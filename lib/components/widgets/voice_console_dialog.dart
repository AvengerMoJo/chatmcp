import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class VoiceConsoleDialog extends StatefulWidget {
  final Future<void> Function(String text) onSubmitText;
  final Future<void> Function()? onStartAudioTurn;
  final Future<void> Function()? onFinishAudioTurn;
  final bool speechToSpeechEnabled;
  final ValueListenable<String> assistantOutput;
  final ValueListenable<String> preferredLanguage;
  final ValueListenable<bool> shareVoiceToChat;
  final ValueListenable<bool> shareChatToVoice;
  final ValueChanged<String> onPreferredLanguageChanged;
  final ValueChanged<bool> onShareVoiceToChatChanged;
  final ValueChanged<bool> onShareChatToVoiceChanged;

  const VoiceConsoleDialog({
    super.key,
    required this.onSubmitText,
    this.onStartAudioTurn,
    this.onFinishAudioTurn,
    this.speechToSpeechEnabled = false,
    required this.assistantOutput,
    required this.preferredLanguage,
    required this.shareVoiceToChat,
    required this.shareChatToVoice,
    required this.onPreferredLanguageChanged,
    required this.onShareVoiceToChatChanged,
    required this.onShareChatToVoiceChanged,
  });

  @override
  State<VoiceConsoleDialog> createState() => _VoiceConsoleDialogState();
}

class _VoiceConsoleDialogState extends State<VoiceConsoleDialog> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final TextEditingController _inputController = TextEditingController();
  bool _speechReady = false;
  bool _isListening = false;
  bool _isRecordingAudioTurn = false;
  bool _isSending = false;
  List<stt.LocaleName> _availableLocales = [];
  stt.LocaleName? _selectedLocale;

  @override
  void initState() {
    super.initState();
    _initSpeech();
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
      },
    );
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isSending) return;
    setState(() => _isSending = true);
    try {
      await widget.onSubmitText(text);
      _inputController.clear();
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _toggleAudioTurn() async {
    if (_isSending) return;
    setState(() => _isSending = true);
    try {
      if (_isRecordingAudioTurn) {
        await widget.onFinishAudioTurn?.call();
      } else {
        await widget.onStartAudioTurn?.call();
      }
      if (mounted) {
        setState(() => _isRecordingAudioTurn = !_isRecordingAudioTurn);
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  void dispose() {
    _speech.stop();
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Voice Console'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _inputController,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(labelText: 'Voice/Text Input', hintText: 'Speak or type, then send'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _speechReady ? _toggleListening : null,
                  icon: Icon(_isListening ? CupertinoIcons.stop_circle : CupertinoIcons.mic),
                  label: Text(_isListening ? 'Stop' : 'Speak'),
                ),
                if (widget.speechToSpeechEnabled) ...[
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _isSending ? null : _toggleAudioTurn,
                    icon: Icon(_isRecordingAudioTurn ? CupertinoIcons.stop_fill : CupertinoIcons.waveform_circle_fill),
                    label: Text(_isRecordingAudioTurn ? 'Send Turn' : 'Talk (S2S)'),
                  ),
                ],
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _isSending ? null : _send,
                  icon: _isSending
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(CupertinoIcons.paperplane_fill),
                  label: const Text('Send'),
                ),
                if (_speechReady && _availableLocales.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  PopupMenuButton<stt.LocaleName>(
                    tooltip: 'Input language',
                    icon: const Icon(CupertinoIcons.globe),
                    onSelected: (locale) => setState(() => _selectedLocale = locale),
                    itemBuilder: (context) => _availableLocales.map((locale) => PopupMenuItem(value: locale, child: Text(locale.name))).toList(),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            ValueListenableBuilder<String>(
              valueListenable: widget.preferredLanguage,
              builder: (context, value, _) => DropdownButtonFormField<String>(
                value: value,
                decoration: const InputDecoration(labelText: 'Reply language', isDense: true),
                items: const [
                  DropdownMenuItem(value: 'auto', child: Text('Auto')),
                  DropdownMenuItem(value: 'en', child: Text('English')),
                  DropdownMenuItem(value: 'zh', child: Text('Chinese')),
                  DropdownMenuItem(value: 'ja', child: Text('Japanese')),
                  DropdownMenuItem(value: 'ko', child: Text('Korean')),
                ],
                onChanged: (v) {
                  if (v != null) widget.onPreferredLanguageChanged(v);
                },
              ),
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<bool>(
              valueListenable: widget.shareVoiceToChat,
              builder: (context, value, _) => SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Share voice context to chat'),
                value: value,
                onChanged: widget.onShareVoiceToChatChanged,
              ),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: widget.shareChatToVoice,
              builder: (context, value, _) => SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Use chat context in voice thread'),
                value: value,
                onChanged: widget.onShareChatToVoiceChanged,
              ),
            ),
            const SizedBox(height: 8),
            const Text('Assistant Voice Output', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 72),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).colorScheme.outline.withAlpha(120)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ValueListenableBuilder<String>(
                valueListenable: widget.assistantOutput,
                builder: (context, value, _) => Text(value.isEmpty ? 'Waiting for assistant output...' : value),
              ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
    );
  }
}
