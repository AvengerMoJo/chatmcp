import 'dart:typed_data';

import 'package:chatmcp/llm/prompt.dart';
import 'package:chatmcp/utils/platform.dart' hide File;
import 'package:flutter/material.dart';
import 'package:chatmcp/llm/model.dart';
import 'package:chatmcp/llm/llm_factory.dart';
import 'package:chatmcp/llm/base_llm_client.dart';
import 'package:chatmcp/llm/context_manager.dart';
import 'package:chatmcp/llm/summarizer.dart';
import 'package:logging/logging.dart';
import 'package:file_picker/file_picker.dart';
import 'package:chatmcp/utils/file_upload_handler.dart';
import 'package:chatmcp/provider/provider_manager.dart';
import 'package:chatmcp/provider/settings_provider.dart';
import 'input_area.dart';
import 'package:chatmcp/dao/chat.dart';
import 'package:uuid/uuid.dart';
import 'chat_message_list.dart';
import 'package:chatmcp/utils/color.dart';
import 'chat_message_to_image.dart';
import 'package:chatmcp/utils/event_bus.dart';
import 'chat_code_preview.dart';
import 'package:chatmcp/generated/app_localizations.dart';
import 'dart:convert';
import 'package:chatmcp/mcp/models/json_rpc_message.dart';
import 'dart:async';
import 'package:chatmcp/services/tts_adapter.dart';
import 'package:chatmcp/services/sentence_chunker.dart';
import 'package:chatmcp/services/mojo_voice_service.dart';
import 'package:chatmcp/services/glm4voice_local_service.dart';
import 'package:chatmcp/services/voice_classifier.dart';
import 'package:chatmcp/services/voice_response_extractor.dart';
import 'package:chatmcp/services/streaming_speech_filter.dart';
import 'package:chatmcp/services/buffered_summary_speaker.dart';
import 'package:chatmcp/components/widgets/mojo_voice_panel.dart';
import 'package:chatmcp/components/widgets/voice_console_dialog.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  Chat? _chat;
  List<ChatMessage> _messages = [];
  bool _isComposing = false; // Indicates if the user is currently composing a message
  BaseLLMClient? _llmClient;
  String _currentResponse = '';
  bool _isLoading = false; // Indicates if the chat is currently loading or processing a response
  String _parentMessageId = ''; // Parent message ID
  bool _isCancelled = false; // Indicates if the current operation has been cancelled by the user
  bool _isWaiting = false; // Indicates if the system is waiting for a response from the LLM

  // GlobalKey for InputArea to access focus methods
  final GlobalKey<InputAreaState> _inputAreaKey = GlobalKey<InputAreaState>();

  // TTS
  TtsAdapter _ttsAdapter = NoOpTtsAdapter();
  SentenceChunker _sentenceChunker = SentenceChunker();
  final VoiceResponseExtractor _voiceExtractor = VoiceResponseExtractor();
  final StreamingSpeechFilter _speechFilter = StreamingSpeechFilter();
  BufferedSummarySpeaker _bufferedSpeaker = BufferedSummarySpeaker(ttsAdapter: NoOpTtsAdapter());

  // MoJo Voice
  MojoVoiceService? _mojoVoiceService;
  Uint8List? _pendingRecordingBytes;
  bool _isMojoStartPending = false;
  bool _isMojoStopPending = false;
  String? _lastMojoPushedAssistantMessageId;
  final ValueNotifier<String> _voiceConsoleOutput = ValueNotifier<String>('');
  final ValueNotifier<String> _voiceConsoleLanguage = ValueNotifier<String>('auto');
  final ValueNotifier<bool> _shareVoiceToChat = ValueNotifier<bool>(true);
  final ValueNotifier<bool> _shareChatToVoice = ValueNotifier<bool>(false);
  bool _voiceConsoleActive = false;
  bool _suspendHistorySync = false;
  Glm4VoiceLocalService? _glm4VoiceLocalService;
  StreamSubscription<Uint8List>? _mojoPendingAudioSub;
  StreamSubscription<ContextResponse>? _mojoContextSub;
  int? _lastMojoContextVersion;

  // Stores image bytes of the widget for sharing functionality
  Uint8List? bytes;

  bool mobile = kIsMobile;

  final List<RunFunctionEvent> _runFunctionEvents = [];
  bool _isRunningFunction = false;

  num _currentLoop = 0;
  Future<void> _voiceSubmitQueue = Future.value();

  // https://stackoverflow.com/questions/51791501/how-to-debounce-textfield-onchange-in-dart
  Timer? _debounce;
  static const int _chatPageDebounceTime = 100;

  @override
  void initState() {
    super.initState();
    _initializeState();
    on<ShareEvent>(_handleShare);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isMobile() != mobile) {
        setState(() {
          mobile = _isMobile();
        });
      }
      if (!mobile && showModalCodePreview) {
        setState(() {
          Navigator.pop(context);
          showModalCodePreview = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _voiceConsoleOutput.dispose();
    _voiceConsoleLanguage.dispose();
    _shareVoiceToChat.dispose();
    _shareChatToVoice.dispose();
    _mojoPendingAudioSub?.cancel();
    _mojoContextSub?.cancel();
    _glm4VoiceLocalService?.dispose();
    _removeListeners();
    super.dispose();
  }

  // Initializes state and sets up related methods
  void _initializeState() {
    _initializeLLMClient();
    _addListeners();
    _initializeHistoryMessages();
    _initMojoVoice();
    on<RunFunctionEvent>(_onRunFunction);
  }

  Future<void> _onRunFunction(RunFunctionEvent event) async {
    if (event.name.trim().isEmpty) {
      Logger.root.warning('Ignored RunFunctionEvent with empty tool name');
      return;
    }
    setState(() {
      _runFunctionEvents.add(event);
    });

    if (!_isLoading) {
      _handleSubmitted(SubmitData("", []));
    }
  }

  Future<bool> _showFunctionApprovalDialog(RunFunctionEvent event) async {
    // Determines which MCP server's tool the function belongs to
    final clientName = _findClientName(ProviderManager.mcpServerProvider.tools, event.name);
    if (clientName == null) return false;

    final serverConfig = await ProviderManager.mcpServerProvider.loadServersAll();
    final servers = serverConfig['mcpServers'] as Map<String, dynamic>? ?? {};

    if (servers.containsKey(clientName)) {
      final config = servers[clientName] as Map<String, dynamic>? ?? {};
      final autoApprove = config['auto_approve'] as bool? ?? false;

      // Skips authorization dialog if auto-approve is enabled in server config
      if (autoApprove) {
        return true;
      }
    }

    // Verifies component is still mounted before showing dialog
    if (!mounted) return false;

    // Displays authorization dialog for function execution
    var t = AppLocalizations.of(context)!;
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
              title: Text(t.functionCallAuth),
              content: SingleChildScrollView(
                child: ListBody(children: <Widget>[Text(t.allowFunctionExecution), SizedBox(height: 8), Text(event.name), SizedBox(height: 8)]),
              ),
              actions: <Widget>[
                TextButton(
                  child: Text(t.cancel),
                  onPressed: () {
                    setState(() {
                      _runFunctionEvents.clear();
                    });
                    Navigator.of(context).pop(false);
                  },
                ),
                TextButton(
                  child: Text(t.allow),
                  onPressed: () {
                    Navigator.of(context).pop(true);
                  },
                ),
              ],
            );
          },
        ) ??
        false;
  }

  void _addListeners() {
    ProviderManager.chatModelProvider.addListener(_initializeLLMClient);
    ProviderManager.chatProvider.addListener(_onChatProviderChanged);
    ProviderManager.settingsProvider.addListener(_onSettingsChanged);
  }

  void _removeListeners() {
    ProviderManager.chatModelProvider.removeListener(_initializeLLMClient);
    ProviderManager.chatProvider.removeListener(_onChatProviderChanged);
    ProviderManager.settingsProvider.removeListener(_onSettingsChanged);
  }

  void _onSettingsChanged() {
    _initTts();
    _initGlm4VoiceLocal();
    unawaited(_initMojoVoice());
  }

  void _initializeLLMClient() {
    _llmClient = LLMFactoryHelper.createFromModel(ProviderManager.chatModelProvider.currentModel);
    _initTts();
    _initGlm4VoiceLocal();
    setState(() {});
  }

  void _initGlm4VoiceLocal() {
    _glm4VoiceLocalService?.dispose();
    _glm4VoiceLocalService = null;
    final gs = ProviderManager.settingsProvider.generalSetting;
    if (gs.voiceConsoleEngine != 'glm4voice_local') return;
    _glm4VoiceLocalService = Glm4VoiceLocalService(serverUrl: gs.glm4voiceServerUrl, queryPath: gs.glm4voiceQueryPath);
    Logger.root.info('GLM4Voice local service initialized: ${gs.glm4voiceServerUrl}${gs.glm4voiceQueryPath}');
  }

  void _initTts() {
    _ttsAdapter.dispose();
    final gs = ProviderManager.settingsProvider.generalSetting;
    if (gs.voiceConsoleEngine == 'glm4voice_local') {
      _ttsAdapter = NoOpTtsAdapter();
      _sentenceChunker = SentenceChunker();
      Logger.root.info('TTS adapter: NoOp (glm4voice local engine active)');
      return;
    }
    Logger.root.info('VoiceConsole TTS init: enabled=${gs.voiceConsoleTtsEnabled}, provider=${gs.voiceConsoleTtsProvider}');
    if (!gs.voiceConsoleTtsEnabled) {
      _ttsAdapter = NoOpTtsAdapter();
      Logger.root.info('TTS adapter: NoOp (voice console tts disabled)');
      _sentenceChunker = SentenceChunker();
      return;
    }

    final ttsProviderId = gs.voiceConsoleTtsProvider;

    if (ttsProviderId == 'cosyvoice2') {
      final adapter = TtsAdapterFactory.create(providerId: 'cosyvoice2', apiKey: '', baseUrl: gs.ttsServerUrl, voice: gs.ttsVoice);
      _ttsAdapter = adapter ?? NoOpTtsAdapter();
      Logger.root.info('TTS adapter: ${_ttsAdapter.runtimeType} (cosyvoice2 path)');
      _sentenceChunker = SentenceChunker();
      return;
    }

    if (ttsProviderId != 'none' && ttsProviderId.isNotEmpty) {
      final matchingProviders = ProviderManager.settingsProvider.apiSettings.where((s) => s.providerId == ttsProviderId).toList();
      if (matchingProviders.isNotEmpty) {
        final provider = matchingProviders.first;
        final adapter = TtsAdapterFactory.create(
          providerId: ttsProviderId,
          apiKey: provider.apiKey,
          baseUrl: provider.apiEndpoint,
          model: gs.mimoModel,
          voice: ttsProviderId == 'mimo' ? gs.mimoVoice : gs.ttsVoice,
          stylePrompt: gs.mimoStylePrompt,
        );
        _ttsAdapter = adapter ?? NoOpTtsAdapter();
        Logger.root.info('TTS adapter: ${_ttsAdapter.runtimeType} (provider=$ttsProviderId)');
      } else {
        _ttsAdapter = NoOpTtsAdapter();
        Logger.root.warning('TTS adapter fallback: NoOp (provider not found: $ttsProviderId)');
      }
    } else {
      _ttsAdapter = NoOpTtsAdapter();
      Logger.root.info('TTS adapter: NoOp (provider none/empty)');
    }
    _sentenceChunker = SentenceChunker();
    _bufferedSpeaker = BufferedSummarySpeaker(ttsAdapter: _ttsAdapter);
  }

  Future<void> _initMojoVoice() async {
    debugPrint('MoJo: _initMojoVoice called');
    _mojoPendingAudioSub?.cancel();
    _mojoContextSub?.cancel();
    _mojoVoiceService?.dispose();
    _mojoVoiceService = null;

    final gs = ProviderManager.settingsProvider.generalSetting;
    debugPrint('MoJo: enabled=${gs.mojoVoiceEnabled}, url=${gs.mojoVoiceUrl}');
    if (!gs.mojoVoiceEnabled || gs.mojoVoiceUrl.isEmpty) {
      debugPrint('MoJo: not enabled or URL empty, skipping init');
      return;
    }

    _mojoVoiceService = MojoVoiceService(baseUrl: gs.mojoVoiceUrl);
    debugPrint('MoJo: service created');
    _bindMojoVoiceStreams();

    final activeChat = ProviderManager.chatProvider.activeChat;
    debugPrint('MoJo: activeChat=${activeChat?.id}');
    if (activeChat != null) {
      try {
        await _mojoVoiceService!.createSession();
        _ensureMojoPollingActive();
        debugPrint('MoJo: session created');
      } catch (e) {
        debugPrint('MoJo: Failed to create session: $e');
        Logger.root.warning('Failed to create MoJo session: $e');
      }
    } else {
      debugPrint('MoJo: no active chat, session not created yet');
    }
  }

  void _bindMojoVoiceStreams() {
    _mojoPendingAudioSub?.cancel();
    _mojoContextSub?.cancel();
    if (_mojoVoiceService == null) return;
    _mojoPendingAudioSub = _mojoVoiceService!.pendingAudioStream.listen((audioBytes) async {
      await _mojoVoiceService!.playAudio(audioBytes);
    });
    _mojoContextSub = _mojoVoiceService!.contextStream.listen((context) {
      if (context.update && context.content != null) {
        _handleMojoContextUpdate(context);
      }
    });
  }

  void _ensureMojoPollingActive() {
    if (_mojoVoiceService == null) return;
    _mojoVoiceService!.startPolling(interval: const Duration(seconds: 2));
  }

  Future<void> _ensureActiveChatForVoice() async {
    if (ProviderManager.chatProvider.activeChat != null) return;
    await ProviderManager.chatProvider.createChat(Chat(title: 'MoJo Voice'), []);
    _chat = ProviderManager.chatProvider.activeChat;
    _parentMessageId = '';
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _appendVoiceTurn({required String transcript, required String replyText}) async {
    await _ensureActiveChatForVoice();
    if (transcript.trim().isEmpty && replyText.trim().isEmpty) return;
    _suspendHistorySync = true;
    try {
      setState(() {
        if (transcript.trim().isNotEmpty) {
          final userId = const Uuid().v4();
          _messages.add(ChatMessage(messageId: userId, parentMessageId: _parentMessageId, content: transcript.trim(), role: MessageRole.user));
          _parentMessageId = userId;
        }
        if (replyText.trim().isNotEmpty) {
          final assistantId = const Uuid().v4();
          _messages.add(
            ChatMessage(messageId: assistantId, parentMessageId: _parentMessageId, content: replyText.trim(), role: MessageRole.assistant),
          );
          _voiceConsoleOutput.value = replyText.trim();
          _parentMessageId = assistantId;
        }
        _isLoading = false;
      });
      await _updateChat();
    } finally {
      _suspendHistorySync = false;
    }
  }

  Future<void> _appendVoiceContextUpdate(String content, {int? contextVersion}) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;
    if (_lastMojoContextVersion != null && contextVersion != null && contextVersion <= _lastMojoContextVersion!) {
      return;
    }
    _lastMojoContextVersion = contextVersion ?? _lastMojoContextVersion;
    await _ensureActiveChatForVoice();
    setState(() {
      final msgId = const Uuid().v4();
      _messages.add(
        ChatMessage(messageId: msgId, parentMessageId: _parentMessageId, content: '[Voice context update] $trimmed', role: MessageRole.system),
      );
      _parentMessageId = msgId;
    });
    await _updateChat();
  }

  void _handleMojoContextUpdate(ContextResponse context) async {
    debugPrint('MoJo context update: ${context.content}');
    await _appendVoiceContextUpdate(context.content ?? '', contextVersion: context.contextVersion);
  }

  Future<void> _closeMojoSession() async {
    if (_mojoVoiceService != null) {
      await _mojoVoiceService!.closeSession();
      MojoVoicePanelOverlay.hide();
    }
  }

  Future<void> _onMojoVoiceStart() async {
    debugPrint('MoJo: _onMojoVoiceStart called');
    if (_mojoVoiceService == null) {
      debugPrint('MoJo: _mojoVoiceService is NULL');
      return;
    }
    if (_isMojoStartPending || _mojoVoiceService!.isRecording) {
      debugPrint('MoJo: start ignored because recording is already active/pending');
      return;
    }
    _isMojoStartPending = true;
    debugPrint('MoJo: service found');
    _inputAreaKey.currentState?.setMojoRecording(true);

    // Show panel BEFORE starting recording so it can subscribe to state changes
    MojoVoicePanelOverlay.show(context: context, service: _mojoVoiceService!);

    debugPrint('MoJo: calling startRecording...');
    try {
      await _mojoVoiceService!.ensureSession();
      _ensureMojoPollingActive();
      await _mojoVoiceService!.startRecording();
      debugPrint('MoJo: startRecording completed');
    } catch (e) {
      debugPrint('MoJo: startRecording error: $e');
      _inputAreaKey.currentState?.setMojoRecording(false);
      MojoVoicePanelOverlay.hide();
    } finally {
      _isMojoStartPending = false;
    }
  }

  void _onMojoVoiceStop() async {
    debugPrint('MoJo: _onMojoVoiceStop called');
    if (_mojoVoiceService == null) {
      debugPrint('MoJo: _mojoVoiceService is NULL on stop');
      return;
    }
    if (_isMojoStopPending) return;
    _isMojoStopPending = true;
    _inputAreaKey.currentState?.setMojoRecording(false);
    debugPrint('MoJo: calling stopRecording...');
    Uint8List audioBytes = Uint8List(0);
    try {
      audioBytes = await _mojoVoiceService!.stopRecording();
    } catch (e) {
      debugPrint('MoJo: stopRecording error: $e');
    }
    debugPrint('MoJo: stopRecording returned ${audioBytes.length} bytes');

    if (audioBytes.isNotEmpty) {
      try {
        await _mojoVoiceService!.ensureSession();
        debugPrint('MoJo: sending query...');
        final response = await _mojoVoiceService!.queryAudio(audioBytes);
        debugPrint('MoJo: query response transcript: ${response.transcript}');
        await _appendVoiceTurn(transcript: response.transcript, replyText: response.replyText);

        // Play audio reply
        if (response.replyAudioBase64.isNotEmpty) {
          await _mojoVoiceService!.playFromBase64(response.replyAudioBase64, format: response.replyAudioFormat);
        }

        // Trigger text brain in parallel while MoJo polling remains active.
        if (response.transcript.isNotEmpty) {
          unawaited(_triggerTextBrainForVoice());
        }
      } catch (e) {
        debugPrint('MoJo query failed: $e');
      }
    } else {
      debugPrint('MoJo: No audio recorded');
    }
    MojoVoicePanelOverlay.hide();
    _isMojoStopPending = false;
  }

  void _onMojoVoiceCancel() {
    if (_mojoVoiceService == null) return;
    _inputAreaKey.currentState?.setMojoRecording(false);
    _mojoVoiceService!.stopRecording();
    MojoVoicePanelOverlay.hide();
  }

  Future<void> _openVoiceConsole() async {
    // Always use dialog - desktop_multi_window sub-window crashes on macOS
    // due to plugin registration issues. Revisit when desktop_multi_window
    // adds proper sub-window plugin support.
    await _openVoiceConsoleDialog();
  }

  Future<void> _openVoiceConsoleDialog() async {
    _voiceConsoleActive = true;
    await showDialog(
      context: context,
      builder: (_) => VoiceConsoleDialog(
        assistantOutput: _voiceConsoleOutput,
        preferredLanguage: _voiceConsoleLanguage,
        speechToSpeechEnabled: ProviderManager.settingsProvider.generalSetting.voiceConsoleEngine == 'glm4voice_local',
        shareVoiceToChat: _shareVoiceToChat,
        shareChatToVoice: _shareChatToVoice,
        onPreferredLanguageChanged: (value) => _voiceConsoleLanguage.value = value,
        onShareVoiceToChatChanged: (value) => _shareVoiceToChat.value = value,
        onShareChatToVoiceChanged: (value) => _shareChatToVoice.value = value,
        onStartAudioTurn: _startVoiceConsoleAudioTurn,
        onFinishAudioTurn: _finishVoiceConsoleAudioTurn,
        onSubmitText: (text) async {
          await _handleVoiceConsoleSubmit(text);
        },
      ),
    );
    _voiceConsoleActive = false;
  }

  void _enqueueVoiceSubmit(SubmitData data, {bool cancelTtsBeforeSubmit = false}) {
    _voiceSubmitQueue = _voiceSubmitQueue.then((_) => _handleSubmitted(data, cancelTtsBeforeSubmit: cancelTtsBeforeSubmit)).catchError((
      e,
      stackTrace,
    ) {
      Logger.root.warning('Voice submit queue failed: $e');
    });
  }

  Future<void> _handleVoiceConsoleSubmit(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final classifier = VoiceClassifier();
    final result = classifier.classify(trimmed);

    // 1. Instant acknowledgment via TTS
    _voiceConsoleOutput.value = result.immediateResponse;
    if (_ttsAdapter is! NoOpTtsAdapter) {
      _ttsAdapter.speak(result.immediateResponse);
    }

    // 2. Mirror to main chat if enabled
    if (_shareVoiceToChat.value) {
      _enqueueVoiceSubmit(SubmitData(trimmed, []), cancelTtsBeforeSubmit: false);
    }

    // 3. For greetings/acks, done (no LLM needed in voice console)
    if (result.inputClass == VoiceInputClass.greeting || result.inputClass == VoiceInputClass.ack) {
      return;
    }

    // 4. For questions/statements, process in voice console background (NO tool calls)
    if (!_shareVoiceToChat.value || !_shareChatToVoice.value) {
      _voiceConsoleOutput.value = 'Processing...';
      unawaited(_processVoiceInBackground(trimmed));
    } else {
      // If both share directions are on, the main chat stream will handle TTS
      _voiceConsoleOutput.value = 'Processing...';
    }
  }

  Future<void> _processVoiceInBackground(String text) async {
    try {
      final llmClient = _llmClient;
      if (llmClient == null) return;

      final extractor = VoiceResponseExtractor();
      final modelName = ProviderManager.chatModelProvider.currentModel.name;
      final systemPrompt = await _getSystemPrompt();

      final stream = llmClient.chatStreamCompletion(
        CompletionRequest(
          model: modelName,
          messages: [
            ChatMessage(content: systemPrompt, role: MessageRole.system),
            ChatMessage(content: text, role: MessageRole.user),
          ],
          modelSetting: ProviderManager.settingsProvider.modelSetting,
        ),
      );

      final buffer = StringBuffer();
      await for (final chunk in stream) {
        if (chunk.content != null) {
          buffer.write(chunk.content);
        }
      }

      final raw = buffer.toString();
      final cleaned = extractor.extract(raw);

      if (cleaned.isNotEmpty) {
        _voiceConsoleOutput.value = cleaned;
        if (_ttsAdapter is! NoOpTtsAdapter) {
          _ttsAdapter.speak(cleaned);
        }
      }
    } catch (e) {
      Logger.root.warning('Voice background processing failed: $e');
      _voiceConsoleOutput.value = 'Sorry, I had trouble processing that.';
    }
  }

  Future<void> _startVoiceConsoleAudioTurn() async {
    final service = _glm4VoiceLocalService;
    if (service == null) {
      _voiceConsoleOutput.value = 'GLM4Voice local engine is not initialized.';
      return;
    }
    _voiceConsoleOutput.value = 'Listening...';
    await service.startRecording();
  }

  Future<void> _finishVoiceConsoleAudioTurn() async {
    final service = _glm4VoiceLocalService;
    if (service == null) {
      _voiceConsoleOutput.value = 'GLM4Voice local engine is not initialized.';
      return;
    }
    _voiceConsoleOutput.value = 'Processing audio...';
    final language = _voiceConsoleLanguage.value;
    final response = await service.stopRecordingAndQuery(language: language);

    final spoken = _sanitizeForVoice(response.replyText);
    final transcript = response.transcript.trim();
    if (spoken.isNotEmpty) {
      _voiceConsoleOutput.value = spoken;
    } else if (transcript.isNotEmpty) {
      _voiceConsoleOutput.value = transcript;
    } else {
      _voiceConsoleOutput.value = 'Received audio response.';
    }

    if (response.replyAudioBytes != null && response.replyAudioBytes!.isNotEmpty) {
      await service.playAudio(response.replyAudioBytes!, format: response.replyAudioFormat);
    }

    if (_shareVoiceToChat.value && transcript.isNotEmpty) {
      _enqueueVoiceSubmit(SubmitData(transcript, []), cancelTtsBeforeSubmit: false);
    }
  }

  void _onChatProviderChanged() {
    if (!_suspendHistorySync) {
      _initializeHistoryMessages();
    }
    if (_isMobile() && ProviderManager.chatProvider.showCodePreview && ProviderManager.chatProvider.artifactEvent != null) {
      _showMobileCodePreview();
    } else {
      setState(() {
        _showCodePreview = ProviderManager.chatProvider.showCodePreview;
      });
    }
  }

  bool _showCodePreview = false;

  List<ChatMessage> _allMessages = [];

  Future<List<ChatMessage>> _getHistoryTreeMessages() async {
    final activeChat = ProviderManager.chatProvider.activeChat;
    if (activeChat == null) return [];

    Map<String, List<String>> messageMap = {};

    final messages = await activeChat.getChatMessages();

    for (var message in messages) {
      if (message.role == MessageRole.user) {
        continue;
      }
      if (messageMap[message.parentMessageId] == null) {
        messageMap[message.parentMessageId] = [];
      }

      messageMap[message.parentMessageId]?.add(message.messageId);
    }

    for (var message in messages) {
      final brotherIds = messageMap[message.messageId] ?? [];

      if (brotherIds.length > 1) {
        int index = messages.indexWhere((m) => m.messageId == message.messageId);
        if (index != -1) {
          messages[index].childMessageIds ??= brotherIds;
        }

        for (var brotherId in brotherIds) {
          final index = messages.indexWhere((m) => m.messageId == brotherId);
          if (index != -1) {
            messages[index].brotherMessageIds ??= brotherIds;
          }
        }
      }
    }

    setState(() {
      _allMessages = messages;
    });

    if (messages.isEmpty) {
      return [];
    }

    final lastMessage = messages.last;
    return _getTreeMessages(lastMessage.messageId, messages);
  }

  List<ChatMessage> _getTreeMessages(String messageId, List<ChatMessage> messages) {
    final lastMessage = messages.firstWhere((m) => m.messageId == messageId);
    List<ChatMessage> treeMessages = [];

    ChatMessage? currentMessage = lastMessage;
    while (currentMessage != null) {
      if (currentMessage.role != MessageRole.user) {
        final childMessageIds = currentMessage.childMessageIds;
        if (childMessageIds != null && childMessageIds.isNotEmpty) {
          for (var childId in childMessageIds.reversed) {
            final childMessage = messages.firstWhere(
              (m) => m.messageId == childId,
              orElse: () => ChatMessage(content: '', role: MessageRole.user),
            );
            if (treeMessages.any((m) => m.messageId == childMessage.messageId)) {
              continue;
            }
            treeMessages.insert(0, childMessage);
          }
        }
      }

      treeMessages.insert(0, currentMessage);

      final parentId = currentMessage.parentMessageId;
      if (parentId.isEmpty) break;

      currentMessage = messages.firstWhere(
        (m) => m.messageId == parentId,
        orElse: () => ChatMessage(messageId: '', content: '', role: MessageRole.user, parentMessageId: ''),
      );

      if (currentMessage.messageId.isEmpty) break;
    }

    ChatMessage? nextMessage = messages
        .where((m) => m.role == MessageRole.user)
        .firstWhere(
          (m) => m.parentMessageId == lastMessage.messageId,
          orElse: () => ChatMessage(messageId: '', content: '', role: MessageRole.user),
        );

    while (nextMessage != null && nextMessage.messageId.isNotEmpty) {
      if (!treeMessages.any((m) => m.messageId == nextMessage!.messageId)) {
        treeMessages.add(nextMessage);
      }
      final childMessageIds = nextMessage.childMessageIds;
      if (childMessageIds != null && childMessageIds.isNotEmpty) {
        for (var childId in childMessageIds) {
          final childMessage = messages.firstWhere(
            (m) => m.messageId == childId,
            orElse: () => ChatMessage(messageId: '', content: '', role: MessageRole.user),
          );
          if (treeMessages.any((m) => m.messageId == childMessage.messageId)) {
            continue;
          }
          treeMessages.add(childMessage);
        }
      }

      nextMessage = messages.firstWhere(
        (m) => m.parentMessageId == nextMessage!.messageId,
        orElse: () => ChatMessage(messageId: '', content: '', role: MessageRole.user),
      );
    }

    return treeMessages;
  }

  // Message processing related methods
  Future<void> _initializeHistoryMessages() async {
    if (_suspendHistorySync) return;
    final activeChat = ProviderManager.chatProvider.activeChat;
    if (activeChat == null) {
      setState(() {
        _messages = [];
        _chat = null;
        _parentMessageId = '';
      });
      _resetState();
      await _closeMojoSession();
      // Auto focus input on desktop when creating new chat
      if (!kIsMobile) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _inputAreaKey.currentState?.requestFocus();
        });
      }
      return;
    }

    if (_chat?.id != activeChat.id) {
      final messages = await _getHistoryTreeMessages();
      // Find the index of the last user message
      final lastUserIndex = messages.lastIndexWhere((m) => m.role == MessageRole.user);
      String parentId = '';

      // If a user message is found, and there is an assistant message after it, use the ID of the assistant message
      if (lastUserIndex != -1 && lastUserIndex + 1 < messages.length) {
        parentId = messages[lastUserIndex + 1].messageId;
      } else if (messages.isNotEmpty) {
        // If no suitable message is found, use the ID of the last message
        parentId = messages.last.messageId;
      }

      ProviderManager.chatProvider.clearArtifactEvent();

      setState(() {
        _messages = messages;
        _chat = activeChat;
        _parentMessageId = parentId;
      });
      _resetState();
      await _initMojoVoice();
      // Auto focus input on desktop when switching to a different chat
      if (!kIsMobile) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _inputAreaKey.currentState?.requestFocus();
        });
      }
    }
  }

  // UI building related methods
  Widget _buildMessageList() {
    if (_messages.isEmpty) {
      final l10n = AppLocalizations.of(context)!;
      return Expanded(
        child: Container(
          color: AppColors.transparent,
          child: Center(
            child: Text(l10n.welcomeMessage, style: TextStyle(fontSize: 18, color: AppColors.getWelcomeMessageColor())),
          ),
        ),
      );
    }

    final parentMsgIndex = _messages.length - 1;
    for (var i = 0; i < parentMsgIndex; i++) {
      final content = _messages[i].content;
      if (content?.contains('<function') == true) {
        var normalized = content!;
        if (!normalized.contains('<function done="true"')) {
          normalized = normalized.replaceAll("<function ", "<function done=\"true\" ");
        }
        if (!normalized.contains('</function>')) {
          normalized = '$normalized</function>';
        }
        _messages[i] = _messages[i].copyWith(content: normalized);
      }
    }

    return Expanded(
      child: MessageList(
        messages: _isWaiting ? [..._messages, ChatMessage(content: '', role: MessageRole.loading)] : _messages.toList(),
        onRetry: _onRetry,
        onSwitch: _onSwitch,
      ),
    );
  }

  void _onSwitch(String messageId) {
    final messages = _getTreeMessages(messageId, _allMessages);
    setState(() {
      _messages = messages;
    });
  }

  // Message processing related methods
  void _handleTextChanged(String text) {
    setState(() {
      _isComposing = text.isNotEmpty;
    });
  }

  String? _findClientName(Map<String, List<Map<String, dynamic>>> tools, String toolName) {
    for (var entry in tools.entries) {
      final clientTools = entry.value;
      if (clientTools.any((tool) => tool['name'] == toolName)) {
        return entry.key;
      }
    }
    return null;
  }

  Future<void> _sendToolCallAndProcessResponse(String toolName, Map<String, dynamic> toolArguments) async {
    final clientName = _findClientName(ProviderManager.mcpServerProvider.tools, toolName);
    if (clientName == null) {
      Logger.root.severe('No MCP server found for tool: $toolName');
      return;
    }

    final mcpClient = ProviderManager.mcpServerProvider.getClient(clientName);
    if (mcpClient == null) {
      Logger.root.severe('No MCP client found for tool: $toolName');
      return;
    }

    // Configures tool call with timeout and retry mechanism
    const int maxRetries = 3;
    const Duration timeout = Duration(seconds: 60 * 5);

    JSONRPCMessage? response;
    String? lastError;

    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        Logger.root.info('send tool call attempt ${attempt + 1}/$maxRetries - name: $toolName arguments: $toolArguments');

        response = await mcpClient.sendToolCall(name: toolName, arguments: toolArguments).timeout(timeout);

        // Exits retry loop on successful response
        break;
      } catch (e) {
        lastError = e.toString();
        Logger.root.warning('tool call attempt ${attempt + 1}/$maxRetries failed: $e');

        // Implements exponential backoff before next retry attempt
        if (attempt < maxRetries - 1) {
          final delay = Duration(seconds: (attempt + 1) * 2); // Incremental delay
          Logger.root.info('waiting ${delay.inSeconds}s before retry...');
          await Future.delayed(delay);
        }
      }
    }

    // Logs error and updates UI when all retry attempts fail
    if (response == null) {
      Logger.root.severe('Tool call failed after $maxRetries attempts: $lastError');
      setState(() {
        _parentMessageId = _messages.last.messageId;
        final msgId = Uuid().v4();
        _messages.add(
          ChatMessage(
            messageId: msgId,
            content: '<call_function_result name="$toolName"> failed to call function: $lastError</call_function_result>',
            role: MessageRole.assistant,
            name: toolName,
            parentMessageId: _parentMessageId,
          ),
        );
        _parentMessageId = msgId;
      });
      return;
    }

    Logger.root.info('Tool call success - name: $toolName arguments: $toolArguments response: $response');

    setState(() {
      final contentList = response!.result['content'];
      if (contentList is List && contentList.isNotEmpty) {
        _currentResponse = contentList
            .map((item) {
              if (item is Map && item['type'] == 'text') {
                return item['text']?.toString() ?? '';
              }
              return item.toString();
            })
            .join('\n');
      } else {
        _currentResponse = contentList?.toString() ?? '';
      }
      if (_currentResponse.isNotEmpty) {
        _parentMessageId = _messages.last.messageId;
        final msgId = Uuid().v4();
        _messages.add(
          ChatMessage(
            messageId: msgId,
            content: '<call_function_result name="$toolName">$_currentResponse</call_function_result>',
            role: MessageRole.assistant,
            name: toolName,
            parentMessageId: _parentMessageId,
          ),
        );
        _parentMessageId = msgId;
      }
    });
  }

  ChatMessage? _findUserMessage(ChatMessage message) {
    final parentMessage = _messages.firstWhere(
      (m) => m.messageId == message.parentMessageId,
      orElse: () => ChatMessage(messageId: '', content: '', role: MessageRole.user),
    );

    if (parentMessage.messageId.isEmpty) return null;

    if (parentMessage.role != MessageRole.user) {
      return _findUserMessage(parentMessage);
    }

    return parentMessage;
  }

  Future<void> _onRetry(ChatMessage message) async {
    final userMessage = _findUserMessage(message);
    if (userMessage == null) return;

    final messageIndex = _messages.indexOf(userMessage);
    if (messageIndex == -1) return;

    final previousMessages = _messages.sublist(0, messageIndex + 1);

    setState(() {
      _messages = previousMessages;
      _parentMessageId = userMessage.messageId;
      _isLoading = true;
    });

    await _handleSubmitted(
      SubmitData(userMessage.content ?? '', (userMessage.files ?? []).map((f) => f as PlatformFile).toList()),
      addUserMessage: false,
    );
  }

  /// function calling style tool use
  Future<bool> _checkNeedToolCallFunction() async {
    if (_runFunctionEvents.isNotEmpty) return true;

    final lastMessage = _messages.last;

    final content = lastMessage.content ?? '';
    if (content.isEmpty) return false;

    final messages = _messages.toList();

    Logger.root.info('check need tool call: $messages');

    final result = await _llmClient!.checkToolCall(
      ProviderManager.chatModelProvider.currentModel.name,
      CompletionRequest(model: ProviderManager.chatModelProvider.currentModel.name, messages: [..._prepareMessageList()]),
      ProviderManager.mcpServerProvider.tools,
    );
    final needToolCall = result['need_tool_call'] ?? false;

    if (!needToolCall) {
      return false;
    }

    final toolCalls = (result['tool_calls'] as List?) ?? const [];
    if (toolCalls.isEmpty) {
      Logger.root.warning('need_tool_call=true but tool_calls is empty');
      return false;
    }
    var queuedAny = false;
    for (var toolCall in toolCalls) {
      if (toolCall is! Map<String, dynamic>) continue;
      final toolName = (toolCall['name'] ?? '').toString().trim();
      if (toolName.isEmpty) {
        Logger.root.warning('Skipping tool call with empty name: $toolCall');
        continue;
      }
      final functionEvent = RunFunctionEvent(toolName, toolCall['arguments']);

      _runFunctionEvents.add(functionEvent);
      queuedAny = true;

      _messages.add(
        ChatMessage(
          content: "<function name=\"${functionEvent.name}\">\n${jsonEncode(functionEvent.arguments)}\n</function>",
          role: MessageRole.assistant,
          parentMessageId: _parentMessageId,
        ),
      );

      _onRunFunction(functionEvent);
    }

    return needToolCall && queuedAny;
  }

  /// xml style function calling tool use
  Future<bool> _checkNeedToolCallXml() async {
    if (_runFunctionEvents.isNotEmpty) return true;

    final lastMessage = _messages.last;
    if (lastMessage.role == MessageRole.user) return true;

    final content = lastMessage.content ?? '';
    if (content.isEmpty) return false;

    // Parses function call tags in format <function name="toolName">args</function>
    final RegExp functionTagRegex = RegExp('<function\\s+name=["\']([^"\']*)["\']\\s*>(.*?)</function>', dotAll: true);
    final matches = functionTagRegex.allMatches(content);

    if (matches.isEmpty) return false;

    // Build structured toolCalls list for the chat UI ToolCallWidget
    // Track already-dispatched calls to prevent duplicate tool calls
    final toolCallsList = <Map<String, dynamic>>[];
    final dispatchedCalls = <String>{};
    for (var match in matches) {
      final toolName = match.group(1);
      final toolArguments = match.group(2);
      if (toolName == null || toolArguments == null) continue;
      try {
        final normalizedToolName = toolName.trim();
        if (normalizedToolName.isEmpty) continue;
        final cleanedToolArguments = toolArguments.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
        if (cleanedToolArguments.isEmpty) continue;
        jsonDecode(cleanedToolArguments); // validate JSON
        final callKey = '$normalizedToolName:$cleanedToolArguments';
        if (dispatchedCalls.contains(callKey)) {
          Logger.root.info('Skipping duplicate tool call: $normalizedToolName');
          continue;
        }
        dispatchedCalls.add(callKey);
        toolCallsList.add({
          'id': 'xml_${Uuid().v4()}',
          'function': {'name': normalizedToolName, 'arguments': cleanedToolArguments},
        });
        _onRunFunction(RunFunctionEvent(normalizedToolName, jsonDecode(cleanedToolArguments)));
      } catch (e) {
        Logger.root.warning('Failed to parse tool parameters for $toolName: $e');
        continue;
      }
    }

    // Set toolCalls on the message so ToolCallWidget renders properly
    // Strip function XML from content (API rejects mixed toolCalls + XML content)
    if ((toolCallsList.isNotEmpty || _runFunctionEvents.isNotEmpty) && _messages.isNotEmpty) {
      final calls = toolCallsList.isNotEmpty
          ? toolCallsList
          : _runFunctionEvents
                .map(
                  (e) => {
                    'id': 'xml_${Uuid().v4()}',
                    'function': {'name': e.name, 'arguments': jsonEncode(e.arguments)},
                  },
                )
                .toList();
      // Remove function XML from content so API sees clean tool_calls format
      final cleanContent = content.replaceAll(functionTagRegex, '').trim();
      _messages.last = _messages.last.copyWith(toolCalls: calls, content: cleanContent);
      _currentResponse = cleanContent;
    }

    return _runFunctionEvents.isNotEmpty;
  }

  Future<bool> _checkNeedToolCall() async {
    return await _checkNeedToolCallXml();
  }

  // Message submission processing
  Future<void> _handleSubmitted(SubmitData data, {bool addUserMessage = true, bool cancelTtsBeforeSubmit = true}) async {
    if (cancelTtsBeforeSubmit) {
      _ttsAdapter.cancel();
    }

    setState(() {
      _isCancelled = false;
    });

    final currentModel = ProviderManager.chatModelProvider.currentModel;
    final strategy = FileUploadHandler.getStrategy(currentModel.providerId, currentModel.name);
    Logger.root.info('Preparing ${data.files.length} files with strategy: $strategy for provider ${currentModel.providerId}');

    final files = <File>[];
    final filesList = List<PlatformFile>.from(data.files);

    // Identify PDF page images vs regular files
    final pageFiles = <PlatformFile>[];
    final otherFiles = <PlatformFile>[];
    for (final f in filesList) {
      final name = f.name.toLowerCase();
      if (name.endsWith('.png') && name.contains('_page_')) {
        pageFiles.add(f);
      } else {
        otherFiles.add(f);
      }
    }

    // Process non-page files (regular attachments)
    for (final file in otherFiles) {
      final preparedFile = await FileUploadHandler.prepareFile(file, strategy);
      if (preparedFile.fileContent.isNotEmpty || preparedFile.path != null) {
        files.add(preparedFile);
      }
    }

    // If there are page files, process them one by one with the user's text
    if (pageFiles.isNotEmpty) {
      // Add user's text as a message (with non-page files if any)
      if (addUserMessage && data.text.isNotEmpty) {
        _addUserMessage(data.text, files);
      }

      try {
        final generalSetting = ProviderManager.settingsProvider.generalSetting;
        final maxLoops = generalSetting.maxLoops;
        while (await _checkNeedToolCall()) {
          if (_currentLoop > maxLoops) break;
          if (_runFunctionEvents.isNotEmpty) {
            while (_runFunctionEvents.isNotEmpty) {
              final event = _runFunctionEvents.first;
              final approved = await _showFunctionApprovalDialog(event);
              if (approved) {
                setState(() => _isRunningFunction = true);
                await _sendToolCallAndProcessResponse(event.name, event.arguments);
                setState(() => _isRunningFunction = false);
                _runFunctionEvents.removeAt(0);
              } else {
                setState(() => _runFunctionEvents.clear());
                break;
              }
            }
          }
          await _processLLMResponse();
          _currentLoop++;
        }
      } catch (e, stackTrace) {
        _handleError(e, stackTrace);
      }

      // Send each page one by one
      for (final pageFile in pageFiles) {
        if (_isCancelled) break;
        await _handlePdfPageSubmitted(pageFile);
      }

      await _updateChat();
      unawaited(_pushLatestAssistantSummaryToMojo());
      return;
    }

    if (addUserMessage && data.text.isNotEmpty) {
      _addUserMessage(data.text, files);
    }

    try {
      final generalSetting = ProviderManager.settingsProvider.generalSetting;
      final maxLoops = generalSetting.maxLoops;

      while (await _checkNeedToolCall()) {
        if (_currentLoop > maxLoops) {
          Logger.root.warning('reach max loops: $maxLoops');
          break;
        }

        if (_runFunctionEvents.isNotEmpty) {
          while (_runFunctionEvents.isNotEmpty) {
            final event = _runFunctionEvents.first;
            final approved = await _showFunctionApprovalDialog(event);

            if (approved) {
              setState(() => _isRunningFunction = true);
              await _sendToolCallAndProcessResponse(event.name, event.arguments);
              setState(() => _isRunningFunction = false);
              _runFunctionEvents.removeAt(0);
            } else {
              setState(() => _runFunctionEvents.clear());
              final msgId = Uuid().v4();
              _messages.add(
                ChatMessage(messageId: msgId, content: 'call function rejected', role: MessageRole.assistant, parentMessageId: _parentMessageId),
              );
              _parentMessageId = msgId;
              break;
            }
          }
        }

        await _processLLMResponse();
        _currentLoop++;
      }
      await _updateChat();
      unawaited(_pushLatestAssistantSummaryToMojo());
    } catch (e, stackTrace) {
      _handleError(e, stackTrace);
      await _updateChat();
    }

    setState(() {
      _isLoading = false;
    });
    // Auto focus input on desktop when response completes
    if (!kIsMobile) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _inputAreaKey.currentState?.requestFocus();
      });
    }
  }

  Future<bool> _handleTestImageSilent(PlatformFile page) async {
    if (_llmClient == null) return false;
    try {
      final modelName = ProviderManager.chatModelProvider.currentModel.name;
      final setting = ProviderManager.settingsProvider.apiSettings.firstWhere(
        (s) => s.providerId == ProviderManager.chatModelProvider.currentModel.providerId,
      );
      if (setting.apiKey.isEmpty) return false;

      final prepared = await FileUploadHandler.prepareFile(page, FileUploadHandler.getStrategy(setting.providerId!, modelName));
      if (prepared.fileContent.isEmpty) return false;

      // Don't include system prompt — it may trigger tool calls
      await _llmClient!.chatCompletion(
        CompletionRequest(
          model: modelName,
          messages: [
            ChatMessage(role: MessageRole.user, content: 'ok', files: [prepared]),
          ],
          stream: false,
        ),
      );
      return true;
    } catch (e) {
      Logger.root.info('Silent image test failed: $e');
      return false;
    }
  }

  Future<bool> _handlePdfPageSubmitted(PlatformFile page) async {
    try {
      final currentModel = ProviderManager.chatModelProvider.currentModel;
      final strategy = FileUploadHandler.getStrategy(currentModel.providerId, currentModel.name);
      final preparedFile = await FileUploadHandler.prepareFile(page, strategy);

      if (preparedFile.fileContent.isEmpty && preparedFile.path == null) {
        Logger.root.warning('Failed to prepare PDF page: ${page.name}');
        return false;
      }

      _addUserMessage('', [preparedFile]);
      setState(() => _isComposing = false);
      await _processLLMResponse();
      return true;
    } catch (e) {
      Logger.root.warning('PDF page submission failed: $e');
      return false;
    }
  }

  void _addUserMessage(String text, List<File> files) {
    setState(() {
      _isLoading = true;
      _isComposing = false;
      final msgId = Uuid().v4();
      _messages.add(
        ChatMessage(
          messageId: msgId,
          parentMessageId: _parentMessageId,
          content: text.replaceAll('\n', '\n\n'),
          role: MessageRole.user,
          files: files,
        ),
      );
      _parentMessageId = msgId;
    });
  }

  Future<String> _getSystemPrompt() async {
    // return ProviderManager.settingsProvider.generalSetting.systemPrompt;

    final promptGenerator = SystemPromptGenerator();

    var tools = <Map<String, dynamic>>[];
    for (var entry in ProviderManager.mcpServerProvider.tools.entries) {
      if (ProviderManager.serverStateProvider.isEnabled(entry.key)) {
        tools.addAll(entry.value);
      }
    }

    var prompt = promptGenerator.generatePrompt(tools: tools);

    // When TTS is active, constrain output for voice.
    final ttsProvider = ProviderManager.settingsProvider.generalSetting.ttsProvider;
    if (ttsProvider != 'none' && ttsProvider.isNotEmpty && _ttsAdapter is! NoOpTtsAdapter) {
      prompt += '''

<voice_output_rules>
Your response will be spoken aloud via text-to-speech. CRITICAL rules:
- MAXIMUM 2 sentences. Under 30 words total.
- ONLY the final answer. No reasoning, no thinking, no analysis.
- NEVER narrate your process ("I should...", "Let me...", "I need to...")
- NEVER repeat the user's question
- NEVER include task IDs, JSON, XML, function calls, or technical details
- NEVER include labels like "Here is" or "The answer is"
- Just state the fact directly as if speaking to a friend
- If you used tools, summarize ONLY the human-relevant outcome
</voice_output_rules>''';
    }

    return prompt;
  }

  Future<void> _triggerTextBrainForVoice() async {
    if (_llmClient == null) return;
    setState(() {
      _isLoading = true;
      _isCancelled = false;
      _currentLoop = 0;
    });
    try {
      await _processLLMResponse();
      await _updateChat();
      unawaited(_pushLatestAssistantSummaryToMojo());
    } catch (e, stackTrace) {
      _handleError(e, stackTrace);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _processLLMResponse() async {
    setState(() {
      _isWaiting = true;
    });

    List<ChatMessage> messageList = _prepareMessageList();

    final modelSetting = ProviderManager.settingsProvider.modelSetting;
    final generalSetting = ProviderManager.settingsProvider.generalSetting;

    // Limit the number of messages
    final maxMessages = generalSetting.maxMessages;
    if (messageList.length > maxMessages) {
      messageList = messageList.sublist(messageList.length - maxMessages);
    }

    // Converts assistant's function call results to user role for proper context
    for (var message in messageList) {
      if (message.role == MessageRole.assistant && message.content?.contains('done="true"') == true) {
        messageList[messageList.indexOf(message)] = message.copyWith(content: message.content?.replaceAll('done="true"', ''));
      }
      if (message.role == MessageRole.assistant && message.content?.startsWith('<call_function_result') == true) {
        messageList[messageList.indexOf(message)] = message.copyWith(
          role: MessageRole.user,
          content: message.content
              ?.replaceAll('<call_function_result name="', 'tool result: ')
              .replaceAll('">', '')
              .replaceAll('</call_function_result>', ''),
        );
      }
    }

    var messageList0 = messageMerge(messageList);

    if (messageList0.isNotEmpty && messageList0.last.role == MessageRole.assistant) {
      messageList0.add(ChatMessage(content: 'continue', role: MessageRole.user));
    }

    final modelName = ProviderManager.chatModelProvider.currentModel.name;
    final currentModel = ProviderManager.chatModelProvider.currentModel;
    final providerSetting = ProviderManager.settingsProvider.apiSettings.firstWhere(
      (s) => s.providerId == currentModel.providerId,
      orElse: () => LLMProviderSetting(apiKey: '', apiEndpoint: '', providerId: currentModel.providerId),
    );
    final systemPrompt = await _getSystemPrompt();

    // Analyze context usage and summarize if needed
    final contextUsage = TokenEstimator.analyzeContextUsage(messageList0, modelName, providerContextWindow: providerSetting.contextWindow);
    Logger.root.info(
      'Context usage: ${contextUsage.totalTokens}/${contextUsage.contextWindow} '
      '(${(contextUsage.usageRatio * 100).toStringAsFixed(1)}%) '
      'text:${contextUsage.textTokens} images:${contextUsage.imageTokens} files:${contextUsage.fileTokens}',
    );

    if (contextUsage.needsSummarization) {
      Logger.root.info('Context usage exceeds threshold, triggering summarization');

      final toSummarize = MessageSelector.selectMessagesToSummarize(messageList0, contextUsage);
      if (toSummarize.isNotEmpty) {
        final summary = await ConversationSummarizer.summarize(
          messages: toSummarize,
          summarizeWithLLM: (prompt) => _summarizeWithLLM(prompt, modelName),
        );

        Logger.root.info(
          'Summarization saved ${summary.tokensSaved} tokens '
          '(${summary.originalMessageCount} messages → ${summary.summaryTokenCount} tokens)',
        );

        messageList0 = ConversationSummarizer.buildCompressedMessages(allMessages: messageList0, summarizedMessages: toSummarize, summary: summary);
      }
    }

    Logger.root.info('Start processing LLM response: ${messageList0.length} messages');
    Logger.root.info('System prompt (first 100 chars): "${systemPrompt.length > 100 ? systemPrompt.substring(0, 100) : systemPrompt}..."');
    _speechFilter.reset();
    _bufferedSpeaker.reset();

    final stream = _llmClient!.chatStreamCompletion(
      CompletionRequest(
        model: modelName,
        messages: [
          ChatMessage(content: systemPrompt, role: MessageRole.system),
          ...messageList0,
        ],
        modelSetting: modelSetting,
      ),
    );

    _initializeAssistantResponse();
    await _processResponseStream(stream);
    Logger.root.info('End processing LLM response');
  }

  Future<String> _summarizeWithLLM(String prompt, String modelName) async {
    try {
      final stream = _llmClient!.chatStreamCompletion(
        CompletionRequest(
          model: modelName,
          messages: [
            ChatMessage(content: 'You are a conversation summarizer.', role: MessageRole.system),
            ChatMessage(content: prompt, role: MessageRole.user),
          ],
          modelSetting: ChatSetting(temperature: 0.3, maxTokens: 1000),
        ),
      );

      final buffer = StringBuffer();
      await for (final chunk in stream) {
        if (chunk.content != null) {
          buffer.write(chunk.content);
        }
      }
      return buffer.toString();
    } catch (e) {
      Logger.root.severe('Summarization failed: $e');
      rethrow;
    }
  }

  List<ChatMessage> _prepareMessageList() {
    final List<ChatMessage> messageList = _messages
        .map(
          (m) => ChatMessage(
            role: m.role,
            content: m.content,
            toolCallId: m.toolCallId,
            name: m.name,
            // toolCalls is used for UI rendering only in this app flow.
            // Sending it back to chat/completions without strict tool-role reply
            // chaining can produce invalid messages payloads.
            toolCalls: null,
            files: m.files,
          ),
        )
        .toList();

    _reorderMessages(messageList);
    return messageList;
  }

  List<ChatMessage> messageMerge(List<ChatMessage> messageList) {
    if (messageList.isEmpty) return [];

    final newMessages = [messageList.first];

    for (final message in messageList.sublist(1)) {
      final last = newMessages.last;
      final lastContent = last.content ?? '';
      final currentContent = message.content ?? '';
      final hasToolXml =
          lastContent.contains('<function') ||
          lastContent.contains('<call_function_result') ||
          currentContent.contains('<function') ||
          currentContent.contains('<call_function_result');

      if (newMessages.isNotEmpty && last.role == message.role && !hasToolXml) {
        String content = message.content ?? '';

        newMessages.last = newMessages.last.copyWith(content: '${newMessages.last.content}\n\n$content');
      } else {
        newMessages.add(message);
      }
    }

    if (newMessages.isNotEmpty && newMessages.last.role != MessageRole.user) {
      newMessages.add(ChatMessage(content: 'continue', role: MessageRole.user));
    }

    return newMessages;
  }

  void _reorderMessages(List<ChatMessage> messageList) {
    for (int i = 0; i < messageList.length - 1; i++) {
      if (messageList[i].role == MessageRole.user && messageList[i + 1].role == MessageRole.tool) {
        final temp = messageList[i];
        messageList[i] = messageList[i + 1];
        messageList[i + 1] = temp;
        i++;
      }
    }
  }

  void _initializeAssistantResponse() {
    setState(() {
      _currentResponse = '';
      _messages.add(ChatMessage(content: _currentResponse, role: MessageRole.assistant, parentMessageId: _parentMessageId));
    });
  }

  Future<void> _processResponseStream(Stream<LLMResponse> stream) async {
    bool isFirstChunk = true;
    LLMResponse? lastChunk;
    await for (final chunk in stream) {
      if (isFirstChunk) {
        setState(() {
          _isWaiting = false;
        });
        isFirstChunk = false;
      }
      if (_isCancelled) break;
      _currentResponse += chunk.content ?? '';
      if (_voiceConsoleActive && _currentResponse.trim().isNotEmpty) {
        _voiceConsoleOutput.value = _currentResponse.trim();
      }
      if (_messages.isNotEmpty) {
        var updatedMessage = _messages.last.copyWith(content: _currentResponse);
        if (chunk.toolCalls != null && chunk.toolCalls!.isNotEmpty) {
          updatedMessage = updatedMessage.copyWith(toolCalls: chunk.toolCalls!.map((tc) => tc.toJson()).toList());
        }
        _messages.last = updatedMessage;
      }

      // Feed through streaming filter → buffered summary speaker.
      // Speaker accumulates text and speaks at natural breakpoints.
      if (chunk.content != null && !_voiceConsoleActive) {
        final speechText = _speechFilter.feed(chunk.content!);
        if (speechText.isNotEmpty) {
          _bufferedSpeaker.feed(speechText);
        }
      }

      if (_debounce?.isActive ?? false) _debounce!.cancel();
      _debounce = Timer(const Duration(milliseconds: _chatPageDebounceTime), () {
        if (mounted) {
          setState(() {});
        }
      });
      lastChunk = chunk;
    }

    // Flush remaining text to TTS at end of stream
    if (!_voiceConsoleActive) {
      _bufferedSpeaker.flush();
    }

    // Voice Console mode: speak assistant output after text stream completes.
    if (_voiceConsoleActive && _shareChatToVoice.value) {
      final spoken = _sanitizeForVoice(_currentResponse);
      if (spoken.isNotEmpty) {
        _voiceConsoleOutput.value = spoken;
        if (ProviderManager.settingsProvider.generalSetting.voiceConsoleTtsEnabled) {
          Logger.root.info('VoiceConsole chat->voice speak dispatch: adapter=${_ttsAdapter.runtimeType}, chars=${spoken.length}');
          _ttsAdapter.speak(spoken);
        }
      }
    }

    if (lastChunk?.tokenUsage != null) {
      _messages.last = _messages.last.copyWith(tokenUsage: lastChunk?.tokenUsage);
    }

    _debounce?.cancel();
    if (mounted) {
      setState(() {});
    }

    _isCancelled = false;
  }

  Future<void> _pushLatestAssistantSummaryToMojo() async {
    final service = _mojoVoiceService;
    if (service == null) return;

    ChatMessage? latestAssistant;
    for (final message in _messages.reversed) {
      if (message.role != MessageRole.assistant) continue;
      final content = message.content?.trim() ?? '';
      if (content.isEmpty) continue;
      if (content.startsWith('<call_function_result')) continue;
      latestAssistant = message;
      break;
    }
    if (latestAssistant == null) return;
    if (_lastMojoPushedAssistantMessageId == latestAssistant.messageId) return;

    final rawContent = latestAssistant.content!.trim();
    if (rawContent.length < 40) return;

    String summary = _buildVoiceSummaryFallback(rawContent);
    try {
      final modelName = ProviderManager.chatModelProvider.currentModel.name;
      summary = await _summarizeForVoice(rawContent, modelName);
    } catch (e) {
      Logger.root.warning('MoJo summary generation failed, using fallback: $e');
    }

    final output = summary.trim();
    if (output.isEmpty) return;

    try {
      await service.ensureSession();
      _ensureMojoPollingActive();
      await service.pushResult(output, type: PushType.result);
      _lastMojoPushedAssistantMessageId = latestAssistant.messageId;
      Logger.root.info('MoJo summary pushed for assistant message: ${latestAssistant.messageId}');
    } catch (e) {
      Logger.root.warning('MoJo pushResult failed: $e');
    }
  }

  Future<String> _summarizeForVoice(String content, String modelName) async {
    if (_llmClient == null) return _buildVoiceSummaryFallback(content);

    final prompt =
        'Summarize the following assistant response for a speech engagement channel in 1-2 plain spoken sentences. '
        'No markdown, no bullets, no numbering, and no code fences. '
        'Do not include labels like "line 1", "step 1", or section headers. '
        'Focus on the key result and the next actionable point, then end with one concise clarifying question when helpful. '
        'Use second person ("you"), avoid third-person narration, and keep the output under 50 words. '
        'Return only the final spoken text, with no analysis or prefixed labels.\n\n$content';

    final stream = _llmClient!.chatStreamCompletion(
      CompletionRequest(
        model: modelName,
        messages: [
          ChatMessage(content: 'You generate concise spoken summaries for voice playback.', role: MessageRole.system),
          ChatMessage(content: prompt, role: MessageRole.user),
        ],
        modelSetting: ChatSetting(temperature: 0.2, maxTokens: 220, topP: 0.9),
      ),
    );

    final buffer = StringBuffer();
    await for (final chunk in stream) {
      if (chunk.content != null) {
        buffer.write(chunk.content);
      }
    }

    final summary = _sanitizeForVoice(buffer.toString());
    return summary.isNotEmpty ? summary : _buildVoiceSummaryFallback(content);
  }

  String _buildVoiceSummaryFallback(String content) {
    final cleaned = _sanitizeForVoice(content);
    if (cleaned.isEmpty) return '';
    if (cleaned.length <= 260) return cleaned;
    return '${cleaned.substring(0, 257)}...';
  }

  String _stripThinkingBlocks(String text) {
    var result = text;
    result = result.replaceAll(RegExp(r'<think[^>]*>(.|\n)*?</think\s*?>', dotAll: true), '');
    result = result.replaceAll(RegExp(r'<thought[^>]*>(.|\n)*?</thought\s*?>', dotAll: true), '');
    return result.trim();
  }

  /// Filter streaming content for display: suppresses thinking block content
  /// even before the closing tag arrives.
  String _filterForDisplay(String fullContent) {
    var result = fullContent;

    // First try to strip complete thinking blocks
    result = result.replaceAll(RegExp(r'<think[^>]*>(.|\n)*?</think\s*?>', dotAll: true), '');
    result = result.replaceAll(RegExp(r'<thought[^>]*>(.|\n)*?</thought\s*?>', dotAll: true), '');

    // If there's an unclosed <think or <thought tag, strip everything from it
    final openThink = RegExp(r'<think[^>]*>', caseSensitive: false);
    final openThought = RegExp(r'<thought[^>]*>', caseSensitive: false);

    for (final pattern in [openThink, openThought]) {
      final match = pattern.firstMatch(result);
      if (match != null) {
        result = result.substring(0, match.start).trim();
      }
    }

    return result.trim();
  }

  bool _isNonSpeechContent(String text) {
    final trimmed = text.trim();

    // Tool call / function XML
    if (trimmed.startsWith('<function ') || trimmed.startsWith('<call_function')) return true;
    if (trimmed.startsWith('<call_function_result')) return true;
    if (trimmed.startsWith('<tool_call')) return true;
    if (trimmed.startsWith('{') && trimmed.contains('"name"') && trimmed.contains('"arguments"')) return true;
    if (trimmed.startsWith('"type"') || trimmed.startsWith('"query"')) return true;

    // Task IDs and UUIDs
    if (RegExp(r'^sub_[a-f0-9_]+').hasMatch(trimmed)) return true;
    if (RegExp(r'^[A-F0-9]{8}-[A-F0-9]{4}-').hasMatch(trimmed)) return true;

    // JSON fragments
    if (trimmed.startsWith('{') && trimmed.endsWith('}') && trimmed.length < 200) return true;
    if (trimmed.startsWith('"') && trimmed.endsWith('"') && trimmed.contains(':')) return true;

    // Model reasoning / inner monologue patterns
    final reasoningPatterns = [
      r'^I should\b',
      r'^I need to\b',
      r'^I will\b',
      r'^I will\b',
      r'^I must\b',
      r'^Let me\b',
      r'^Actually[,.]',
      r'^Wait[,.]',
      r'^Now I\b',
      r'^The user\b',
      r'^I have\b',
      r'^I can\b',
      r'^I do not\b',
      r'^I see\b',
      r'^This is\b',
      r'^Based on\b',
      r'^According to\b',
      r'^The instruction',
      r'^I think\b',
      r'^I believe\b',
      r'^I understand\b',
      r'^OK[,.]',
      r'^So\b',
      r'^Well\b',
      r'^Hmm\b',
      r'^Done\.',
      r'^Output\.',
      r'^This is concise\.',
      r'^I will just\b',
      r'^I will output\b',
      r'^I will mention\b',
      r'^I will say\b',
      r'^Keeping it\b',
      r'^Keeping the\b',
      r'^Let us keep\b',
    ];
    for (final pattern in reasoningPatterns) {
      if (RegExp(pattern, caseSensitive: false).hasMatch(trimmed)) return true;
    }

    // Repeated "Hi." fragments (model echoing)
    if (trimmed == '"Hi."' || trimmed == 'Hi.' && text.length < 10) return true;

    return false;
  }

  String _sanitizeForVoice(String content) {
    final extracted = _extractQuotedSpokenText(content);
    if (extracted != null && extracted.isNotEmpty) {
      return extracted;
    }

    var text = content;
    // Remove reasoning/meta blocks that some models emit.
    text = text.replaceAll(RegExp(r'<thought\b[^>]*>[\s\S]*?</thought>', caseSensitive: false), ' ');
    text = text.replaceAll(RegExp(r'<think\b[^>]*>[\s\S]*?</think>', caseSensitive: false), ' ');
    // Remove any remaining XML-like tags.
    text = text.replaceAll(RegExp(r'</?[^>\n]+>'), ' ');
    // Remove prompt-construction scaffolding that should never be spoken.
    text = text.replaceAll(RegExp(r'^\s*Input\s*text\s*:.*$', caseSensitive: false, multiLine: true), ' ');
    text = text.replaceAll(RegExp(r'^\s*Context\s*:.*$', caseSensitive: false, multiLine: true), ' ');
    text = text.replaceAll(RegExp(r'^\s*Goal\s*:.*$', caseSensitive: false, multiLine: true), ' ');
    text = text.replaceAll(RegExp(r'^\s*Constraints\s*:.*$', caseSensitive: false, multiLine: true), ' ');
    text = text.replaceAll(RegExp(r'^\s*Result\s*:.*$', caseSensitive: false, multiLine: true), ' ');
    text = text.replaceAll(RegExp(r'^\s*Next\s*action\s*:.*$', caseSensitive: false, multiLine: true), ' ');
    text = text.replaceAll(RegExp(r'^\s*Clarifying\s*question\s*:.*$', caseSensitive: false, multiLine: true), ' ');
    text = text.replaceAll(RegExp(r'^\s*Option\s*\d+\s*:.*$', caseSensitive: false, multiLine: true), ' ');
    text = text.replaceAll(RegExp(r'```[\s\S]*?```'), ' ');
    text = text.replaceAll(RegExp(r'`[^`]*`'), ' ');
    text = text.replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '');
    text = text.replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '');
    text = text.replaceAll(RegExp(r'^\s*\d+[.)]\s+', multiLine: true), '');
    text = text.replaceAll(RegExp(r'^\s*line\s*\d+[:\-]?\s*', caseSensitive: false, multiLine: true), '');
    text = text.replaceAll(RegExp(r'\[(.*?)\]\((.*?)\)'), r'$1');
    text = text.replaceAll(RegExp(r'\s+'), ' ');
    return text.trim();
  }

  String? _extractQuotedSpokenText(String content) {
    final inputTextPattern = RegExp(r'Input\s*text\s*:\s*["“](.+?)["”]', caseSensitive: false, dotAll: true);
    final m = inputTextPattern.firstMatch(content);
    if (m != null) {
      return m.group(1)?.trim();
    }
    return null;
  }

  Future<void> _updateChat() async {
    if (ProviderManager.chatProvider.activeChat == null) {
      await _createNewChat();
    } else {
      await _updateExistingChat();
    }
  }

  Future<void> _createNewChat() async {
    if (_messages.isEmpty) return;

    String title;
    try {
      title = await _llmClient!.genTitle([if (_messages.isNotEmpty) _messages.first, if (_messages.length > 1) _messages.last else _messages.first]);
    } catch (e) {
      Logger.root.warning('Failed to generate title: $e');
      // Creates fallback title from user message if title generation fails
      final userMessage = _messages.isNotEmpty ? _messages.first.content ?? '' : '';
      title = _generateFallbackTitle(userMessage);
    }

    await ProviderManager.chatProvider.createChat(Chat(title: title), _handleParentMessageId(_messages));
    Logger.root.info('Created new chat: $title');
  }

  String _generateFallbackTitle(String userMessage) {
    if (userMessage.isEmpty) {
      return 'new chat';
    }

    // Creates title by truncating first 20 characters of user message
    String title = userMessage.replaceAll('\n', ' ').trim();
    if (title.length > 20) {
      title = '${title.substring(0, 17)}...';
    }

    return title.isEmpty ? 'new chat' : title;
  }

  // Handles parent message ID assignment for conversation thread
  List<ChatMessage> _handleParentMessageId(List<ChatMessage> messages) {
    if (messages.isEmpty) return [];

    // Locates the last user message to establish conversation thread
    int lastUserIndex = messages.lastIndexWhere((m) => m.role == MessageRole.user);
    if (lastUserIndex == -1) return messages;

    // Retrieves conversation thread starting from last user message
    List<ChatMessage> relevantMessages = messages.sublist(lastUserIndex);

    // Resets parent IDs for long threads to maintain proper conversation flow
    if (relevantMessages.length > 2) {
      String secondMessageId = relevantMessages[1].messageId;
      for (int i = 2; i < relevantMessages.length; i++) {
        relevantMessages[i] = relevantMessages[i].copyWith(parentMessageId: secondMessageId);
      }
    }

    return relevantMessages;
  }

  Future<void> _updateExistingChat() async {
    final activeChat = ProviderManager.chatProvider.activeChat!;
    await ProviderManager.chatProvider.updateChat(
      Chat(id: activeChat.id!, title: activeChat.title, createdAt: activeChat.createdAt, updatedAt: DateTime.now()),
    );

    await ProviderManager.chatProvider.addChatMessage(activeChat.id!, _handleParentMessageId(_messages));
  }

  void _handleError(dynamic error, StackTrace stackTrace) {
    Logger.root.severe('Error: $error');
    Logger.root.severe('Stack trace: $stackTrace');

    // Extracts detailed error information for debugging purposes
    if (error is TypeError) {
      Logger.root.severe('Type error: ${error.toString()}');
    }

    // Resets all state variables to their initial values
    _resetState();

    if (mounted) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.error_outline, color: AppColors.getErrorIconColor()),
                const SizedBox(width: 8),
                Text(AppLocalizations.of(context)!.error),
              ],
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _getUserFriendlyErrorMessage(error),
                    style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.getErrorTextColor()),
                  ),
                  const SizedBox(height: 8),
                  Text('error type: ${error.runtimeType}', style: TextStyle(fontSize: 12, color: AppColors.getErrorTextColor().withAlpha(128))),
                  if (error is LLMException)
                    Text(error.toString(), style: TextStyle(fontSize: 12, color: AppColors.getErrorTextColor().withAlpha(128))),
                ],
              ),
            ),
            actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(AppLocalizations.of(context)!.close))],
          );
        },
      );
    }
  }

  // Formats error messages for user display
  String _getUserFriendlyErrorMessage(dynamic error) {
    final errorMap = {
      'connection': AppLocalizations.of(context)!.networkError,
      'timeout': AppLocalizations.of(context)!.timeoutError,
      'permission': AppLocalizations.of(context)!.permissionError,
      'cancelled': AppLocalizations.of(context)!.userCancelledToolCall,
      'No element': AppLocalizations.of(context)!.noElementError,
      'not found': AppLocalizations.of(context)!.notFoundError,
      'invalid': AppLocalizations.of(context)!.invalidError,
      'unauthorized': AppLocalizations.of(context)!.unauthorizedError,
    };

    for (final entry in errorMap.entries) {
      if (error.toString().toLowerCase().contains(entry.key.toLowerCase())) {
        return entry.value;
      }
    }
    return AppLocalizations.of(context)!.unknownError;
  }

  // Handles chat export functionality
  Future<void> _handleShare(ShareEvent event) async {
    if (_messages.isEmpty) return;
    await Future.delayed(const Duration(milliseconds: 100));
    if (mounted) {
      if (kIsMobile) {
        Navigator.push(context, MaterialPageRoute(builder: (context) => ListViewToImageScreen(messages: _messages)));
      } else {
        showDialog(
          context: context,
          builder: (context) => ListViewToImageScreen(messages: _messages),
        );
      }
    }
  }

  bool _isMobile() {
    final height = MediaQuery.of(context).size.height;
    final width = MediaQuery.of(context).size.width;
    return height > width;
  }

  void _resetState() {
    setState(() {
      _isRunningFunction = false;
      _runFunctionEvents.clear();
      _isLoading = false;
      _isCancelled = false;
      _isWaiting = false;
      _currentLoop = 0;
    });
    // Auto focus input on desktop when state resets
    if (!kIsMobile) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _inputAreaKey.currentState?.requestFocus();
      });
    }
  }

  void _handleCancel() {
    _resetState();
    setState(() {
      _isCancelled = true;
    });
  }

  bool showModalCodePreview = false;
  void _showMobileCodePreview() {
    if (showModalCodePreview) {
      return;
    }
    setState(() {
      showModalCodePreview = true;
    });

    const txtNoCodePreview = Text('No code preview', style: TextStyle(fontSize: 14, color: Colors.grey));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: DraggableScrollableSheet(
            initialChildSize: 0.9,
            minChildSize: 0.3,
            maxChildSize: 0.9,
            expand: false,
            builder: (context, scrollController) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(color: AppColors.getBottomSheetHandleColor(context), borderRadius: BorderRadius.circular(2)),
                  ),
                  Expanded(
                    child: ProviderManager.chatProvider.artifactEvent != null
                        ? ChatCodePreview(codePreviewEvent: ProviderManager.chatProvider.artifactEvent!)
                        : Center(child: txtNoCodePreview),
                  ),
                ],
              );
            },
          ),
        );
      },
    ).whenComplete(() {
      setState(() {
        showModalCodePreview = false;
      });
      ProviderManager.chatProvider.clearArtifactEvent();
    });
  }

  Widget _buildFunctionRunning() {
    if (_isRunningFunction) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).primaryColor)),
            ),
            const SizedBox(width: 12),
            Text(
              AppLocalizations.of(context)!.functionRunning,
              style: TextStyle(fontSize: 14, color: Theme.of(context).textTheme.bodyMedium?.color?.withAlpha((0.7 * 255).round())),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    if (mobile) {
      return Column(
        children: [
          _buildMessageList(),
          _buildFunctionRunning(),
          InputArea(
            key: _inputAreaKey,
            disabled: _isLoading,
            isComposing: _isComposing,
            onTextChanged: _handleTextChanged,
            onSubmitted: _handleSubmitted,
            onPdfPageSubmitted: _handlePdfPageSubmitted,
            onTestImageSilent: _handleTestImageSilent,
            onCancel: _handleCancel,
            onMojoVoiceStart: _onMojoVoiceStart,
            onMojoVoiceStop: _onMojoVoiceStop,
            onMojoVoiceCancel: _onMojoVoiceCancel,
            onOpenVoiceConsole: _openVoiceConsole,
            mojoVoiceEnabled: _mojoVoiceService != null,
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          flex: 1,
          child: Column(
            children: [
              _buildMessageList(),
              _buildFunctionRunning(),
              InputArea(
                key: _inputAreaKey,
                disabled: _isLoading,
                isComposing: _isComposing,
                onTextChanged: _handleTextChanged,
                onSubmitted: _handleSubmitted,
                onPdfPageSubmitted: _handlePdfPageSubmitted,
                onTestImageSilent: _handleTestImageSilent,
                onCancel: _handleCancel,
                onMojoVoiceStart: _onMojoVoiceStart,
                onMojoVoiceStop: _onMojoVoiceStop,
                onMojoVoiceCancel: _onMojoVoiceCancel,
                onOpenVoiceConsole: _openVoiceConsole,
                mojoVoiceEnabled: _mojoVoiceService != null,
              ),
            ],
          ),
        ),
        if (!mobile && _showCodePreview && ProviderManager.chatProvider.artifactEvent != null)
          Expanded(flex: 2, child: ChatCodePreview(codePreviewEvent: ProviderManager.chatProvider.artifactEvent!)),
      ],
    );
  }
}
