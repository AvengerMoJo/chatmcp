import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class Glm4VoiceResponse {
  final String transcript;
  final String replyText;
  final Uint8List? replyAudioBytes;
  final String replyAudioFormat;

  Glm4VoiceResponse({required this.transcript, required this.replyText, required this.replyAudioBytes, required this.replyAudioFormat});
}

class Glm4VoiceLocalService {
  final String serverUrl;
  final String queryPath;
  final http.Client _client = http.Client();
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  final Logger _log = Logger.root;
  String? _recordingPath;

  Glm4VoiceLocalService({required this.serverUrl, this.queryPath = '/voice/query'});

  Future<void> startRecording() async {
    if (!await _recorder.hasPermission()) {
      throw Exception('Microphone permission denied');
    }
    final tempDir = await getTemporaryDirectory();
    _recordingPath = '${tempDir.path}/glm4voice_rec_${DateTime.now().millisecondsSinceEpoch}.wav';
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1), path: _recordingPath!);
  }

  Future<Glm4VoiceResponse> stopRecordingAndQuery({String language = 'auto', String contextHint = ''}) async {
    final path = await _recorder.stop();
    final filePath = path ?? _recordingPath;
    _recordingPath = null;
    if (filePath == null) {
      throw Exception('No recording path available');
    }
    final file = io.File(filePath);
    if (!await file.exists()) {
      throw Exception('Recording file not found');
    }

    final uri = Uri.parse(_joinUrl(serverUrl, queryPath));
    final req = http.MultipartRequest('POST', uri);
    req.files.add(await http.MultipartFile.fromPath('audio', file.path, filename: 'input.wav'));
    req.fields['language'] = language;
    if (contextHint.isNotEmpty) req.fields['context_hint'] = contextHint;

    final streamed = await _client.send(req).timeout(const Duration(seconds: 120));
    final bytes = await streamed.stream.toBytes();
    await file.delete();

    final contentType = streamed.headers['content-type'] ?? '';
    if (streamed.statusCode != 200) {
      final err = utf8.decode(bytes, allowMalformed: true);
      _log.warning('GLM4Voice returned ${streamed.statusCode}: $err');
      throw Exception('GLM4Voice request failed: ${streamed.statusCode}');
    }

    if (contentType.contains('audio/')) {
      return Glm4VoiceResponse(
        transcript: '',
        replyText: '',
        replyAudioBytes: Uint8List.fromList(bytes),
        replyAudioFormat: contentType.contains('mpeg') ? 'mp3' : 'wav',
      );
    }

    final jsonBody = jsonDecode(utf8.decode(bytes, allowMalformed: true)) as Map<String, dynamic>;
    final audioBase64 = jsonBody['reply_audio_base64'] as String?;
    final audioBytes = audioBase64 != null && audioBase64.isNotEmpty ? base64Decode(audioBase64) : null;
    return Glm4VoiceResponse(
      transcript: jsonBody['transcript'] as String? ?? '',
      replyText: jsonBody['reply_text'] as String? ?? '',
      replyAudioBytes: audioBytes,
      replyAudioFormat: jsonBody['reply_audio_format'] as String? ?? 'wav',
    );
  }

  Future<void> playAudio(Uint8List audioBytes, {String format = 'wav'}) async {
    final tempDir = await getTemporaryDirectory();
    final path = '${tempDir.path}/glm4voice_reply_${DateTime.now().millisecondsSinceEpoch}.$format';
    await io.File(path).writeAsBytes(audioBytes);
    await _player.play(DeviceFileSource(path));
  }

  Future<void> stopPlayback() => _player.stop();

  void dispose() {
    _recorder.dispose();
    _player.dispose();
    _client.close();
  }

  String _joinUrl(String base, String path) {
    final normalizedBase = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return '$normalizedBase$normalizedPath';
  }
}
