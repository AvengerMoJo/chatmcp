import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';
import 'package:logging/logging.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';

enum MojoVoiceState {
  idle,
  recording,
  processing,
  playing,
  error,
}

enum PushType {
  progress,
  result,
  question,
}

enum ContextType {
  clarification,
  refinement,
}

class SessionResponse {
  final String sessionId;
  SessionResponse({required this.sessionId});
  factory SessionResponse.fromJson(Map<String, dynamic> json) =>
      SessionResponse(sessionId: json['session_id'] as String);
}

class QueryResponse {
  final String transcript;
  final String replyText;
  final String replyAudioBase64;
  final String replyAudioFormat;
  final String sessionId;
  QueryResponse({
    required this.transcript,
    required this.replyText,
    required this.replyAudioBase64,
    required this.replyAudioFormat,
    required this.sessionId,
  });
  factory QueryResponse.fromJson(Map<String, dynamic> json) => QueryResponse(
        transcript: json['transcript'] as String,
        replyText: json['reply_text'] as String,
        replyAudioBase64: json['reply_audio_base64'] as String,
        replyAudioFormat: json['reply_audio_format'] as String,
        sessionId: json['session_id'] as String,
      );
}

class PendingResponse {
  final bool pending;
  final PushType? type;
  final String? replyText;
  final String? replyAudioBase64;
  final String? replyAudioFormat;
  PendingResponse({
    required this.pending,
    this.type,
    this.replyText,
    this.replyAudioBase64,
    this.replyAudioFormat,
  });
  factory PendingResponse.fromJson(Map<String, dynamic> json) => PendingResponse(
        pending: json['pending'] as bool,
        type: json['type'] != null ? PushType.values.firstWhere(
            (e) => e.name == (json['type'] as String),
            orElse: () => PushType.result) : null,
        replyText: json['reply_text'] as String?,
        replyAudioBase64: json['reply_audio_base64'] as String?,
        replyAudioFormat: json['reply_audio_format'] as String?,
      );
}

class ContextResponse {
  final bool update;
  final ContextType? type;
  final String? content;
  final int? contextVersion;
  ContextResponse({
    required this.update,
    this.type,
    this.content,
    this.contextVersion,
  });
  factory ContextResponse.fromJson(Map<String, dynamic> json) => ContextResponse(
        update: json['update'] as bool,
        type: json['type'] != null ? ContextType.values.firstWhere(
            (e) => e.name == (json['type'] as String),
            orElse: () => ContextType.clarification) : null,
        content: json['content'] as String?,
        contextVersion: json['context_version'] as int?,
      );
}

class MojoVoiceService {
  final String baseUrl;
  final http.Client _client = http.Client();
  final Logger _log = Logger.root;

  String? _sessionId;
  Timer? _pollTimer;
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  MojoVoiceState _state = MojoVoiceState.idle;
  MojoVoiceState get state => _state;

  final _stateController = StreamController<MojoVoiceState>.broadcast();
  Stream<MojoVoiceState> get stateStream => _stateController.stream;

  final _pendingAudioController = StreamController<Uint8List>.broadcast();
  Stream<Uint8List> get pendingAudioStream => _pendingAudioController.stream;

  final _contextController = StreamController<ContextResponse>.broadcast();
  Stream<ContextResponse> get contextStream => _contextController.stream;

  MojoVoiceService({required this.baseUrl});

  Future<SessionResponse> createSession() async {
    final response = await _client
        .post(Uri.parse('$baseUrl/voice/session'))
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      _sessionId = data['session_id'] as String;
      _log.info('MoJo session created: $_sessionId');
      return SessionResponse.fromJson(data);
    } else {
      throw Exception('Failed to create session: ${response.statusCode}');
    }
  }

  Future<void> closeSession() async {
    if (_sessionId == null) return;
    stopPolling();
    await _player.stop();
    await _recorder.stop();

    try {
      await _client
          .delete(Uri.parse('$baseUrl/voice/session/$_sessionId'))
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      _log.warning('Error closing session: $e');
    }
    _sessionId = null;
    _setState(MojoVoiceState.idle);
    _log.info('MoJo session closed');
  }

  Future<QueryResponse> queryAudio(Uint8List wavBytes, {String? mcpMode, String? roleId}) async {
    if (_sessionId == null) {
      throw Exception('No active session. Call createSession() first.');
    }

    _setState(MojoVoiceState.processing);

    final audioBase64 = base64Encode(wavBytes);
    final body = {'audio_base64': audioBase64};
    if (mcpMode != null) body['mcp_mode'] = mcpMode;
    if (roleId != null) body['role_id'] = roleId;

    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/voice/query/$_sessionId'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _log.info('MoJo query successful, transcript: ${data['transcript']}');
        return QueryResponse.fromJson(data);
      } else {
        _setState(MojoVoiceState.error);
        throw Exception('Query failed: ${response.statusCode}');
      }
    } catch (e) {
      _setState(MojoVoiceState.error);
      rethrow;
    }
  }

  Future<void> pushResult(String summary, {PushType type = PushType.result}) async {
    if (_sessionId == null) return;

    try {
      await _client
          .post(
            Uri.parse('$baseUrl/voice/push/$_sessionId'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'type': type.name, 'summary': summary}),
          )
          .timeout(const Duration(seconds: 10));
      _log.info('Pushed to MoJo: $summary');
    } catch (e) {
      _log.warning('Push failed: $e');
    }
  }

  Future<PendingResponse> pollPending() async {
    if (_sessionId == null) {
      throw Exception('No active session');
    }

    final response = await _client
        .get(Uri.parse('$baseUrl/voice/pending/$_sessionId'))
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      return PendingResponse.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Poll pending failed: ${response.statusCode}');
    }
  }

  Future<ContextResponse> pollContext() async {
    if (_sessionId == null) {
      throw Exception('No active session');
    }

    final response = await _client
        .get(Uri.parse('$baseUrl/voice/context/$_sessionId'))
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      return ContextResponse.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Poll context failed: ${response.statusCode}');
    }
  }

  Future<Uint8List> startRecording() async {
    if (!await _recorder.hasPermission()) {
      throw Exception('Microphone permission denied');
    }

    _setState(MojoVoiceState.recording);

    final tempDir = await getTemporaryDirectory();
    final path = '${tempDir.path}/mojo_rec_${DateTime.now().millisecondsSinceEpoch}.wav';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: path,
    );

    return Uint8List(0);
  }

  Future<Uint8List> stopRecording() async {
    final path = await _recorder.stop();
    _setState(MojoVoiceState.processing);

    if (path != null) {
      final file = io.File(path);
      final bytes = await file.readAsBytes();
      await file.delete();
      return bytes;
    }
    return Uint8List(0);
  }

  bool get isRecording => _state == MojoVoiceState.recording;

  Future<void> playAudio(Uint8List audioBytes, {String format = 'wav'}) async {
    _setState(MojoVoiceState.playing);

    final tempDir = await getTemporaryDirectory();
    final path = '${tempDir.path}/mojo_reply_${DateTime.now().millisecondsSinceEpoch}.$format';
    final file = io.File(path);
    await file.writeAsBytes(audioBytes);

    await _player.play(DeviceFileSource(path));

    _player.onPlayerComplete.listen((_) {
      _setState(MojoVoiceState.idle);
    });
  }

  Future<void> playFromBase64(String base64Audio, {String format = 'wav'}) async {
    final audioBytes = base64Decode(base64Audio);
    await playAudio(audioBytes, format: format);
  }

  void startPolling({Duration interval = const Duration(seconds: 2)}) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(interval, (_) => _poll());
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _poll() async {
    try {
      final pending = await pollPending();
      if (pending.pending && pending.replyAudioBase64 != null) {
        _pendingAudioController.add(base64Decode(pending.replyAudioBase64!));
      }
    } catch (e) {
      _log.warning('Poll pending error: $e');
    }

    try {
      final context = await pollContext();
      if (context.update && context.content != null) {
        _contextController.add(context);
      }
    } catch (e) {
      _log.warning('Poll context error: $e');
    }
  }

  void _setState(MojoVoiceState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  void dispose() {
    closeSession();
    _recorder.dispose();
    _player.dispose();
    _stateController.close();
    _pendingAudioController.close();
    _contextController.close();
    _client.close();
  }
}