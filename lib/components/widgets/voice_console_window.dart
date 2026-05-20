import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'package:chatmcp/services/voice_classifier.dart';
import 'package:chatmcp/services/voice_response_extractor.dart';
import 'package:chatmcp/services/tts_adapter.dart';

class VoiceConsoleApp extends StatelessWidget {
  final int windowId;
  const VoiceConsoleApp({super.key, required this.windowId});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Voice Console',
      theme: ThemeData(useMaterial3: true, brightness: Brightness.light),
      darkTheme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      themeMode: ThemeMode.system,
      home: VoiceConsolePage(windowId: windowId),
    );
  }
}

class VoiceConsolePage extends StatefulWidget {
  final int windowId;
  const VoiceConsolePage({super.key, required this.windowId});

  @override
  State<VoiceConsolePage> createState() => _VoiceConsolePageState();
}

class _VoiceConsolePageState extends State<VoiceConsolePage> {
  // STT
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechReady = false;
  bool _isListening = false;
  List<stt.LocaleName> _availableLocales = [];
  stt.LocaleName? _selectedLocale;

  // Recording
  final AudioRecorder _recorder = AudioRecorder();
  String? _recordingPath;
  bool _isRecording = false;

  // TTS
  TtsAdapter _ttsAdapter = NoOpTtsAdapter();
  final AudioPlayer _player = AudioPlayer();

  // Classifier
  final VoiceClassifier _classifier = VoiceClassifier();
  final VoiceResponseExtractor _extractor = VoiceResponseExtractor();

  // State
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _outputScrollController = ScrollController();
  String _outputText = '';
  String _stateLabel = 'idle';
  bool _isProcessing = false;

  // Communication with main window
  late WindowMethodChannel _mainChannel;

  // Settings from main window
  String _ttsProvider = 'none';
  String _ttsApiKey = '';
  String _ttsEndpoint = '';
  String _ttsModel = '';
  String _ttsVoice = '';
  String _llmApiKey = '';
  String _llmEndpoint = '';
  String _llmModel = '';

  @override
  void initState() {
    super.initState();
    _initWindow();
    _initSpeech();
    _initRecorder();
  }

  Future<void> _initWindow() async {
    // Set up communication channel with main window
    _mainChannel = const WindowMethodChannel('voice_console_channel');
    _mainChannel.setMethodCallHandler(_handleMainMessage);

    // Request settings from main window
    try {
      final settings = await _mainChannel.invokeMethod('getSettings');
      if (settings is Map) {
        _ttsProvider = settings['ttsProvider'] ?? 'none';
        _ttsApiKey = settings['ttsApiKey'] ?? '';
        _ttsEndpoint = settings['ttsEndpoint'] ?? '';
        _ttsModel = settings['ttsModel'] ?? '';
        _ttsVoice = settings['ttsVoice'] ?? '';
        _llmApiKey = settings['llmApiKey'] ?? '';
        _llmEndpoint = settings['llmEndpoint'] ?? '';
        _llmModel = settings['llmModel'] ?? '';
        _initTts();
      }
    } catch (e) {
      Logger.root.warning('Failed to get settings from main window: $e');
    }
  }

  Future<dynamic> _handleMainMessage(MethodCall call) async {
    switch (call.method) {
      case 'updateSettings':
        final settings = call.arguments as Map;
        setState(() {
          _ttsProvider = settings['ttsProvider'] ?? _ttsProvider;
          _ttsApiKey = settings['ttsApiKey'] ?? _ttsApiKey;
          _ttsEndpoint = settings['ttsEndpoint'] ?? _ttsEndpoint;
          _ttsModel = settings['ttsModel'] ?? _ttsModel;
          _ttsVoice = settings['ttsVoice'] ?? _ttsVoice;
          _llmApiKey = settings['llmApiKey'] ?? _llmApiKey;
          _llmEndpoint = settings['llmEndpoint'] ?? _llmEndpoint;
          _llmModel = settings['llmModel'] ?? _llmModel;
        });
        _initTts();
        return 'ok';
      default:
        throw MissingPluginException('Not implemented: ${call.method}');
    }
  }

  void _initTts() {
    _ttsAdapter.dispose();
    if (_ttsProvider == 'mimo' && _ttsApiKey.isNotEmpty) {
      _ttsAdapter = MiMoTtsAdapter(
        apiKey: _ttsApiKey,
        baseUrl: _ttsEndpoint,
        model: _ttsModel.isNotEmpty ? _ttsModel : 'mimo-v2.5-tts',
        voice: _ttsVoice.isNotEmpty ? _ttsVoice : 'mimo_default',
      );
    } else if (_ttsProvider == 'openai' && _ttsApiKey.isNotEmpty) {
      _ttsAdapter = OpenAITtsAdapter(
        apiKey: _ttsApiKey,
        baseUrl: _ttsEndpoint,
        model: _ttsModel.isNotEmpty ? _ttsModel : 'tts-1',
        voice: _ttsVoice.isNotEmpty ? _ttsVoice : 'alloy',
      );
    } else {
      _ttsAdapter = NoOpTtsAdapter();
    }
  }

  Future<void> _initSpeech() async {
    final ready = await _speech.initialize(
      onError: (_) => setState(() => _isListening = false),
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          setState(() => _isListening = false);
        }
      },
    );
    if (!mounted) return;
    if (ready) {
      _availableLocales = await _speech.locales();
      _selectedLocale = _availableLocales.firstWhere(
        (l) => l.localeId.toLowerCase().startsWith('en'),
        orElse: () => _availableLocales.isNotEmpty ? _availableLocales.first : stt.LocaleName('en_US', 'English'),
      );
    }
    setState(() => _speechReady = ready);
  }

  Future<void> _initRecorder() async {
    // Just check permission
    await _recorder.hasPermission();
  }

  void _appendOutput(String text) {
    setState(() {
      _outputText = _outputText.isEmpty ? text : '$_outputText\n$text';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_outputScrollController.hasClients) {
        _outputScrollController.jumpTo(_outputScrollController.position.maxScrollExtent);
      }
    });
  }

  Future<void> _toggleListening() async {
    if (!_speechReady) return;
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      return;
    }
    setState(() => _isListening = true);
    await _speech.listen(
      localeId: _selectedLocale?.localeId,
      onResult: (result) {
        _inputController.text = result.recognizedWords;
        _inputController.selection = TextSelection.fromPosition(TextPosition(offset: _inputController.text.length));
        if (result.finalResult) {
          _handleSubmit(result.recognizedWords);
        }
      },
    );
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      // Stop recording and process
      final path = await _recorder.stop();
      setState(() => _isRecording = false);
      final filePath = path ?? _recordingPath;
      _recordingPath = null;
      if (filePath != null) {
        _appendOutput('[Audio recorded, processing...]');
        // For now, just notify main window. Full S2S would need server integration.
        _sendToMain('audioRecorded', {'path': filePath});
      }
    } else {
      if (!await _recorder.hasPermission()) {
        _appendOutput('[Microphone permission denied]');
        return;
      }
      final tempDir = await getTemporaryDirectory();
      _recordingPath = '${tempDir.path}/voice_rec_${DateTime.now().millisecondsSinceEpoch}.wav';
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1), path: _recordingPath!);
      setState(() => _isRecording = true);
      _appendOutput('[Recording...]');
    }
  }

  Future<void> _handleSubmit(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isProcessing) return;

    setState(() => _isProcessing = true);
    _appendOutput('You: $trimmed');

    // 1. Classify for instant response
    final result = _classifier.classify(trimmed);
    _appendOutput('Assistant: ${result.immediateResponse}');
    if (_ttsAdapter is! NoOpTtsAdapter) {
      _ttsAdapter.speak(result.immediateResponse);
    }

    // 2. For greetings/acks, done
    if (result.inputClass == VoiceInputClass.greeting || result.inputClass == VoiceInputClass.ack) {
      setState(() => _isProcessing = false);
      _sendToMain('voiceInput', {'text': trimmed, 'class': result.inputClass.name});
      return;
    }

    // 3. For questions/statements, process in background
    _setStateLabel('processing');
    _sendToMain('voiceInput', {'text': trimmed, 'class': result.inputClass.name});

    try {
      final llmResponse = await _callLlm(trimmed);
      final cleaned = _extractor.extract(llmResponse);

      if (cleaned.isNotEmpty) {
        _appendOutput('Assistant: $cleaned');
        if (_ttsAdapter is! NoOpTtsAdapter) {
          _ttsAdapter.speak(cleaned);
        }
      }

      _sendToMain('voiceResponse', {'raw': llmResponse, 'cleaned': cleaned});
    } catch (e) {
      _appendOutput('[Error: $e]');
    } finally {
      setState(() {
        _isProcessing = false;
        _stateLabel = 'idle';
      });
    }
  }

  Future<String> _callLlm(String text) async {
    if (_llmApiKey.isEmpty) return '[No LLM API key configured]';

    final url = _llmEndpoint.isNotEmpty ? '$_llmEndpoint/chat/completions' : 'https://api.openai.com/v1/chat/completions';
    final model = _llmModel.isNotEmpty ? _llmModel : 'gpt-4o-mini';

    final response = await http
        .post(
          Uri.parse(url),
          headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $_llmApiKey'},
          body: jsonEncode({
            'model': model,
            'messages': [
              {
                'role': 'system',
                'content': 'You are a voice assistant. Keep responses under 50 words. Use natural spoken language. No markdown, no code blocks.',
              },
              {'role': 'user', 'content': text},
            ],
            'max_tokens': 200,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      return '[LLM error: ${response.statusCode}]';
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = data['choices'] as List?;
    if (choices == null || choices.isEmpty) return '[No response]';
    return choices[0]['message']['content'] as String? ?? '[Empty response]';
  }

  void _sendToMain(String method, dynamic arguments) {
    try {
      _mainChannel.invokeMethod(method, arguments);
    } catch (e) {
      Logger.root.warning('Failed to send to main window: $e');
    }
  }

  void _setStateLabel(String label) {
    setState(() => _stateLabel = label);
  }

  @override
  void dispose() {
    _speech.stop();
    _recorder.dispose();
    _ttsAdapter.dispose();
    _player.dispose();
    _inputController.dispose();
    _outputScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(CupertinoIcons.waveform, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('Voice Console', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _isProcessing ? Colors.orange.withAlpha(30) : Colors.green.withAlpha(30),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_stateLabel, style: TextStyle(fontSize: 11, color: _isProcessing ? Colors.orange : Colors.green)),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Input
              TextField(
                controller: _inputController,
                maxLines: 2,
                minLines: 1,
                decoration: InputDecoration(
                  hintText: 'Speak or type...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  isDense: true,
                ),
                onSubmitted: _handleSubmit,
              ),
              const SizedBox(height: 8),

              // Buttons
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: _speechReady ? _toggleListening : null,
                    icon: Icon(_isListening ? CupertinoIcons.stop_circle : CupertinoIcons.mic),
                    label: Text(_isListening ? 'Stop' : 'Speak'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: _toggleRecording,
                    icon: Icon(_isRecording ? CupertinoIcons.stop_fill : CupertinoIcons.waveform_circle_fill),
                    label: Text(_isRecording ? 'Send' : 'Record'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _isProcessing ? null : () => _handleSubmit(_inputController.text),
                    icon: _isProcessing
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(CupertinoIcons.paperplane_fill),
                    label: const Text('Send'),
                  ),
                  if (_speechReady && _availableLocales.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    PopupMenuButton<stt.LocaleName>(
                      tooltip: 'Input language',
                      icon: const Icon(CupertinoIcons.globe, size: 20),
                      onSelected: (locale) => setState(() => _selectedLocale = locale),
                      itemBuilder: (context) => _availableLocales.map((locale) => PopupMenuItem(value: locale, child: Text(locale.name))).toList(),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),

              // Output
              Text(
                'Output',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).colorScheme.outline.withAlpha(120)),
                    borderRadius: BorderRadius.circular(8),
                    color: Theme.of(context).colorScheme.surface,
                  ),
                  child: SingleChildScrollView(
                    controller: _outputScrollController,
                    reverse: true,
                    child: Text(
                      _outputText.isEmpty ? 'Waiting for input...' : _outputText,
                      style: TextStyle(
                        fontSize: 13,
                        color: _outputText.isEmpty ? Theme.of(context).colorScheme.onSurface.withAlpha(100) : Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
