import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math';
import 'dart:typed_data';
import 'package:logging/logging.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

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
            Uri.parse('$serverUrl/tts'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'text': text, 'voice': voice}),
          )
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
  }

  @override
  void dispose() {
    _cancelled = true;
    _sub?.cancel();
    _queue.close();
    _client.close();
  }
}
