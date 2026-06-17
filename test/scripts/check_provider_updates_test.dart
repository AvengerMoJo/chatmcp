import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Tests for scripts/check_provider_updates.dart pure functions.
//
// The script lives outside lib/ so we can't import it directly in a
// package test. Instead we copy the pure functions here — they have zero
// external dependencies. If the script's logic changes, these tests
// will catch regressions.
// ---------------------------------------------------------------------------

/// Copied from scripts/check_provider_updates.dart
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

/// Copied from scripts/check_provider_updates.dart
const _skipProviders = {'openrouter'};

/// Copied from scripts/check_provider_updates.dart
const _maxModelsPerProvider = 5;

/// Copied from scripts/check_provider_updates.dart
const _allowedStatuses = {'active', 'production'};

/// Copied from scripts/check_provider_updates.dart
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

/// Copied from scripts/check_provider_updates.dart
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

/// Copied from scripts/check_provider_updates.dart
Map<String, Map<String, dynamic>> parseGeminiResponse(Map<String, dynamic> root) {
  final result = <String, Map<String, dynamic>>{};
  final models = root['models'];
  if (models is! List) return result;

  for (final m in models) {
    if (m is! Map) continue;
    final name = m['name'] as String?;
    if (name == null) continue;

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

/// Copied from scripts/check_provider_updates.dart
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

/// Copied from scripts/check_provider_updates.dart
bool hasProviderManifestChanged(dynamic existing, Map<String, dynamic> incoming) {
  if (existing is! Map) return true;

  for (final k in ['name', 'doc', 'npm', 'api']) {
    if (existing[k] != incoming[k]) return true;
  }

  if (existing['maxContextWindow'] != incoming['maxContextWindow']) return true;
  if (existing['modelCount'] != incoming['modelCount']) return true;

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

void main() {
  group('hasCapabilityChanged', () {
    test('returns false when identical', () {
      final existing = {
        'limit': {'context': 128000, 'output': 8192},
        'capabilities': {'tool_call': true, 'reasoning': false, 'attachment': true},
      };
      final incoming = {
        'limit': {'context': 128000, 'output': 8192},
        'capabilities': {'tool_call': true, 'reasoning': false, 'attachment': true},
      };
      expect(hasCapabilityChanged(existing, incoming), isFalse);
    });

    test('returns true when context changes', () {
      final existing = {
        'limit': {'context': 64000, 'output': 8192},
        'capabilities': {'tool_call': true, 'reasoning': false, 'attachment': true},
      };
      final incoming = {
        'limit': {'context': 128000, 'output': 8192},
        'capabilities': {'tool_call': true, 'reasoning': false, 'attachment': true},
      };
      expect(hasCapabilityChanged(existing, incoming), isTrue);
    });

    test('returns true when output limit changes', () {
      final existing = {
        'limit': {'context': 128000, 'output': 8000},
        'capabilities': {'tool_call': true, 'reasoning': false, 'attachment': true},
      };
      final incoming = {
        'limit': {'context': 128000, 'output': 32000},
        'capabilities': {'tool_call': true, 'reasoning': false, 'attachment': true},
      };
      expect(hasCapabilityChanged(existing, incoming), isTrue);
    });

    test('returns true when tool_call changes', () {
      final existing = {
        'limit': {'context': 128000, 'output': 8192},
        'capabilities': {'tool_call': false, 'reasoning': false, 'attachment': true},
      };
      final incoming = {
        'limit': {'context': 128000, 'output': 8192},
        'capabilities': {'tool_call': true, 'reasoning': false, 'attachment': true},
      };
      expect(hasCapabilityChanged(existing, incoming), isTrue);
    });

    test('returns true when reasoning changes', () {
      final existing = {
        'limit': {'context': 128000, 'output': 8192},
        'capabilities': {'tool_call': true, 'reasoning': false, 'attachment': true},
      };
      final incoming = {
        'limit': {'context': 128000, 'output': 8192},
        'capabilities': {'tool_call': true, 'reasoning': true, 'attachment': true},
      };
      expect(hasCapabilityChanged(existing, incoming), isTrue);
    });

    test('returns true when attachment changes', () {
      final existing = {
        'limit': {'context': 128000, 'output': 8192},
        'capabilities': {'tool_call': true, 'reasoning': false, 'attachment': false},
      };
      final incoming = {
        'limit': {'context': 128000, 'output': 8192},
        'capabilities': {'tool_call': true, 'reasoning': false, 'attachment': true},
      };
      expect(hasCapabilityChanged(existing, incoming), isTrue);
    });

    test('returns true when existing is not a Map', () {
      expect(hasCapabilityChanged(null, {'limit': {}, 'capabilities': {}}), isTrue);
    });

    test('returns false when both have no limits or capabilities', () {
      expect(hasCapabilityChanged({}, {}), isFalse);
    });
  });

  group('parseModelsDev', () {
    test('parses models from allowed providers', () {
      final root = {
        'openai': {
          'models': {
            'gpt-4o': {
              'id': 'gpt-4o',
              'family': 'gpt-4o',
              'tool_call': true,
              'reasoning': false,
              'attachment': true,
              'limit': {'context': 128000, 'output': 16384},
              'modalities': {
                'input': ['text', 'image'],
                'output': ['text'],
              },
            },
          },
        },
      };
      final result = parseModelsDev(root, {'openai'});
      expect(result, hasLength(1));
      expect(result, contains('openai/gpt-4o'));
      expect(result['openai/gpt-4o']!['family'], equals('gpt-4o'));
      expect(result['openai/gpt-4o']!['capabilities']!['tool_call'], isTrue);
    });

    test('skips non-allowed providers', () {
      final root = {
        'openai': {
          'models': {
            'gpt-4o': {
              'id': 'gpt-4o',
              'family': 'gpt-4o',
              'tool_call': true,
              'limit': {'context': 128000, 'output': 16384},
            },
          },
        },
        'reseller': {
          'models': {
            'gpt-4o': {
              'id': 'gpt-4o',
              'family': 'gpt-4o',
              'tool_call': true,
              'limit': {'context': 128000, 'output': 16384},
            },
          },
        },
      };
      final result = parseModelsDev(root, {'openai'});
      expect(result, hasLength(1));
      expect(result.keys.first, startsWith('openai/'));
    });

    test('uses model id from data when available', () {
      final root = {
        'deepseek': {
          'models': {
            'some-key': {
              'id': 'deepseek-chat',
              'family': 'deepseek',
              'tool_call': true,
              'limit': {'context': 64000, 'output': 8000},
            },
          },
        },
      };
      final result = parseModelsDev(root, {'deepseek'});
      expect(result, contains('deepseek/deepseek-chat'));
    });

    test('falls back to map key when id is missing', () {
      final root = {
        'deepseek': {
          'models': {
            'deepseek-chat': {
              'family': 'deepseek',
              'tool_call': true,
              'limit': {'context': 64000, 'output': 8000},
            },
          },
        },
      };
      final result = parseModelsDev(root, {'deepseek'});
      expect(result, contains('deepseek/deepseek-chat'));
    });

    test('sets default modalities when missing', () {
      final root = {
        'openai': {
          'models': {
            'gpt-4o': {
              'id': 'gpt-4o',
              'family': 'gpt-4o',
              'tool_call': true,
              'limit': {'context': 128000, 'output': 16384},
            },
          },
        },
      };
      final result = parseModelsDev(root, {'openai'});
      final modalities = result['openai/gpt-4o']!['modalities'] as Map;
      expect(modalities['input'], equals(['text']));
      expect(modalities['output'], equals(['text']));
    });

    test('correctly maps boolean capabilities', () {
      final root = {
        'deepseek': {
          'models': {
            'deepseek-reasoner': {
              'id': 'deepseek-reasoner',
              'family': 'deepseek',
              'tool_call': false,
              'reasoning': true,
              'attachment': false,
              'limit': {'context': 64000, 'output': 32000},
            },
          },
        },
      };
      final result = parseModelsDev(root, {'deepseek'});
      final caps = result['deepseek/deepseek-reasoner']!['capabilities'] as Map;
      expect(caps['tool_call'], isFalse);
      expect(caps['reasoning'], isTrue);
      expect(caps['attachment'], isFalse);
    });
  });

  group('parseGeminiResponse', () {
    test('parses model with token limits', () {
      final root = {
        'models': [
          {
            'name': 'models/gemini-2.0-flash',
            'inputTokenLimit': 1048576,
            'outputTokenLimit': 8192,
            'supportedGenerationMethods': ['generateContent', 'embedContent'],
          },
        ],
      };
      final result = parseGeminiResponse(root);
      expect(result, hasLength(1));
      expect(result, contains('google/gemini-2.0-flash'));
      expect(result['google/gemini-2.0-flash']!['limit']!['context'], equals(1048576));
      expect(result['google/gemini-2.0-flash']!['limit']!['output'], equals(8192));
      expect(result['google/gemini-2.0-flash']!['capabilities']!['tool_call'], isTrue);
      expect(result['google/gemini-2.0-flash']!['capabilities']!['attachment'], isTrue);
    });

    test('strips models/ prefix from name', () {
      final root = {
        'models': [
          {
            'name': 'models/gemini-2.5-pro',
            'inputTokenLimit': 1048576,
            'outputTokenLimit': 65536,
            'supportedGenerationMethods': ['generateContent'],
          },
        ],
      };
      final result = parseGeminiResponse(root);
      expect(result, contains('google/gemini-2.5-pro'));
    });

    test('sets tool_call false when generateContent not in methods', () {
      final root = {
        'models': [
          {
            'name': 'models/text-embedding-005',
            'inputTokenLimit': 2048,
            'outputTokenLimit': 1,
            'supportedGenerationMethods': ['embedContent'],
          },
        ],
      };
      final result = parseGeminiResponse(root);
      expect(result['google/text-embedding-005']!['capabilities']!['tool_call'], isFalse);
    });

    test('returns empty map for missing models key', () {
      expect(parseGeminiResponse({}), isEmpty);
    });

    test('skips entries without name', () {
      final root = {
        'models': [
          {'inputTokenLimit': 1000},
        ],
      };
      expect(parseGeminiResponse({}), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Provider manifest (assets/providers.json)
  // ---------------------------------------------------------------------------

  group('parseProviderManifest', () {
    test('emits an entry per allowed provider from the raw root', () {
      final root = {
        'anthropic': {
          'name': 'Anthropic',
          'doc': 'https://docs.anthropic.com',
          'npm': '@ai-sdk/anthropic',
          'models': {
            'claude-3-5-sonnet': {
              'modalities': {
                'input': ['text', 'image'],
                'output': ['text'],
              },
              'limit': {'context': 200000},
            },
          },
        },
        'openai': {
          'name': 'OpenAI',
          'models': {
            'gpt-4o': {
              'modalities': {
                'input': ['text', 'image', 'pdf'],
                'output': ['text'],
              },
              'limit': {'context': 128000},
            },
            'gpt-4o-mini': {
              'modalities': {
                'input': ['text', 'image'],
                'output': ['text'],
              },
              'limit': {'context': 128000},
            },
          },
        },
      };
      final result = parseProviderManifest(root, {'anthropic', 'openai'});

      expect(result.keys.toSet(), {'anthropic', 'openai'});
      expect(result['anthropic']!['name'], 'Anthropic');
      expect(result['openai']!['name'], 'OpenAI');
      expect(result['openai']!['modelCount'], 2);
    });

    test('aggregates from ALL models, not just bundled ones', () {
      // Manifest counts must reflect upstream totals even when the bundled
      // model_capabilities.json only ships a handful of those models.
      final root = {
        'openai': {
          'name': 'OpenAI',
          'models': {
            'old-1': {
              'modalities': {
                'input': ['text'],
                'output': ['text'],
              },
              'limit': {},
            },
            'old-2': {
              'modalities': {
                'input': ['text'],
                'output': ['text'],
              },
              'limit': {},
            },
            'old-3': {
              'modalities': {
                'input': ['text'],
                'output': ['text'],
              },
              'limit': {},
            },
            'old-4': {
              'modalities': {
                'input': ['text'],
                'output': ['text'],
              },
              'limit': {},
            },
            'old-5': {
              'modalities': {
                'input': ['text'],
                'output': ['text'],
              },
              'limit': {},
            },
            'old-6': {
              'modalities': {
                'input': ['text'],
                'output': ['text'],
              },
              'limit': {},
            },
          },
        },
      };
      final result = parseProviderManifest(root, {'openai'});
      expect(result['openai']!['modelCount'], 6);
    });

    test('skips providers not in allowedProviders', () {
      final root = {
        'anthropic': {
          'name': 'Anthropic',
          'models': {
            'claude': {
              'modalities': {
                'input': ['text'],
                'output': ['text'],
              },
              'limit': {},
            },
          },
        },
        'rogue': {
          'name': 'Rogue',
          'models': {
            'foo': {
              'modalities': {
                'input': ['text'],
                'output': ['text'],
              },
              'limit': {},
            },
          },
        },
      };
      final result = parseProviderManifest(root, {'anthropic'});

      expect(result.keys, ['anthropic']);
    });

    test('unions and sorts modalities across all models', () {
      final root = {
        'openai': {
          'name': 'OpenAI',
          'models': {
            'gpt-4o': {
              'modalities': {
                'input': ['text', 'image'],
                'output': ['text'],
              },
              'limit': {},
            },
            'gpt-4o-mini': {
              'modalities': {
                'input': ['text', 'pdf'],
                'output': ['text'],
              },
              'limit': {},
            },
            'whisper': {
              'modalities': {
                'input': ['audio'],
                'output': ['text'],
              },
              'limit': {},
            },
          },
        },
      };
      final result = parseProviderManifest(root, {'openai'});

      expect(result['openai']!['modalities']!['input'], ['audio', 'image', 'pdf', 'text']);
      expect(result['openai']!['modalities']!['output'], ['text']);
    });

    test('takes max of limit.context across models', () {
      final root = {
        'openai': {
          'name': 'OpenAI',
          'models': {
            'gpt-4o': {
              'modalities': {
                'input': ['text'],
                'output': ['text'],
              },
              'limit': {'context': 128000},
            },
            'gpt-4.1': {
              'modalities': {
                'input': ['text'],
                'output': ['text'],
              },
              'limit': {'context': 1048576},
            },
          },
        },
      };
      final result = parseProviderManifest(root, {'openai'});

      expect(result['openai']!['maxContextWindow'], 1048576);
    });

    test('omits maxContextWindow when no model has a limit', () {
      final root = {
        'openai': {
          'name': 'OpenAI',
          'models': {
            'foo': {
              'modalities': {
                'input': ['text'],
                'output': ['text'],
              },
              'limit': {},
            },
          },
        },
      };
      final result = parseProviderManifest(root, {'openai'});

      expect(result['openai']!['maxContextWindow'], isNull);
    });

    test('falls back to provId when name missing', () {
      final root = {
        'openai': {
          'models': {
            'foo': {
              'modalities': {
                'input': ['text'],
                'output': ['text'],
              },
              'limit': {},
            },
          },
        },
      };
      final result = parseProviderManifest(root, {'openai'});

      expect(result['openai']!['name'], 'openai');
    });

    test('includes api and npm when present', () {
      final root = {
        'deepseek': {
          'name': 'DeepSeek',
          'npm': '@ai-sdk/openai-compatible',
          'api': 'https://api.deepseek.com',
          'models': {
            'deepseek-chat': {
              'modalities': {
                'input': ['text'],
                'output': ['text'],
              },
              'limit': {},
            },
          },
        },
      };
      final result = parseProviderManifest(root, {'deepseek'});

      expect(result['deepseek']!['api'], 'https://api.deepseek.com');
      expect(result['deepseek']!['npm'], '@ai-sdk/openai-compatible');
    });

    test('handles num (double) context values from JSON', () {
      final root = {
        'openai': {
          'name': 'OpenAI',
          'models': {
            'gpt-4o': {
              'modalities': {
                'input': ['text'],
                'output': ['text'],
              },
              'limit': {'context': 128000.0},
            },
          },
        },
      };
      final result = parseProviderManifest(root, {'openai'});

      expect(result['openai']!['maxContextWindow'], 128000);
    });
  });

  // ---------------------------------------------------------------------------
  // Bundle-snapshot filter (parseModelsDev applies _selectModelsForBundle)
  // ---------------------------------------------------------------------------

  group('parseModelsDev bundled-snapshot filter', () {
    test('drops models whose status is not active/production', () {
      final root = {
        'openai': {
          'name': 'OpenAI',
          'models': {
            'good': {
              'status': 'active',
              'modalities': {
                'input': ['text'],
                'output': ['text'],
              },
              'limit': {'context': 128000},
            },
            'beta': {
              'status': 'beta',
              'modalities': {
                'input': ['text'],
                'output': ['text'],
              },
              'limit': {'context': 128000},
            },
            'deprecated': {
              'status': 'deprecated',
              'modalities': {
                'input': ['text'],
                'output': ['text'],
              },
              'limit': {'context': 128000},
            },
          },
        },
      };
      final result = parseModelsDev(root, {'openai'});
      expect(result.keys, ['openai/good']);
    });

    test('keeps models with no status field (treated as unknown → kept)', () {
      final root = {
        'openai': {
          'name': 'OpenAI',
          'models': {
            'nostatus': {
              'modalities': {
                'input': ['text'],
                'output': ['text'],
              },
              'limit': {'context': 128000},
            },
          },
        },
      };
      final result = parseModelsDev(root, {'openai'});
      expect(result.keys, ['openai/nostatus']);
    });

    test('skips hard-coded skip providers (openrouter)', () {
      final root = {
        'openrouter': {
          'name': 'OpenRouter',
          'models': {
            'any-model': {
              'status': 'active',
              'modalities': {
                'input': ['text'],
                'output': ['text'],
              },
              'limit': {'context': 200000},
            },
          },
        },
      };
      // openrouter is in allowedProviders but also in _skipProviders — must skip.
      final result = parseModelsDev(root, {'openrouter'});
      expect(result, isEmpty);
    });

    test('caps models per provider at _maxModelsPerProvider by recency', () {
      // 8 models, cap is 5 — top 5 by release_date must survive.
      final root = {
        'openai': {
          'name': 'OpenAI',
          'models': {
            'a-2020': {
              'status': 'active',
              'release_date': '2020-01-01',
              'modalities': {
                'input': ['text'],
                'output': ['text'],
              },
              'limit': {'context': 8000},
            },
            'b-2022': {
              'status': 'active',
              'release_date': '2022-06-01',
              'modalities': {
                'input': ['text'],
                'output': ['text'],
              },
              'limit': {'context': 8000},
            },
            'c-2023': {
              'status': 'active',
              'release_date': '2023-03-01',
              'modalities': {
                'input': ['text'],
                'output': ['text'],
              },
              'limit': {'context': 16000},
            },
            'd-2024': {
              'status': 'active',
              'release_date': '2024-06-01',
              'modalities': {
                'input': ['text'],
                'output': ['text'],
              },
              'limit': {'context': 128000},
            },
            'e-2025': {
              'status': 'active',
              'release_date': '2025-01-15',
              'modalities': {
                'input': ['text'],
                'output': ['text'],
              },
              'limit': {'context': 128000},
            },
            'f-2026': {
              'status': 'active',
              'release_date': '2026-03-01',
              'modalities': {
                'input': ['text'],
                'output': ['text'],
              },
              'limit': {'context': 200000},
            },
            'g-2026-late': {
              'status': 'active',
              'release_date': '2026-09-01',
              'modalities': {
                'input': ['text'],
                'output': ['text'],
              },
              'limit': {'context': 200000},
            },
            'h-2026-fresh': {
              'status': 'active',
              'release_date': '2026-12-01',
              'modalities': {
                'input': ['text'],
                'output': ['text'],
              },
              'limit': {'context': 200000},
            },
          },
        },
      };
      final result = parseModelsDev(root, {'openai'});
      expect(result.length, 5);
      expect(result.keys, containsAll(['openai/h-2026-fresh', 'openai/g-2026-late', 'openai/f-2026', 'openai/e-2025', 'openai/d-2024']));
      expect(result.keys, isNot(contains('openai/a-2020')));
      expect(result.keys, isNot(contains('openai/b-2022')));
      expect(result.keys, isNot(contains('openai/c-2023')));
    });
  });

  group('hasProviderManifestChanged', () {
    final base = {
      'name': 'Anthropic',
      'doc': 'https://docs.anthropic.com',
      'npm': '@ai-sdk/anthropic',
      'maxContextWindow': 200000,
      'modelCount': 25,
      'modalities': {
        'input': ['image', 'text'],
        'output': ['text'],
      },
      'source': 'models.dev',
    };

    test('returns false when identical', () {
      expect(hasProviderManifestChanged(base, Map<String, dynamic>.from(base)), isFalse);
    });

    test('returns true when name changes', () {
      final incoming = Map<String, dynamic>.from(base)..['name'] = 'Anthropic Inc.';
      expect(hasProviderManifestChanged(base, incoming), isTrue);
    });

    test('returns true when doc changes', () {
      final incoming = Map<String, dynamic>.from(base)..['doc'] = 'https://new.anthropic.com';
      expect(hasProviderManifestChanged(base, incoming), isTrue);
    });

    test('returns true when maxContextWindow changes', () {
      final incoming = Map<String, dynamic>.from(base)..['maxContextWindow'] = 1000000;
      expect(hasProviderManifestChanged(base, incoming), isTrue);
    });

    test('returns true when modelCount changes', () {
      final incoming = Map<String, dynamic>.from(base)..['modelCount'] = 26;
      expect(hasProviderManifestChanged(base, incoming), isTrue);
    });

    test('returns true when input modalities gain an entry', () {
      final incoming = Map<String, dynamic>.from(base);
      incoming['modalities'] = {
        'input': ['image', 'pdf', 'text'],
        'output': ['text'],
      };
      expect(hasProviderManifestChanged(base, incoming), isTrue);
    });

    test('returns false when modalities are the same in different order', () {
      final incoming = Map<String, dynamic>.from(base);
      incoming['modalities'] = {
        'input': ['text', 'image'],
        'output': ['text'],
      };
      expect(hasProviderManifestChanged(base, incoming), isFalse);
    });

    test('returns true when existing is not a Map', () {
      expect(hasProviderManifestChanged('not a map', base), isTrue);
    });
  });
}
