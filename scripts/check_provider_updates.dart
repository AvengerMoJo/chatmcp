// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io' as io;

/// Hard-skip these providers when populating the bundled model_capabilities.json.
/// These are routing/aggregator layers whose models are duplicates of entries
/// already under the actual upstream provider on models.dev. They remain valid
/// provider choices in `providers.json` and `defaultApiSettings`; users picking
/// them get their model list from the runtime models.dev fetch.
const _skipProviders = {'openrouter'};

/// Cap models per provider in the bundled snapshot. The runtime `ModelRegistry`
/// is unaffected — it always sees the full picture from its own models.dev
/// fetch + disk cache. This cap only constrains what we ship in the APK so the
/// fallback file stays small (~30 KB instead of ~280 KB).
const _maxModelsPerProvider = 5;

/// Only include models whose `status` matches. models.dev uses 'active' for
/// production models; 'alpha'/'beta'/'deprecated' are skipped by default.
const _allowedStatuses = {'active', 'production'};

/// Checks public provider APIs for new/updated models and compares them
/// against the bundled model_capabilities.json and providers.json manifests.
///
/// Usage:
///   dart run scripts/check_provider_updates.dart                     # dry-run
///   dart run scripts/check_provider_updates.dart --apply             # write changes
///   dart run scripts/check_provider_updates.dart --report out.txt    # save report
///   dart run scripts/check_provider_updates.dart --check             # exit 2 on downgrades
void main(List<String> args) async {
  final apply = args.contains('--apply');
  final check = args.contains('--check');

  String? reportPath;
  final reportIdx = args.indexOf('--report');
  if (reportIdx != -1 && reportIdx + 1 < args.length) {
    reportPath = args[reportIdx + 1];
  }

  final scriptDir = io.Platform.script.toFilePath();
  final projectRoot = io.File(scriptDir).parent.parent.path;
  final capabilitiesPath = '$projectRoot/assets/model_capabilities.json';
  final providersPath = '$projectRoot/assets/providers.json';
  final settingsPath = '$projectRoot/lib/provider/settings_provider.dart';

  final capabilitiesFile = io.File(capabilitiesPath);
  if (!await capabilitiesFile.exists()) {
    io.stderr.writeln('ERROR: $capabilitiesPath not found');
    io.exitCode = 1;
    return;
  }

  final providersFile = io.File(providersPath);
  if (!await providersFile.exists()) {
    // First-run seed — empty manifest so the writer can populate it.
    await providersFile.writeAsString('{}\n');
  }

  final bundled = _loadBundled(await capabilitiesFile.readAsString());
  final bundledModels = Map<String, dynamic>.from(bundled['models'] ?? {});
  final bundledProvidersDoc = _loadBundled(await providersFile.readAsString());
  final bundledProviders = Map<String, dynamic>.from(bundledProvidersDoc['providers'] ?? {});

  // Extract provider IDs from settings_provider.dart (#7: single source of truth).
  final allowedProviders = await _extractProviderIds(settingsPath);
  if (allowedProviders.isEmpty) {
    io.stderr.writeln('WARNING: could not parse provider IDs from $settingsPath');
    io.stderr.writeln('  Falling back to empty provider set — only Gemini will be checked.');
  }

  // --- Fetch from public APIs (single pass) ---
  final Map<String, Map<String, dynamic>> fetched = {};
  Map<String, dynamic>? modelsDevRoot;

  final rawRoot = await _fetchModelsDevRoot();
  if (rawRoot != null) {
    modelsDevRoot = rawRoot;
    final modelsDev = parseModelsDev(rawRoot, allowedProviders);
    fetched.addAll(modelsDev);
    print('Fetched ${modelsDev.length} models from models.dev');
  } else {
    print('WARNING: models.dev fetch failed, skipping');
  }

  final gemini = await _fetchGeminiModels();
  if (gemini != null) {
    for (final entry in gemini.entries) {
      fetched.putIfAbsent(entry.key, () => entry.value);
    }
    print('Fetched ${gemini.length} models from Gemini API');
  } else {
    print('WARNING: Gemini API fetch failed, skipping');
  }

  // --- Model diff ---
  final modelDiff = computeDiff(bundledModels, fetched);

  // --- Provider manifest pass (only when models.dev is available) ---
  Map<String, Map<String, dynamic>> fetchedProviders = {};
  if (modelsDevRoot != null) {
    fetchedProviders = parseProviderManifest(modelsDevRoot, allowedProviders);
    print('Computed manifest for ${fetchedProviders.length} providers from models.dev');
  }

  // --- Provider diff ---
  final providerDiff = computeProviderDiff(bundledProviders, fetchedProviders);

  // --- Report ---
  final report = formatReport(
    modelDiff,
    bundledModels,
    fetched,
    providerDiff: providerDiff,
    bundledProviders: bundledProviders,
    fetchedProviders: fetchedProviders,
  );
  print(report);

  if (reportPath != null) {
    await io.File(reportPath).writeAsString(report);
    print('Report saved to $reportPath');
  }

  // --- Check mode: exit 2 if any capabilities were downgraded ---
  if (check && modelDiff.downgrades.isNotEmpty) {
    print('');
    print('DOWNGRADES DETECTED (${modelDiff.downgrades.length}):');
    for (final d in modelDiff.downgrades) {
      print('  $d');
    }
    io.exitCode = 2;
    return;
  }

  final anyChanges = modelDiff.hasChanges || providerDiff.hasChanges;

  // --- Apply ---
  if (apply && anyChanges) {
    if (modelDiff.hasChanges) {
      final merged = applyDiff(bundled, bundledModels, modelDiff, fetched);
      final encoder = JsonEncoder.withIndent('  ');
      await capabilitiesFile.writeAsString('${encoder.convert(merged)}\n');
      print('Wrote ${modelDiff.newModels.length + modelDiff.updatedModels.length} changes to $capabilitiesPath');
    }
    if (providerDiff.hasChanges) {
      final mergedProviders = applyProviderDiff(bundledProvidersDoc, bundledProviders, providerDiff, fetchedProviders);
      final encoder = JsonEncoder.withIndent('  ');
      await providersFile.writeAsString('${encoder.convert(mergedProviders)}\n');
      print('Wrote ${providerDiff.newProviders.length + providerDiff.updatedProviders.length} changes to $providersPath');
    }
  } else if (!apply && anyChanges) {
    print('Dry run. Use --apply to write changes.');
  }

  // Exit 0 = no changes, 1 = changes found.
  // In the GitHub Actions workflow this exit code is intentionally || true-swallowed
  // so the job continues to the apply/PR steps regardless.
  io.exitCode = anyChanges ? 1 : 0;
}

// ---------------------------------------------------------------------------
// Provider ID extraction (#7: single source of truth)
// ---------------------------------------------------------------------------

/// Parses `settings_provider.dart` to extract all `providerId:` values.
/// This keeps the script in sync with defaultApiSettings without duplication.
Future<Set<String>> _extractProviderIds(String settingsPath) async {
  final file = io.File(settingsPath);
  if (!await file.exists()) return {};
  final content = await file.readAsString();

  final ids = <String>{};
  // Match providerId: 'xxx' or providerId: "xxx"
  final re = RegExp(r"""providerId:\s*['"]([^'"]+)['"]""");
  for (final match in re.allMatches(content)) {
    ids.add(match.group(1)!);
  }

  // Add known models.dev aliases that differ from our providerId.
  // Our "claude" → models.dev "anthropic"
  // Our "gemini" → models.dev "google"
  // Our "glm"    → models.dev "zai" / "zai-coding-plan"
  // Our "mimo"   → models.dev "xiaomi" / "xiaomi-token-plan-*"
  // Our "minimax" → models.dev "minimax"
  // Our "moonshot" → models.dev "moonshotai"
  const aliases = {
    'anthropic', // claude
    'google', // gemini
    'zai',
    'zai-coding-plan', // glm
    'xiaomi',
    'xiaomi-token-plan-cn',
    'xiaomi-token-plan-sgp',
    'xiaomi-token-plan-ams', // mimo
    'moonshotai', // moonshot
  };

  return ids.union(aliases);
}

// ---------------------------------------------------------------------------
// Diff model
// ---------------------------------------------------------------------------

class ModelDiff {
  final List<String> newModels;
  final List<String> updatedModels;
  final List<String> downgrades;

  const ModelDiff({required this.newModels, required this.updatedModels, required this.downgrades});

  bool get hasChanges => newModels.isNotEmpty || updatedModels.isNotEmpty;
}

/// Pure function: computes diff between bundled and fetched models.
/// Testable in isolation.
ModelDiff computeDiff(Map<String, dynamic> bundledModels, Map<String, Map<String, dynamic>> fetched) {
  final newModels = <String>[];
  final updatedModels = <String>[];
  final downgrades = <String>[];

  final sortedKeys = fetched.keys.toList()..sort();

  for (final key in sortedKeys) {
    final incoming = fetched[key]!;
    if (!bundledModels.containsKey(key)) {
      newModels.add(key);
    } else {
      final existing = bundledModels[key]!;
      if (hasCapabilityChanged(existing, incoming)) {
        updatedModels.add(key);
        // Detect downgrades for --check mode.
        final downgrade = _detectDowngrade(existing, incoming);
        if (downgrade != null) {
          downgrades.add('$key: $downgrade');
        }
      }
    }
  }

  return ModelDiff(newModels: newModels, updatedModels: updatedModels, downgrades: downgrades);
}

/// Merges diff results into the bundled JSON, preserving custom fields (#8).
Map<String, dynamic> applyDiff(
  Map<String, dynamic> bundled,
  Map<String, dynamic> bundledModels,
  ModelDiff diff,
  Map<String, Map<String, dynamic>> fetched,
) {
  final mergedModels = Map<String, dynamic>.from(bundledModels);

  for (final key in diff.newModels) {
    mergedModels[key] = fetched[key]!;
  }
  for (final key in diff.updatedModels) {
    final existing = mergedModels[key];
    final incoming = fetched[key]!;
    // Preserve custom fields (notes, source, deprecation, etc.) by merging
    // incoming over existing rather than replacing wholesale.
    if (existing is Map<String, dynamic>) {
      mergedModels[key] = _mergePreservingExtras(existing, incoming);
    } else {
      mergedModels[key] = incoming;
    }
  }

  // Build output preserving _doc and _format_version at top.
  final sorted = <String, dynamic>{};
  for (final k in bundled.keys.where((k) => k.startsWith('_'))) {
    sorted[k] = bundled[k];
  }
  final modelKeys = mergedModels.keys.toList()..sort();
  sorted['models'] = <String, dynamic>{};
  for (final k in modelKeys) {
    sorted['models'][k] = mergedModels[k];
  }
  return sorted;
}

/// Merges [incoming] over [existing], preserving any extra keys that exist
/// in [incoming] but not in [existing] (e.g. notes, source, deprecation).
Map<String, dynamic> _mergePreservingExtras(Map<String, dynamic> existing, Map<String, dynamic> incoming) {
  final result = Map<String, dynamic>.from(incoming);
  for (final key in existing.keys) {
    if (!result.containsKey(key)) {
      result[key] = existing[key];
    } else if (existing[key] is Map && result[key] is Map) {
      result[key] = _mergePreservingExtras(Map<String, dynamic>.from(existing[key] as Map), Map<String, dynamic>.from(result[key] as Map));
    }
  }
  return result;
}

// ---------------------------------------------------------------------------
// Report formatting
// ---------------------------------------------------------------------------

/// Pure function: formats a diff report as a string.
String formatReport(
  ModelDiff diff,
  Map<String, dynamic> bundledModels,
  Map<String, Map<String, dynamic>> fetched, {
  ProviderDiff providerDiff = const ProviderDiff(newProviders: [], updatedProviders: []),
  Map<String, dynamic> bundledProviders = const {},
  Map<String, Map<String, dynamic>> fetchedProviders = const {},
}) {
  final buf = StringBuffer();

  if (!diff.hasChanges && !providerDiff.hasChanges) {
    buf.writeln('No changes — model_capabilities.json and providers.json are up to date.');
    return buf.toString();
  }

  if (diff.newModels.isNotEmpty) {
    buf.writeln('=== NEW MODELS (${diff.newModels.length}) ===');
    for (final key in diff.newModels) {
      final m = fetched[key]!;
      final ctx = m['limit']?['context'];
      final out = m['limit']?['output'];
      final tc = m['capabilities']?['tool_call'];
      final re = m['capabilities']?['reasoning'];
      buf.writeln('  $key  ctx=$ctx out=$out tool_call=$tc reasoning=$re');
    }
    buf.writeln('');
  }

  if (diff.updatedModels.isNotEmpty) {
    buf.writeln('=== UPDATED MODELS (${diff.updatedModels.length}) ===');
    for (final key in diff.updatedModels) {
      final old = bundledModels[key];
      final nw = fetched[key]!;
      final oldCtx = old['limit']?['context'];
      final newCtx = nw['limit']?['context'];
      final oldOut = old['limit']?['output'];
      final newOut = nw['limit']?['output'];
      buf.writeln('  $key  ctx=$oldCtx→$newCtx out=$oldOut→$newOut');
    }
    buf.writeln('');
  }

  if (providerDiff.hasChanges) {
    if (providerDiff.newProviders.isNotEmpty) {
      buf.writeln('=== NEW PROVIDERS (${providerDiff.newProviders.length}) ===');
      for (final key in providerDiff.newProviders) {
        final p = fetchedProviders[key]!;
        buf.writeln('  $key  name=${p['name']} models=${p['modelCount']} maxCtx=${p['maxContextWindow']}');
      }
      buf.writeln('');
    }
    if (providerDiff.updatedProviders.isNotEmpty) {
      buf.writeln('=== UPDATED PROVIDERS (${providerDiff.updatedProviders.length}) ===');
      for (final key in providerDiff.updatedProviders) {
        final old = bundledProviders[key];
        final nw = fetchedProviders[key]!;
        final oldMax = old is Map ? old['maxContextWindow'] : null;
        final newMax = nw['maxContextWindow'];
        final oldIn = old is Map ? (old['modalities']?['input'] as List?)?.join('+') : null;
        final newIn = (nw['modalities']?['input'] as List?)?.join('+');
        buf.writeln('  $key  maxCtx=$oldMax→$newMax input=$oldIn→$newIn');
      }
    }
  }

  return buf.toString();
}

// ---------------------------------------------------------------------------
// Data loading
// ---------------------------------------------------------------------------

Map<String, dynamic> _loadBundled(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map<String, dynamic>) {
    throw FormatException('Expected JSON object at root');
  }
  return decoded;
}

// ---------------------------------------------------------------------------
// models.dev
// ---------------------------------------------------------------------------

/// Fetches the raw models.dev root so callers can do both the model pass
/// and the provider-manifest pass without re-fetching.
Future<Map<String, dynamic>?> _fetchModelsDevRoot() async {
  try {
    final client = io.HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.parse('https://models.dev/api.json'));
      req.headers.set('User-Agent', 'chatmcp/check_provider_updates (https://github.com/chatmcpclient/chatmcp)');
      req.headers.set('Accept', 'application/json');
      final resp = await req.close().timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) {
        io.stderr.writeln('  models.dev HTTP ${resp.statusCode}');
        return null;
      }
      final body = await resp.transform(utf8.decoder).join();
      final json = jsonDecode(body);
      if (json is! Map<String, dynamic>) return null;
      return json;
    } finally {
      client.close(force: true);
    }
  } catch (e) {
    io.stderr.writeln('  models.dev error: $e');
    return null;
  }
}

/// Pure function: parses models.dev API response.
///
/// Applies the bundled-snapshot filter: skips hard-coded provider ids
/// (aggregators), drops models whose status is not in [_allowedStatuses],
/// and caps per-provider to [_maxModelsPerProvider] entries by recency.
///
/// Testable in isolation.
Map<String, Map<String, dynamic>> parseModelsDev(Map<String, dynamic> root, Set<String> allowedProviders) {
  final result = <String, Map<String, dynamic>>{};

  for (final provEntry in root.entries) {
    final provId = provEntry.key;
    if (!allowedProviders.contains(provId)) continue;
    if (_skipProviders.contains(provId)) continue;
    final prov = provEntry.value;
    if (prov is! Map) continue;
    final models = prov['models'];
    if (models is! Map) continue;

    final selected = _selectModelsForBundle(models);

    for (final modelEntry in selected.entries) {
      final m = modelEntry.value;

      final modelId = m['id'] ?? modelEntry.key;
      final key = '$provId/$modelId';

      result[key] = {
        'family': m['family'],
        'status': 'active',
        'limit': {
          if (m['limit']?['context'] != null) 'context': m['limit']['context'],
          if (m['limit']?['output'] != null) 'output': m['limit']['output'],
        },
        'modalities':
            m['modalities'] ??
            {
              'input': ['text'],
              'output': ['text'],
            },
        'capabilities': {'tool_call': m['tool_call'] == true, 'reasoning': m['reasoning'] == true, 'attachment': m['attachment'] == true},
      };
    }
  }

  return result;
}

/// Pure function: filters and ranks a provider's models for inclusion in the
/// bundled snapshot. Drops models whose `status` is not in
/// [_allowedStatuses] (or has no status field, treated as unknown → skip),
/// then keeps the [_maxModelsPerProvider] newest by `release_date`, then
/// `last_updated`, then map key.
Map<String, Map<String, dynamic>> _selectModelsForBundle(Map<dynamic, dynamic> providerModels) {
  final filtered = <MapEntry<String, Map<String, dynamic>>>[];
  for (final entry in providerModels.entries) {
    final m = entry.value;
    if (m is! Map) continue;
    final status = m['status'];
    if (status != null && status is String && !_allowedStatuses.contains(status)) {
      continue;
    }
    filtered.add(MapEntry(entry.key.toString(), Map<String, dynamic>.from(m)));
  }

  filtered.sort((a, b) {
    final aDate = a.value['release_date'] ?? a.value['last_updated'] ?? '';
    final bDate = b.value['release_date'] ?? b.value['last_updated'] ?? '';
    final cmp = bDate.toString().compareTo(aDate.toString());
    if (cmp != 0) return cmp;
    return a.key.compareTo(b.key);
  });

  if (filtered.length <= _maxModelsPerProvider) {
    return Map.fromEntries(filtered);
  }
  return Map.fromEntries(filtered.take(_maxModelsPerProvider));
}

// ---------------------------------------------------------------------------
// Gemini API
// ---------------------------------------------------------------------------

Future<Map<String, Map<String, dynamic>>?> _fetchGeminiModels() async {
  try {
    final client = io.HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models');
      final req = await client.getUrl(url);
      req.headers.set('User-Agent', 'chatmcp/check_provider_updates (https://github.com/chatmcpclient/chatmcp)');
      req.headers.set('Accept', 'application/json');
      final resp = await req.close().timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) {
        io.stderr.writeln('  Gemini API HTTP ${resp.statusCode}');
        return null;
      }
      final body = await resp.transform(utf8.decoder).join();
      final json = jsonDecode(body);
      if (json is! Map<String, dynamic>) return null;
      return parseGeminiResponse(json);
    } finally {
      client.close(force: true);
    }
  } catch (e) {
    io.stderr.writeln('  Gemini API error: $e');
    return null;
  }
}

/// Pure function: parses Gemini models API response.
/// Testable in isolation.
Map<String, Map<String, dynamic>> parseGeminiResponse(Map<String, dynamic> root) {
  final result = <String, Map<String, dynamic>>{};
  final models = root['models'];
  if (models is! List) return result;

  for (final m in models) {
    if (m is! Map) continue;
    final name = m['name'] as String?;
    if (name == null) continue;

    // name is "models/gemini-2.0-flash" — strip prefix.
    final modelName = name.contains('/') ? name.split('/').last : name;
    final key = 'google/$modelName';

    final inputLimit = m['inputTokenLimit'];
    final outputLimit = m['outputTokenLimit'];
    final methods = m['supportedGenerationMethods'] as List?;

    result[key] = {
      'family': 'gemini',
      'status': 'active',
      'limit': {if (inputLimit != null) 'context': inputLimit, if (outputLimit != null) 'output': outputLimit},
      'modalities': {
        'input': ['text', 'image'],
        'output': ['text'],
      },
      'capabilities': {'tool_call': methods != null && methods.contains('generateContent'), 'reasoning': false, 'attachment': true},
    };
  }

  return result;
}

// ---------------------------------------------------------------------------
// Diff helpers
// ---------------------------------------------------------------------------

/// Pure function: checks if capabilities changed between existing and incoming.
/// Testable in isolation.
bool hasCapabilityChanged(dynamic existing, Map<String, dynamic> incoming) {
  if (existing is! Map) return true;

  final eLimit = existing['limit'];
  final iLimit = incoming['limit'];
  if (eLimit is Map && iLimit is Map) {
    if (eLimit['context'] != iLimit['context']) return true;
    if (eLimit['output'] != iLimit['output']) return true;
  }

  final eCaps = existing['capabilities'];
  final iCaps = incoming['capabilities'];
  if (eCaps is Map && iCaps is Map) {
    if (eCaps['tool_call'] != iCaps['tool_call']) return true;
    if (eCaps['reasoning'] != iCaps['reasoning']) return true;
    if (eCaps['attachment'] != iCaps['attachment']) return true;
  }

  return false;
}

/// Returns a human-readable downgrade description, or null if no downgrade.
String? _detectDowngrade(dynamic existing, Map<String, dynamic> incoming) {
  if (existing is! Map) return null;

  final parts = <String>[];

  final eLimit = existing['limit'];
  final iLimit = incoming['limit'];
  if (eLimit is Map && iLimit is Map) {
    final eCtx = eLimit['context'] as num?;
    final iCtx = iLimit['context'] as num?;
    if (eCtx != null && iCtx != null && iCtx < eCtx) {
      parts.add('context ${eCtx}→$iCtx');
    }
    final eOut = eLimit['output'] as num?;
    final iOut = iLimit['output'] as num?;
    if (eOut != null && iOut != null && iOut < eOut) {
      parts.add('output ${eOut}→$iOut');
    }
  }

  final eCaps = existing['capabilities'];
  final iCaps = incoming['capabilities'];
  if (eCaps is Map && iCaps is Map) {
    if (eCaps['tool_call'] == true && iCaps['tool_call'] == false) {
      parts.add('tool_call lost');
    }
    if (eCaps['reasoning'] == true && iCaps['reasoning'] == false) {
      parts.add('reasoning lost');
    }
    if (eCaps['attachment'] == true && iCaps['attachment'] == false) {
      parts.add('attachment lost');
    }
  }

  return parts.isEmpty ? null : parts.join(', ');
}

// ---------------------------------------------------------------------------
// Provider manifest (assets/providers.json)
// ---------------------------------------------------------------------------

class ProviderDiff {
  final List<String> newProviders;
  final List<String> updatedProviders;

  const ProviderDiff({required this.newProviders, required this.updatedProviders});

  bool get hasChanges => newProviders.isNotEmpty || updatedProviders.isNotEmpty;
}

/// Pure function: derives a per-provider manifest from the raw models.dev root.
///
/// Aggregates over **all** models a provider exposes upstream, not just the
/// filtered subset that lands in the bundled model snapshot. The bundle is a
/// cold-start fallback; the manifest is a truthful description of what the
/// provider offers at runtime.
///
/// Per-provider fields:
///   - identity: id, name, doc, npm, api (from models.dev provider entry)
///   - aggregates over the provider's models:
///       * modalities.input / output (union, sorted, deduped)
///       * maxContextWindow (max of limit.context across models)
///       * modelCount
///   - source: "models.dev"
Map<String, Map<String, dynamic>> parseProviderManifest(Map<String, dynamic> rawRoot, Set<String> allowedProviders) {
  final result = <String, Map<String, dynamic>>{};

  for (final provEntry in rawRoot.entries) {
    final provId = provEntry.key;
    if (!allowedProviders.contains(provId)) continue;
    final prov = provEntry.value;
    if (prov is! Map) continue;

    final provMap = Map<String, dynamic>.from(prov);
    final models = provMap['models'];
    if (models is! Map) continue;

    final inputMods = <String>{};
    final outputMods = <String>{};
    int? maxCtx;
    int modelCount = 0;

    for (final entry in models.entries) {
      final m = entry.value;
      if (m is! Map) continue;
      modelCount++;

      final mods = m['modalities'];
      if (mods is Map) {
        final inp = mods['input'];
        if (inp is List) {
          for (final v in inp) {
            if (v is String) inputMods.add(v);
          }
        }
        final outp = mods['output'];
        if (outp is List) {
          for (final v in outp) {
            if (v is String) outputMods.add(v);
          }
        }
      }

      final limit = m['limit'];
      if (limit is Map) {
        final ctx = limit['context'];
        if (ctx is num) {
          final asInt = ctx.toInt();
          if (maxCtx == null || asInt > maxCtx) maxCtx = asInt;
        }
      }
    }

    result[provId] = {
      'name': provMap['name'] ?? provId,
      if (provMap['doc'] != null) 'doc': provMap['doc'],
      if (provMap['npm'] != null) 'npm': provMap['npm'],
      if (provMap['api'] != null) 'api': provMap['api'],
      'modalities': {'input': inputMods.toList()..sort(), 'output': outputMods.toList()..sort()},
      if (maxCtx != null) 'maxContextWindow': maxCtx,
      'modelCount': modelCount,
      'source': 'models.dev',
    };
  }

  return result;
}

/// Pure function: diffs existing vs fetched provider manifests.
ProviderDiff computeProviderDiff(Map<String, dynamic> bundledProviders, Map<String, Map<String, dynamic>> fetchedProviders) {
  final newProviders = <String>[];
  final updatedProviders = <String>[];
  final sortedKeys = fetchedProviders.keys.toList()..sort();

  for (final key in sortedKeys) {
    final incoming = fetchedProviders[key]!;
    if (!bundledProviders.containsKey(key)) {
      newProviders.add(key);
    } else if (hasProviderManifestChanged(bundledProviders[key], incoming)) {
      updatedProviders.add(key);
    }
  }

  return ProviderDiff(newProviders: newProviders, updatedProviders: updatedProviders);
}

/// Pure function: true if any tracked field of the provider manifest changed.
bool hasProviderManifestChanged(dynamic existing, Map<String, dynamic> incoming) {
  if (existing is! Map) return true;

  // Identity fields.
  for (final k in ['name', 'doc', 'npm', 'api']) {
    if (existing[k] != incoming[k]) return true;
  }

  // Aggregates.
  if (existing['maxContextWindow'] != incoming['maxContextWindow']) return true;
  if (existing['modelCount'] != incoming['modelCount']) return true;

  // Modalities: compare as sorted sets (order is canonicalization, not data).
  final eMods = existing['modalities'];
  final iMods = incoming['modalities'];
  if (eMods is Map && iMods is Map) {
    for (final k in ['input', 'output']) {
      final eList = eMods[k];
      final iList = iMods[k];
      if (eList is List && iList is List) {
        final eSorted = (eList as List).map((e) => e.toString()).toList()..sort();
        final iSorted = (iList as List).map((e) => e.toString()).toList()..sort();
        if (eSorted.length != iSorted.length) return true;
        for (var i = 0; i < eSorted.length; i++) {
          if (eSorted[i] != iSorted[i]) return true;
        }
      } else if (eList != iList) {
        return true;
      }
    }
  }

  return false;
}

/// Merges provider diff into the bundled providers.json document,
/// preserving custom fields on existing entries.
Map<String, dynamic> applyProviderDiff(
  Map<String, dynamic> bundledDoc,
  Map<String, dynamic> bundledProviders,
  ProviderDiff diff,
  Map<String, Map<String, dynamic>> fetched,
) {
  final merged = Map<String, dynamic>.from(bundledProviders);

  for (final key in diff.newProviders) {
    merged[key] = fetched[key]!;
  }
  for (final key in diff.updatedProviders) {
    final existing = merged[key];
    final incoming = fetched[key]!;
    if (existing is Map<String, dynamic>) {
      merged[key] = _mergePreservingExtras(existing, incoming);
    } else {
      merged[key] = incoming;
    }
  }

  final out = <String, dynamic>{};
  for (final k in bundledDoc.keys.where((k) => k.startsWith('_'))) {
    out[k] = bundledDoc[k];
  }
  out.putIfAbsent(
    '_doc',
    () =>
        'Bundled provider display info, derived weekly from models.dev per-model aggregates. '
        'Keys mirror the provider id used as a prefix in model_capabilities.json. '
        'The `api` field is informational only — user routing endpoint lives in LLMProviderSetting.',
  );
  out.putIfAbsent('_format_version', () => 1);
  final sortedProviderKeys = merged.keys.toList()..sort();
  out['providers'] = <String, dynamic>{};
  for (final k in sortedProviderKeys) {
    out['providers'][k] = merged[k];
  }
  return out;
}
