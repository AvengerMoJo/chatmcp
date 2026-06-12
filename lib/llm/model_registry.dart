import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'model.dart';

/// Source identifier for [ModelCapabilities.source].
class ModelCapabilitySource {
  static const String bundled = 'bundled';
  static const String modelsDev = 'models.dev';
  static const String unknown = 'unknown';
}

/// Resolves [ModelCapabilities] for a given model name from a layered cache.
///
/// Resolution order (first hit wins):
///   1. Per-model override in bundled `assets/model_capabilities.json`
///   2. `models.dev` cache on disk (TTL: 7 days)
///   3. `models.dev` live fetch (5s timeout, best-effort)
///   4. `null` — caller decides what to show
class ModelRegistry {
  ModelRegistry._();
  static final ModelRegistry instance = ModelRegistry._();

  static const String modelsDevUrl = 'https://models.dev/api.json';
  static const Duration cacheTtl = Duration(days: 7);
  static const Duration fetchTimeout = Duration(seconds: 5);

  final Logger _log = Logger.root;
  final Map<String, ModelCapabilities> _bundled = {};
  Map<String, dynamic>? _modelsDev;
  DateTime? _modelsDevFetchedAt;
  Future<void>? _loading;

  /// Override the disk cache directory. Used in tests to avoid `path_provider`.
  /// If unset, the registry resolves the directory via `getApplicationDocumentsDirectory()`.
  io.Directory? cacheDirectoryOverride;

  /// Load the bundled fallback snapshot from `assets/model_capabilities.json`.
  ///
  /// Call once at app startup. Safe to call multiple times.
  Future<void> loadBundled({String assetPath = 'assets/model_capabilities.json', Future<String> Function(String)? assetLoader}) async {
    if (_bundled.isNotEmpty) return;
    try {
      final raw = assetLoader != null
          ? await assetLoader(assetPath)
          : await _loadAssetDefault(assetPath);
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return;

      final models = json['models'];
      if (models is! Map) return;

      for (final entry in models.entries) {
        if (entry.value is! Map<String, dynamic>) continue;
        final m = Map<String, dynamic>.from(entry.value);
        // Force the source label so we always know when something came from the bundle.
        m['source'] = ModelCapabilitySource.bundled;
        _bundled[entry.key.toString()] = ModelCapabilities.fromJson(m);
      }
      _log.info('ModelRegistry: loaded ${_bundled.length} bundled capabilities');
    } catch (e) {
      _log.warning('ModelRegistry: failed to load bundled capabilities: $e');
    }
  }

  /// Resolve capabilities for a model name.
  ///
  /// [providerId] is optional and is only used to disambiguate when the same
  /// model name appears under multiple providers (e.g. `claude-3-5-sonnet`).
  /// When omitted, the first match wins.
  Future<ModelCapabilities?> enrich(String modelName, {String? providerId}) async {
    if (modelName.isEmpty) return null;

    // 1. Bundled — keyed as "provider/model" or "model" if unique.
    final bundledKey = providerId != null ? '$providerId/$modelName' : modelName;
    final bundled = _bundled[bundledKey] ?? _bundled[modelName];
    if (bundled != null) return bundled;

    // 2 + 3. models.dev — best effort, never throws.
    final live = await _ensureModelsDev();
    if (live == null) return null;
    return _lookupModelsDev(live, modelName, providerId: providerId);
  }

  /// Look up capabilities across both bundled and models.dev, returning the
  /// bundled entry first when both exist. Intended for batch use in the
  /// model selector UI.
  Future<ModelCapabilities?> lookup(String modelName, {String? providerId}) => enrich(modelName, providerId: providerId);

  // ---------------------------------------------------------------------------
  // models.dev
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>?> _ensureModelsDev() async {
    final now = DateTime.now();
    if (_modelsDev != null && _modelsDevFetchedAt != null && now.difference(_modelsDevFetchedAt!) < cacheTtl) {
      return _modelsDev;
    }

    // Coalesce concurrent calls.
    if (_loading != null) {
      await _loading;
      return _modelsDev;
    }
    _loading = _refreshModelsDev();
    try {
      await _loading;
    } finally {
      _loading = null;
    }
    return _modelsDev;
  }

  Future<void> _refreshModelsDev() async {
    // Try disk cache first; if fresh enough, skip the network entirely.
    try {
      final cached = await _readDiskCache();
      if (cached != null) {
        final fetchedAt = cached.fetchedAt;
        if (DateTime.now().difference(fetchedAt) < cacheTtl) {
          _modelsDev = cached.data;
          _modelsDevFetchedAt = fetchedAt;
          return;
        }
      }
    } catch (e) {
      _log.fine('ModelRegistry: disk cache read failed: $e');
    }

    // Best-effort network fetch.
    try {
      final fetched = await _fetchModelsDev().timeout(fetchTimeout);
      _modelsDev = fetched;
      _modelsDevFetchedAt = DateTime.now();
      await _writeDiskCache(fetched);
    } catch (e) {
      _log.fine('ModelRegistry: models.dev fetch failed, falling back to cache: $e');
      // Even on failure, try to use stale cache.
      final cached = await _readDiskCache();
      if (cached != null) {
        _modelsDev = cached.data;
        _modelsDevFetchedAt = cached.fetchedAt;
      }
    }
  }

  Future<Map<String, dynamic>> _fetchModelsDev() async {
    final client = io.HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final req = await client.getUrl(Uri.parse(modelsDevUrl));
      req.headers.set('User-Agent', 'chatmcp/ModelRegistry');
      req.headers.set('Accept', 'application/json');
      final resp = await req.close().timeout(fetchTimeout);
      if (resp.statusCode != 200) {
        throw io.HttpException('models.dev HTTP ${resp.statusCode}');
      }
      final body = await resp.transform(utf8.decoder).join();
      final json = jsonDecode(body);
      if (json is! Map<String, dynamic>) {
        throw const FormatException('models.dev: expected object at root');
      }
      return json;
    } finally {
      client.close(force: true);
    }
  }

  ModelCapabilities? _lookupModelsDev(Map<String, dynamic> root, String modelName, {String? providerId}) {
    final providers = root;
    Map<String, dynamic>? matchedModel;

    if (providerId != null && providers[providerId] is Map) {
      final prov = Map<String, dynamic>.from(providers[providerId]);
      final models = prov['models'];
      if (models is Map && models[modelName] is Map) {
        matchedModel = Map<String, dynamic>.from(models[modelName]);
      }
    }

    matchedModel ??= _scanAllProviders(providers, modelName);
    if (matchedModel == null) return null;

    matchedModel['source'] = ModelCapabilitySource.modelsDev;
    return ModelCapabilities.fromJson(matchedModel);
  }

  Map<String, dynamic>? _scanAllProviders(Map<String, dynamic> root, String modelName) {
    for (final provEntry in root.entries) {
      if (provEntry.value is! Map) continue;
      final models = (provEntry.value as Map)['models'];
      if (models is! Map) continue;
      if (models[modelName] is Map) {
        return Map<String, dynamic>.from(models[modelName]);
      }
      // Case-insensitive fallback.
      for (final m in models.entries) {
        if (m.key.toString().toLowerCase() == modelName.toLowerCase() && m.value is Map) {
          return Map<String, dynamic>.from(m.value);
        }
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Disk cache
  // ---------------------------------------------------------------------------

  Future<_CacheFile?> _readDiskCache() async {
    final dir = await _cacheDir();
    final file = io.File(p.join(dir.path, 'models_dev.json'));
    if (!await file.exists()) return null;
    try {
      final raw = await file.readAsString();
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      final fetchedAtStr = json['fetched_at'] as String?;
      final data = json['data'];
      if (fetchedAtStr == null || data is! Map<String, dynamic>) return null;
      return _CacheFile(data: data, fetchedAt: DateTime.parse(fetchedAtStr));
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeDiskCache(Map<String, dynamic> data) async {
    final dir = await _cacheDir();
    final file = io.File(p.join(dir.path, 'models_dev.json'));
    final payload = jsonEncode({
      'fetched_at': DateTime.now().toIso8601String(),
      'data': data,
    });
    // Atomic-ish: write to .tmp then rename.
    final tmp = io.File(p.join(dir.path, 'models_dev.json.tmp'));
    await tmp.writeAsString(payload);
    await tmp.rename(file.path);
  }

  Future<io.Directory> _cacheDir() async {
    final override = cacheDirectoryOverride;
    if (override != null) {
      if (!await override.exists()) await override.create(recursive: true);
      return override;
    }
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final dir = io.Directory(p.join(appDir.path, 'ChatMcp', 'cache'));
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    } catch (_) {
      final tmp = await getTemporaryDirectory();
      final dir = io.Directory(p.join(tmp.path, 'ChatMcp', 'cache'));
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    }
  }

  // ---------------------------------------------------------------------------
  // Bundled asset loading (kept here to keep the registry self-contained)
  // ---------------------------------------------------------------------------

  Future<String> _loadAssetDefault(String assetPath) async {
    // Lazily imported so the registry is unit-testable without Flutter.
    // ignore: avoid_dynamic_calls
    final loader = _rootBundleString;
    if (loader == null) {
      throw StateError('No asset loader registered; call loadBundled(assetLoader: ...) first');
    }
    return loader(assetPath);
  }

  /// Injected by the app layer (e.g. `rootBundle.loadString`). `null` in tests
  /// unless the test passes a custom `assetLoader`.
  static Future<String> Function(String)? _rootBundleString;
  static void registerAssetLoader(Future<String> Function(String) loader) {
    _rootBundleString = loader;
  }
}

class _CacheFile {
  final Map<String, dynamic> data;
  final DateTime fetchedAt;
  _CacheFile({required this.data, required this.fetchedAt});
}
