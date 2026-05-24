import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';
import 'package:logging/logging.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';

enum MojoVoiceState { idle, recording, processing, playing, error }

enum PushType { progress, result, question }

enum ContextType { clarification, refinement }

enum MojoSseEventType { meta, text, audioChunk, done, error }

class MojoSseEvent {
  final MojoSseEventType type;
  final String? data;
  MojoSseEvent({required this.type, this.data});
  @override
  String toString() => 'MojoSseEvent($type, $data)';
}

class SessionResponse {
  final String sessionId;
  SessionResponse({required this.sessionId});
  factory SessionResponse.fromJson(Map<String, dynamic> json) => SessionResponse(sessionId: json['session_id'] as String);
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
    replyText: (json['reply_text'] ?? json['text'] ?? '') as String,
    replyAudioBase64: (json['reply_audio_base64'] ?? json['audio_base64'] ?? '') as String,
    replyAudioFormat: (json['reply_audio_format'] ?? 'wav') as String,
    sessionId: (json['session_id'] ?? '') as String,
  );
}

class PendingResponse {
  final bool pending;
  final PushType? type;
  final String? replyText;
  final String? replyAudioBase64;
  final String? replyAudioFormat;
  PendingResponse({required this.pending, this.type, this.replyText, this.replyAudioBase64, this.replyAudioFormat});
  factory PendingResponse.fromJson(Map<String, dynamic> json) => PendingResponse(
    pending: json['pending'] as bool,
    type: json['type'] != null ? PushType.values.firstWhere((e) => e.name == (json['type'] as String), orElse: () => PushType.result) : null,
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
  ContextResponse({required this.update, this.type, this.content, this.contextVersion});
  factory ContextResponse.fromJson(Map<String, dynamic> json) => ContextResponse(
    update: json['update'] as bool,
    type: json['type'] != null
        ? ContextType.values.firstWhere((e) => e.name == (json['type'] as String), orElse: () => ContextType.clarification)
        : null,
    content: json['content'] as String?,
    contextVersion: json['context_version'] as int?,
  );
}

class MojoVoiceService {
  final String baseUrl;
  final http.Client _client = http.Client();
  final Logger _log = Logger.root;

  String? _sessionId;
  String _apiPrefix = '/voice';
  final bool _isStatelessS2s;
  late final Uri _baseUri;
  Future<SessionResponse>? _sessionCreateFuture;
  Timer? _pollTimer;
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  String? _recordingPath;
  Future<void>? _startRecordingFuture;

  bool? _supportsStreamS2s;
  bool _streamCapabilityChecked = false;

  MojoVoiceState _state = MojoVoiceState.idle;
  MojoVoiceState get state => _state;

  final _stateController = StreamController<MojoVoiceState>.broadcast();
  Stream<MojoVoiceState> get stateStream => _stateController.stream;

  final _pendingAudioController = StreamController<Uint8List>.broadcast();
  Stream<Uint8List> get pendingAudioStream => _pendingAudioController.stream;

  final _contextController = StreamController<ContextResponse>.broadcast();
  Stream<ContextResponse> get contextStream => _contextController.stream;

  MojoVoiceService({required this.baseUrl})
      : _baseUri = Uri.parse(baseUrl),
        _isStatelessS2s = Uri.parse(baseUrl).path.toLowerCase().endsWith('/voice/s2s');

  bool get hasActiveSession => _isStatelessS2s || _sessionId != null;

  Future<void> checkStreamCapability() async {
    if (_streamCapabilityChecked || !_isStatelessS2s) return;
    _streamCapabilityChecked = true;

    try {
      final healthUri = _uriForPath('/health');
      final response = await _client.get(healthUri).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _supportsStreamS2s = data['supports_stream_s2s'] == true;
        _log.info('MoJo stream capability: $_supportsStreamS2s');
      }
    } catch (e) {
      _log.warning('MoJo health check failed: $e, assuming no stream support');
      _supportsStreamS2s = false;
    }
  }

  bool shouldUseStreaming({required bool streamEnabled}) {
    return streamEnabled && (_supportsStreamS2s ?? false);
  }

  String getStreamEndpoint() {
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return '$base/stream';
  }

  String getNonStreamEndpoint() {
    if (_isStatelessS2s) {
      return _baseUri.toString();
    }
    return _uriForPath('$_apiPrefix/query/$_sessionId').toString();
  }

  Future<void> ensureSession() async {
    if (_isStatelessS2s) return;
    if (_sessionId == null) {
      await createSession();
    }
  }

  Future<SessionResponse> createSession() async {
    if (_isStatelessS2s) {
      _sessionId ??= 'stateless-s2s';
      return SessionResponse(sessionId: _sessionId!);
    }
    if (_sessionId != null) {
      return SessionResponse(sessionId: _sessionId!);
    }
    if (_sessionCreateFuture != null) {
      return _sessionCreateFuture!;
    }

    final f = _createSessionInternal();
    _sessionCreateFuture = f;
    try {
      return await f;
    } finally {
      if (identical(_sessionCreateFuture, f)) {
        _sessionCreateFuture = null;
      }
    }
  }

  Future<SessionResponse> _createSessionInternal() async {
    final prefixesToTry = <String>[_apiPrefix, _apiPrefix == '/voice' ? '' : '/voice'];
    Object? lastError;
    for (final prefix in prefixesToTry) {
      final p = prefix.trim();
      final uri = _uriForPath('$p/session');
      try {
        final response = await _client.post(uri).timeout(const Duration(seconds: 10));
        if (response.statusCode == 200 || response.statusCode == 201) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          _sessionId = data['session_id'] as String;
          _apiPrefix = p;
          _log.info('MoJo session created: $_sessionId (prefix=${_apiPrefix.isEmpty ? "/" : _apiPrefix})');
          return SessionResponse.fromJson(data);
        }
        lastError = Exception('Failed to create session (${uri.path}): ${response.statusCode}');
        if (response.statusCode != 404) {
          throw lastError;
        }
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? Exception('Failed to create session');
  }

  Future<void> closeSession() async {
    if (_isStatelessS2s) {
      _sessionId = null;
      _setState(MojoVoiceState.idle);
      return;
    }
    if (_sessionId == null) return;
    stopPolling();
    await _player.stop();
    await _recorder.stop();

    try {
      await _client.delete(_uriForPath('$_apiPrefix/session/$_sessionId')).timeout(const Duration(seconds: 5));
    } catch (e) {
      _log.warning('Error closing session: $e');
    }
    _sessionId = null;
    _setState(MojoVoiceState.idle);
    _log.info('MoJo session closed');
  }

  Future<QueryResponse> queryAudio(Uint8List wavBytes, {String? mcpMode, String? roleId}) async {
    if (!_isStatelessS2s && _sessionId == null) {
      throw Exception('No active session. Call createSession() first.');
    }

    _setState(MojoVoiceState.processing);

    final audioBase64 = base64Encode(wavBytes);
    final body = {'audio_base64': audioBase64};
    if (mcpMode != null) body['mcp_mode'] = mcpMode;
    if (roleId != null) body['role_id'] = roleId;

    try {
      final uri = _isStatelessS2s ? _baseUri : _uriForPath('$_apiPrefix/query/$_sessionId');
      final response = await _client
          .post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _log.info('MoJo query successful, transcript: ${data['transcript']}');
        if (_isStatelessS2s) {
          return QueryResponse(
            transcript: data['transcript'] as String? ?? '',
            replyText: data['text'] as String? ?? '',
            replyAudioBase64: data['audio_base64'] as String? ?? '',
            replyAudioFormat: 'wav',
            sessionId: _sessionId ?? 'stateless-s2s',
          );
        }
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

  Stream<MojoSseEvent> queryAudioStream(
    Uint8List wavBytes, {
    int maxTokens = 96,
    double temperature = 0.2,
  }) async* {
    if (!_isStatelessS2s && _sessionId == null) {
      yield MojoSseEvent(type: MojoSseEventType.error, data: 'No active session');
      return;
    }

    _setState(MojoVoiceState.processing);
    _audioChunkQueue.clear();
    _isStreamingAudio = true;

    final audioBase64 = base64Encode(wavBytes);
    final body = {
      'audio_base64': audioBase64,
      'max_tokens': maxTokens,
      'temperature': temperature,
    };

    final endpoint = getStreamEndpoint();
    final uri = Uri.parse(endpoint);
    final request = http.Request('POST', uri);
    request.headers['Content-Type'] = 'application/json';
    request.body = jsonEncode(body);
    _log.info('MoJo stream start: $endpoint, maxTokens=$maxTokens, temperature=$temperature');

    http.StreamedResponse response;
    try {
      response = await _client.send(request).timeout(const Duration(seconds: 150));
    } catch (e) {
      _setState(MojoVoiceState.error);
      _isStreamingAudio = false;
      yield MojoSseEvent(type: MojoSseEventType.error, data: e.toString());
      return;
    }

    if (response.statusCode != 200) {
      _setState(MojoVoiceState.error);
      _isStreamingAudio = false;
      yield MojoSseEvent(type: MojoSseEventType.error, data: 'HTTP ${response.statusCode}');
      return;
    }

    String eventName = '';
    StringBuffer dataBuffer = StringBuffer();

    await for (final chunk in response.stream.transform(utf8.decoder)) {
      for (final line in chunk.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) {
          if (dataBuffer.isNotEmpty) {
            final dataStr = dataBuffer.toString().trim();
            if (dataStr.isNotEmpty) {
              try {
                final json = jsonDecode(dataStr) as Map<String, dynamic>;
                final typeStr = eventName.isNotEmpty ? eventName : (json['type'] as String? ?? '');
                final eventData = json['data'] as String? ?? jsonEncode(json);
                switch (typeStr) {
                  case 'meta':
                    yield MojoSseEvent(type: MojoSseEventType.meta, data: eventData);
                    break;
                  case 'text':
                    yield MojoSseEvent(type: MojoSseEventType.text, data: eventData);
                    break;
                  case 'audio_chunk':
                    yield MojoSseEvent(type: MojoSseEventType.audioChunk, data: eventData);
                    break;
                  case 'done':
                    yield MojoSseEvent(type: MojoSseEventType.done, data: eventData);
                    break;
                  case 'error':
                    yield MojoSseEvent(type: MojoSseEventType.error, data: eventData);
                    break;
                  default:
                    if (json.containsKey('audio_base64') && json['audio_base64'] is String) {
                      yield MojoSseEvent(type: MojoSseEventType.audioChunk, data: json['audio_base64'] as String);
                    } else if (json.containsKey('text') || json.containsKey('transcript')) {
                      yield MojoSseEvent(type: MojoSseEventType.text, data: jsonEncode(json));
                    }
                }
              } catch (_) {}
            }
            dataBuffer.clear();
          }
          eventName = '';
          continue;
        }

        if (trimmed.startsWith('event:')) {
          eventName = trimmed.substring(6).trim();
        } else if (trimmed.startsWith('data:')) {
          final dataValue = trimmed.substring(5).trim();
          if (dataBuffer.isNotEmpty) dataBuffer.write('\n');
          dataBuffer.write(dataValue);
        }
      }
    }

    _isStreamingAudio = false;
    _setState(MojoVoiceState.idle);
  }

  final _audioChunkController = StreamController<Uint8List>.broadcast();
  Stream<Uint8List> get audioChunkStream => _audioChunkController.stream;

  final List<Uint8List> _audioChunkQueue = [];
  bool _isStreamingAudio = false;

  void queueAudioChunk(Uint8List chunk) {
    _audioChunkQueue.add(chunk);
    _audioChunkController.add(chunk);
  }

  Future<void> playAudioChunk(Uint8List chunk) async {
    final tempDir = await getTemporaryDirectory();
    final path = '${tempDir.path}/mojo_chunk_${DateTime.now().millisecondsSinceEpoch}.wav';
    final file = io.File(path);
    await file.writeAsBytes(chunk);
    await _player.play(DeviceFileSource(path));
    await file.delete();
  }

  Future<void> flushAudioQueue() async {
    for (final chunk in _audioChunkQueue) {
      await playAudioChunk(chunk);
    }
    _audioChunkQueue.clear();
  }

  void clearAudioQueue() {
    _audioChunkQueue.clear();
  }

  bool get isStreamingAudio => _isStreamingAudio;

  Future<void> pushResult(String summary, {PushType type = PushType.result}) async {
    if (_isStatelessS2s) return;
    if (_sessionId == null) return;

    try {
      await _client
          .post(
            _uriForPath('$_apiPrefix/push/$_sessionId'),
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
    if (_isStatelessS2s) return PendingResponse(pending: false);
    if (_sessionId == null) {
      throw Exception('No active session');
    }

    final response = await _client.get(_uriForPath('$_apiPrefix/pending/$_sessionId')).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      return PendingResponse.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Poll pending failed: ${response.statusCode}');
    }
  }

  Future<ContextResponse> pollContext() async {
    if (_isStatelessS2s) return ContextResponse(update: false);
    if (_sessionId == null) {
      throw Exception('No active session');
    }

    final response = await _client.get(_uriForPath('$_apiPrefix/context/$_sessionId')).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      return ContextResponse.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Poll context failed: ${response.statusCode}');
    }
  }

  Future<Uint8List> startRecording() async {
    if (_startRecordingFuture != null) {
      _log.warning('startRecording ignored: recorder is already starting');
      return Uint8List(0);
    }
    if (_state == MojoVoiceState.recording) {
      _log.warning('startRecording ignored: recorder is already recording');
      return Uint8List(0);
    }

    final startFuture = _doStartRecording();
    _startRecordingFuture = startFuture;
    try {
      await startFuture;
    } finally {
      if (identical(_startRecordingFuture, startFuture)) {
        _startRecordingFuture = null;
      }
    }
    return Uint8List(0);
  }

  Future<void> _doStartRecording() async {
    _log.info('Checking microphone permission...');
    if (!await _recorder.hasPermission()) {
      _log.warning('Microphone permission denied');
      throw Exception('Microphone permission denied. Please enable in System Preferences.');
    }

    final tempDir = await getTemporaryDirectory();
    _recordingPath = '${tempDir.path}/mojo_rec_${DateTime.now().millisecondsSinceEpoch}.wav';

    try {
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1), path: _recordingPath!);
      _setState(MojoVoiceState.recording);
      _log.info('Recording started to: $_recordingPath');
      // Wait a tiny bit for macOS to actually start
      await Future.delayed(const Duration(milliseconds: 100));
    } catch (e) {
      _log.severe('Failed to start recording: $e');
      _recordingPath = null;
      _setState(MojoVoiceState.error);
      rethrow;
    }
  }

  Future<Uint8List> stopRecording() async {
    _log.info('Stopping recording...');
    final startFuture = _startRecordingFuture;
    if (startFuture != null) {
      try {
        await startFuture.timeout(const Duration(seconds: 2));
      } catch (e) {
        _log.warning('stopRecording while recorder startup not ready: $e');
      }
    }

    if (_state != MojoVoiceState.recording) {
      _log.warning('stopRecording ignored: recorder state is $_state');
      _setState(MojoVoiceState.idle);
      _recordingPath = null;
      return Uint8List(0);
    }

    String? path;
    try {
      path = await _recorder.stop();
    } catch (e) {
      _log.severe('Recorder stop failed: $e');
      _setState(MojoVoiceState.error);
      _recordingPath = null;
      return Uint8List(0);
    }

    _setState(MojoVoiceState.processing);

    final filePath = path ?? _recordingPath;
    _recordingPath = null;

    if (filePath != null) {
      _log.info('Reading audio from: $filePath');
      try {
        final file = io.File(filePath);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          await file.delete();
          _log.info('Read ${bytes.length} bytes from recording');
          if (bytes.isEmpty) {
            _setState(MojoVoiceState.idle);
          }
          return bytes;
        } else {
          _log.warning('Recording file does not exist: $filePath');
        }
      } catch (e) {
        _log.severe('Error reading recording: $e');
      }
    } else {
      _log.warning('No recording path available');
    }
    _setState(MojoVoiceState.idle);
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
      if (e.toString().contains('404') || e.toString().contains('session')) {
        _log.warning('Stale session detected, resetting');
        stopPolling();
        _sessionId = null;
        return;
      }
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
    _log.info('_setState called: $_state -> $newState');
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

  Uri _uriForPath(String rawPath) {
    final b = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final p = rawPath.startsWith('/') ? rawPath : '/$rawPath';
    return Uri.parse('$b$p');
  }
}
