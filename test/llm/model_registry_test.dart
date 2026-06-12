import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chatmcp/llm/model.dart';
import 'package:chatmcp/llm/model_registry.dart';
import 'package:flutter_test/flutter_test.dart';

const String _bundledFixture = '''
{
  "format_version": 1,
  "models": {
    "anthropic/claude-3-5-sonnet-latest": {
      "family": "claude",
      "status": "active",
      "limit": { "context": 200000, "output": 8192 },
      "modalities": { "input": ["text", "image"], "output": ["text"] },
      "capabilities": { "tool_call": true, "reasoning": false, "attachment": true }
    }
  }
}
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ModelCapabilities.fromJson', () {
    test('parses models.dev shape with nested limit and modalities', () {
      final json = {
        'family': 'gpt-4o',
        'status': 'active',
        'limit': {'context': 128000, 'output': 16384},
        'modalities': {
          'input': ['text', 'image'],
          'output': ['text'],
        },
        'capabilities': {
          'tool_call': true,
          'reasoning': false,
          'attachment': true,
        },
      };
      final caps = ModelCapabilities.fromJson(json);
      expect(caps.contextWindow, 128000);
      expect(caps.maxOutputTokens, 16384);
      expect(caps.supportsImages, isTrue);
      expect(caps.supportsThinking, isFalse);
      expect(caps.inputModalities, containsAll(['text', 'image']));
      expect(caps.outputModalities, ['text']);
      expect(caps.family, 'gpt-4o');
      expect(caps.status, 'active');
    });

    test('infers supportsImages from modalities when capabilities.attachment missing', () {
      final caps = ModelCapabilities.fromJson({
        'modalities': {
          'input': ['text', 'image'],
          'output': ['text'],
        },
      });
      expect(caps.supportsImages, isTrue);
    });

    test('handles missing fields with safe defaults', () {
      final caps = ModelCapabilities.fromJson({});
      expect(caps.contextWindow, isNull);
      expect(caps.maxOutputTokens, isNull);
      expect(caps.supportsImages, isFalse);
      expect(caps.supportsThinking, isFalse);
      expect(caps.inputModalities, ['text']);
      expect(caps.outputModalities, ['text']);
      expect(caps.source, 'unknown');
    });
  });

  group('Model JSON round-trip', () {
    test('Model preserves capabilities', () {
      final m = Model(
        name: 'gpt-4o',
        label: 'GPT-4o',
        providerId: 'openai',
        icon: 'icon.png',
        providerName: 'OpenAI',
        apiStyle: 'openai',
        capabilities: const ModelCapabilities(
          contextWindow: 128000,
          maxOutputTokens: 16384,
          supportsImages: true,
        ),
      );
      final json = m.toJson();
      final back = Model.fromJson(json);
      expect(back.name, 'gpt-4o');
      expect(back.capabilities?.contextWindow, 128000);
      expect(back.capabilities?.supportsImages, isTrue);
    });

    test('Model.fromJson without capabilities is null', () {
      final m = Model.fromJson({
        'name': 'gpt-4o',
        'label': 'GPT-4o',
        'provider': 'openai',
        'icon': '',
        'providerName': 'OpenAI',
        'apiStyle': 'openai',
      });
      expect(m.capabilities, isNull);
    });

    test('copyWithCapabilities only touches the field', () {
      final m = Model(
        name: 'gpt-4o',
        label: 'GPT-4o',
        providerId: 'openai',
        icon: '',
        providerName: 'OpenAI',
        apiStyle: 'openai',
      );
      final caps = const ModelCapabilities(contextWindow: 128000, supportsImages: true);
      final m2 = m.copyWithCapabilities(caps);
      expect(identical(m, m2), isFalse);
      expect(m2.name, m.name);
      expect(m2.capabilities?.contextWindow, 128000);
    });
  });

  group('ModelRegistry.bundled resolution', () {
    setUp(() async {
      // Point the disk cache at a fresh temp dir so we don't trip path_provider.
      final tmp = await Directory.systemTemp.createTemp('chatmcp_test_');
      ModelRegistry.instance.cacheDirectoryOverride = tmp;
      ModelRegistry.instance.loadBundled(assetLoader: (_) async => _bundledFixture);
    });

    test('returns bundled capabilities for provider/model key', () async {
      await ModelRegistry.instance.loadBundled(assetLoader: (_) async => _bundledFixture);
      final caps = await ModelRegistry.instance.enrich('claude-3-5-sonnet-latest', providerId: 'anthropic');
      expect(caps, isNotNull);
      expect(caps!.contextWindow, 200000);
      expect(caps.supportsImages, isTrue);
      expect(caps.source, 'bundled');
    });

    test('returns null for unknown model when no network', () async {
      await ModelRegistry.instance.loadBundled(assetLoader: (_) async => _bundledFixture);
      final caps = await ModelRegistry.instance.enrich('nonexistent-model-xyz', providerId: 'openai');
      expect(caps, isNull);
    });
  });
}
