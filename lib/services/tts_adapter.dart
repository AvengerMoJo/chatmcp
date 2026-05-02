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
  final bool useStreaming;
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
    this.useStreaming = false,
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

    final spokenText = _sanitizeSpokenInput(text);
    Logger.root.info('MiMo TTS speak: "${spokenText.length > 80 ? '${spokenText.substring(0, 80)}...' : spokenText}"');
    _isSpeaking = true;
    try {
      Uint8List? audioBytes;
      if (useStreaming) {
        audioBytes = await _requestStreamingAudioWavBytes(spokenText);
        if (audioBytes == null || audioBytes.isEmpty) {
          _log.warning('MiMo TTS streaming returned no audio, falling back to non-streaming');
        }
      }
      audioBytes ??= await _requestNonStreamingAudioWavBytes(spokenText);

      if (audioBytes != null && audioBytes.isNotEmpty) {
        await _playAudio(audioBytes);
      } else {
        _log.warning('MiMo TTS: no playable audio bytes');
      }
    } catch (e) {
      _log.warning('MiMo TTS request failed: $e');
    } finally {
      if (!_cancelled) {
        // Player onPlayerComplete will set _isSpeaking = false
      }
    }
  }

  Future<Uint8List?> _requestNonStreamingAudioWavBytes(String spokenText) async {
    final messages = <Map<String, String>>[];
    if (stylePrompt.isNotEmpty) {
      messages.add({'role': 'system', 'content': stylePrompt});
    }
    messages.add({'role': 'user', 'content': spokenText});

    final body = jsonEncode({
      'model': model,
      'messages': messages,
      'audio': {'format': 'wav', 'voice': voice},
    });

    Logger.root.info('MiMo TTS request body: ${body.length > 200 ? '${body.substring(0, 200)}...' : body}');
    final response = await _client
        .post(Uri.parse('$baseUrl/chat/completions'), headers: {'Content-Type': 'application/json', 'api-key': apiKey}, body: body)
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      _log.warning('MiMo TTS returned ${response.statusCode}: ${response.body}');
      return null;
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = data['choices'] as List?;
    if (choices == null || choices.isEmpty) return null;
    final message = choices[0]['message'] as Map<String, dynamic>?;
    final audio = message?['audio'] as Map<String, dynamic>?;
    final audioData = audio?['data'] as String?;
    if (audioData == null || audioData.isEmpty) {
      _log.warning('MiMo TTS: no audio.data in non-streaming response');
      return null;
    }
    return base64Decode(audioData);
  }

  Future<Uint8List?> _requestStreamingAudioWavBytes(String spokenText) async {
    final messages = <Map<String, String>>[];
    if (stylePrompt.isNotEmpty) {
      messages.add({'role': 'system', 'content': stylePrompt});
    }
    messages.add({'role': 'user', 'content': spokenText});

    final body = jsonEncode({
      'model': model,
      'messages': messages,
      'audio': {'format': 'pcm16', 'voice': voice},
      'stream': true,
    });

    final req = http.Request('POST', Uri.parse('$baseUrl/chat/completions'))
      ..headers['Content-Type'] = 'application/json'
      ..headers['api-key'] = apiKey
      ..body = body;

    final resp = await _client.send(req).timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) {
      final err = await resp.stream.bytesToString();
      _log.warning('MiMo TTS stream returned ${resp.statusCode}: $err');
      return null;
    }

    final pcmBuilder = BytesBuilder(copy: false);
    await for (final line in resp.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (!trimmed.startsWith('data:')) continue;
      final payload = trimmed.substring(5).trim();
      if (payload == '[DONE]') break;
      try {
        final data = jsonDecode(payload) as Map<String, dynamic>;
        final choices = data['choices'] as List?;
        if (choices == null || choices.isEmpty) continue;
        final delta = choices[0]['delta'] as Map<String, dynamic>?;
        final audio = delta?['audio'] as Map<String, dynamic>?;
        final audioData = audio?['data'] as String?;
        if (audioData != null && audioData.isNotEmpty) {
          pcmBuilder.add(base64Decode(audioData));
        }
      } catch (_) {
        // Ignore malformed chunk and keep processing.
      }
    }

    final pcmBytes = pcmBuilder.takeBytes();
    if (pcmBytes.isEmpty) return null;
    return _pcm16ToWav(pcmBytes, sampleRate: 24000, channels: 1);
  }

  Future<void> _playAudio(Uint8List audioBytes) async {
    final tempDir = await getTemporaryDirectory();
    final path = '${tempDir.path}/mimo_tts_${DateTime.now().millisecondsSinceEpoch}.wav';
    final file = io.File(path);
    await file.writeAsBytes(audioBytes);
    Logger.root.info('MiMo TTS playing: $path (${audioBytes.length} bytes, header: ${audioBytes.take(4).toList()})');
    await _player.play(DeviceFileSource(path));
  }

  String _sanitizeSpokenInput(String text) {
    var out = text.trim();
    out = out.replaceAll(RegExp(r'^\s*input\s*text[:\-\s]*', caseSensitive: false), '');
    out = out.replaceAll(RegExp(r'^\s*prompt[:\-\s]*', caseSensitive: false), '');
    out = out.replaceAll(RegExp(r'\s+'), ' ');
    return out.trim();
  }

  Uint8List _pcm16ToWav(Uint8List pcm, {required int sampleRate, required int channels}) {
    const bitsPerSample = 16;
    final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
    final blockAlign = channels * (bitsPerSample ~/ 8);
    final dataSize = pcm.lengthInBytes;
    final totalSize = 44 + dataSize;

    final bytes = BytesBuilder(copy: false);
    void writeString(String s) => bytes.add(ascii.encode(s));
    void writeU32(int v) => bytes.add([v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff]);
    void writeU16(int v) => bytes.add([v & 0xff, (v >> 8) & 0xff]);

    writeString('RIFF');
    writeU32(totalSize - 8);
    writeString('WAVE');
    writeString('fmt ');
    writeU32(16);
    writeU16(1);
    writeU16(channels);
    writeU32(sampleRate);
    writeU32(byteRate);
    writeU16(blockAlign);
    writeU16(bitsPerSample);
    writeString('data');
    writeU32(dataSize);
    bytes.add(pcm);
    return bytes.takeBytes();
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
    bool useStreaming = false,
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
          useStreaming: useStreaming,
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
