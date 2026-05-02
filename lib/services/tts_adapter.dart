import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';
import 'package:logging/logging.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';

abstract class TtsAdapter {
  bool get isSpeaking;

  void speak(String text);
  void cancel();
  void dispose();
}

class NoOpTtsAdapter implements TtsAdapter {
  @override
  bool get isSpeaking => false;

  @override
  void speak(String text) {}

  @override
  void cancel() {}

  @override
  void dispose() {}
}

class CosyVoice2Adapter implements TtsAdapter {
  final String serverUrl;
  final String voice;
  final http.Client _client = http.Client();
  final AudioPlayer _player = AudioPlayer();
  final Logger _log = Logger.root;
  bool _isSpeaking = false;
  bool _cancelled = false;
  final StreamController<String> _queue = StreamController<String>.broadcast();
  StreamSubscription<String>? _sub;

  CosyVoice2Adapter({required this.serverUrl, this.voice = 'default'}) {
    _sub = _queue.stream.listen(_processQueue);
  }

  @override
  bool get isSpeaking => _isSpeaking;

  @override
  void speak(String text) {
    if (text.trim().isEmpty) return;
    _queue.add(text);
  }

  @override
  void cancel() {
    _cancelled = true;
    _isSpeaking = false;
    _player.stop();
  }

  Future<void> _processQueue(String text) async {
    if (_cancelled) {
      _cancelled = false;
      return;
    }

    _isSpeaking = true;
    try {
      final response = await _client
          .post(Uri.parse('$serverUrl/tts'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'text': text, 'voice': voice}))
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        await _playAudio(response.bodyBytes);
      } else {
        _log.warning('TTS server returned ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      _log.warning('TTS request failed: $e');
    } finally {
      _isSpeaking = false;
    }
  }

  Future<void> _playAudio(Uint8List audioBytes) async {
    final tempDir = await getTemporaryDirectory();
    final path = '${tempDir.path}/tts_${DateTime.now().millisecondsSinceEpoch}.wav';
    final file = io.File(path);
    await file.writeAsBytes(audioBytes);
    _log.info('TTS audio saved: $path (${audioBytes.length ~/ 1024}KB)');
    await _player.play(DeviceFileSource(path));
  }

  @override
  void dispose() {
    _cancelled = true;
    _sub?.cancel();
    _queue.close();
    _client.close();
    _player.dispose();
  }
}

class MiMoTtsAdapter implements TtsAdapter {
  final String apiKey;
  final String baseUrl;
  final String model;
  final String voice;
  final String stylePrompt;
  final http.Client _client = http.Client();
  final AudioPlayer _player = AudioPlayer();
  final Logger _log = Logger.root;
  bool _isSpeaking = false;
  bool _cancelled = false;
  final StreamController<String> _queue = StreamController<String>.broadcast();
  StreamSubscription<String>? _sub;

  MiMoTtsAdapter({
    required this.apiKey,
    this.baseUrl = 'https://token-plan-cn.xiaomimimo.com/v1',
    this.model = 'mimo-v2.5-tts',
    this.voice = 'mimo_default',
    this.stylePrompt = '',
  }) {
    _sub = _queue.stream.listen(_processQueue);
    _player.onPlayerComplete.listen((_) {
      _isSpeaking = false;
    });
  }

  @override
  bool get isSpeaking => _isSpeaking;

  @override
  void speak(String text) {
    if (text.trim().isEmpty) return;
    _queue.add(text);
  }

  @override
  void cancel() {
    _cancelled = true;
    _isSpeaking = false;
    _player.stop();
  }

  Future<void> _processQueue(String text) async {
    if (_cancelled) {
      _cancelled = false;
      return;
    }

    Logger.root.info('MiMo TTS speak: "${text.length > 80 ? '${text.substring(0, 80)}...' : text}"');
    _isSpeaking = true;
    try {
      final messages = <Map<String, String>>[];
      if (stylePrompt.isNotEmpty) {
        messages.add({'role': 'user', 'content': stylePrompt});
      }
      messages.add({'role': 'assistant', 'content': text});

      final body = jsonEncode({
        'model': model,
        'messages': messages,
        'audio': {'format': 'wav', 'voice': voice},
      });

      Logger.root.info('MiMo TTS request body: ${body.length > 200 ? '${body.substring(0, 200)}...' : body}');

      final response = await _client
          .post(Uri.parse('$baseUrl/chat/completions'), headers: {'Content-Type': 'application/json', 'api-key': apiKey}, body: body)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final choices = data['choices'] as List?;
        if (choices != null && choices.isNotEmpty) {
          final message = choices[0]['message'] as Map<String, dynamic>?;
          final audio = message?['audio'] as Map<String, dynamic>?;
          final audioData = audio?['data'] as String?;
          if (audioData != null) {
            final audioBytes = base64Decode(audioData);
            await _playAudio(audioBytes);
          } else {
            _log.warning('MiMo TTS: no audio data in response');
          }
        }
      } else {
        _log.warning('MiMo TTS returned ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      _log.warning('MiMo TTS request failed: $e');
    } finally {
      if (!_cancelled) {
        // Player onPlayerComplete will set _isSpeaking = false
      }
    }
  }

  Future<void> _playAudio(Uint8List audioBytes) async {
    final tempDir = await getTemporaryDirectory();
    final path = '${tempDir.path}/mimo_tts_${DateTime.now().millisecondsSinceEpoch}.wav';
    final file = io.File(path);
    await file.writeAsBytes(audioBytes);
    _log.info('MiMo TTS audio saved: $path (${audioBytes.length ~/ 1024}KB)');
    await _player.play(DeviceFileSource(path));
  }

  @override
  void dispose() {
    _cancelled = true;
    _sub?.cancel();
    _queue.close();
    _client.close();
    _player.dispose();
  }
}

class OpenAITtsAdapter implements TtsAdapter {
  final String apiKey;
  final String baseUrl;
  final String model;
  final String voice;
  final http.Client _client = http.Client();
  final AudioPlayer _player = AudioPlayer();
  final Logger _log = Logger.root;
  bool _isSpeaking = false;
  bool _cancelled = false;
  final StreamController<String> _queue = StreamController<String>.broadcast();
  StreamSubscription<String>? _sub;

  OpenAITtsAdapter({required this.apiKey, this.baseUrl = 'https://api.openai.com/v1', this.model = 'tts-1', this.voice = 'alloy'}) {
    _sub = _queue.stream.listen(_processQueue);
    _player.onPlayerComplete.listen((_) {
      _isSpeaking = false;
    });
  }

  @override
  bool get isSpeaking => _isSpeaking;

  @override
  void speak(String text) {
    if (text.trim().isEmpty) return;
    _queue.add(text);
  }

  @override
  void cancel() {
    _cancelled = true;
    _isSpeaking = false;
    _player.stop();
  }

  Future<void> _processQueue(String text) async {
    if (_cancelled) {
      _cancelled = false;
      return;
    }

    _isSpeaking = true;
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/audio/speech'),
            headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $apiKey'},
            body: jsonEncode({'model': model, 'input': text, 'voice': voice, 'response_format': 'wav'}),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        await _playAudio(response.bodyBytes);
      } else {
        _log.warning('OpenAI TTS returned ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      _log.warning('OpenAI TTS request failed: $e');
    }
  }

  Future<void> _playAudio(Uint8List audioBytes) async {
    final tempDir = await getTemporaryDirectory();
    final path = '${tempDir.path}/openai_tts_${DateTime.now().millisecondsSinceEpoch}.wav';
    final file = io.File(path);
    await file.writeAsBytes(audioBytes);
    _log.info('OpenAI TTS audio saved: $path (${audioBytes.length ~/ 1024}KB)');
    await _player.play(DeviceFileSource(path));
  }

  @override
  void dispose() {
    _cancelled = true;
    _sub?.cancel();
    _queue.close();
    _client.close();
    _player.dispose();
  }
}

class TtsAdapterFactory {
  static TtsAdapter? create({
    required String providerId,
    required String apiKey,
    required String baseUrl,
    String model = '',
    String voice = '',
    String stylePrompt = '',
  }) {
    switch (providerId) {
      case 'cosyvoice2':
        return CosyVoice2Adapter(serverUrl: baseUrl, voice: voice.isNotEmpty ? voice : 'default');
      case 'mimo':
        if (apiKey.isEmpty) return null;
        return MiMoTtsAdapter(
          apiKey: apiKey,
          baseUrl: baseUrl,
          model: model.isNotEmpty ? model : 'mimo-v2.5-tts',
          voice: voice.isNotEmpty ? voice : 'mimo_default',
          stylePrompt: stylePrompt,
        );
      case 'openai':
      case 'copilot':
      case 'groq':
        if (apiKey.isEmpty) return null;
        return OpenAITtsAdapter(
          apiKey: apiKey,
          baseUrl: baseUrl,
          model: model.isNotEmpty ? model : 'tts-1',
          voice: voice.isNotEmpty ? voice : 'alloy',
        );
      default:
        return null;
    }
  }
}
