import 'dart:async';
import 'package:logging/logging.dart';
import 'package:chatmcp/services/tts_adapter.dart';
import 'package:chatmcp/services/voice_response_extractor.dart';

/// Accumulates clean speech text from LLM stream and speaks complete
/// sentences at natural breakpoints. Avoids choppy fragments and
/// giant unbroken blobs.
class BufferedSummarySpeaker {
  final TtsAdapter ttsAdapter;
  final VoiceResponseExtractor _extractor = VoiceResponseExtractor();
  final Logger _log = Logger.root;
  final StringBuffer _buffer = StringBuffer();
  int _spokenCount = 0;

  /// Minimum words before we consider speaking a sentence.
  final int minWords;

  /// Maximum words in buffer before force-speaking (prevents giant blobs).
  final int maxBufferWords;

  BufferedSummarySpeaker({
    required this.ttsAdapter,
    this.minWords = 5,
    this.maxBufferWords = 100,
  });

  /// Feed clean text from the streaming filter. May trigger TTS.
  void feed(String text) {
    if (text.isEmpty) return;
    _buffer.write(text);
    _trySpeak();
  }

  /// Call when stream ends. Flushes any remaining text.
  void flush() {
    final remaining = _buffer.toString().trim();
    _buffer.clear();
    if (remaining.isNotEmpty && remaining.split(RegExp(r'\s+')).length >= 3) {
      _speak(remaining);
    }
  }

  /// Reset state (e.g., on new message).
  void reset() {
    _buffer.clear();
    _spokenCount = 0;
  }

  int get spokenCount => _spokenCount;

  void _trySpeak() {
    final text = _buffer.toString().trim();
    if (text.isEmpty) return;

    final wordCount = text.split(RegExp(r'\s+')).length;

    // Find the last sentence boundary
    final boundary = _findLastSentenceBoundary(text);

    if (boundary != null) {
      final sentence = text.substring(0, boundary).trim();
      final remaining = text.substring(boundary).trim();
      final sentenceWords = sentence.split(RegExp(r'\s+')).length;

      if (sentenceWords >= minWords) {
        _speak(sentence);
        _buffer.clear();
        if (remaining.isNotEmpty) {
          _buffer.write(remaining);
        }
        return;
      }
    }

    // Force speak if buffer is too large (prevents giant blobs)
    if (wordCount >= maxBufferWords) {
      // Find the best break point (last comma or semicolon)
      final softBreak = _findLastSoftBreak(text);
      if (softBreak != null && softBreak > text.length ~/ 3) {
        _speak(text.substring(0, softBreak).trim());
        _buffer.clear();
        _buffer.write(text.substring(softBreak).trim());
      } else {
        _speak(text);
        _buffer.clear();
      }
    }
  }

  /// Find the last sentence boundary (. ? ! and CJK equivalents).
  /// Returns the index AFTER the boundary character.
  int? _findLastSentenceBoundary(String text) {
    // Match sentence-ending punctuation followed by space or end
    final pattern = RegExp(r'[.!?。？！]\s+');
    int lastEnd = -1;
    for (final match in pattern.allMatches(text)) {
      lastEnd = match.end;
    }
    // Also check if text ends with sentence punctuation
    if (lastEnd == -1 && RegExp(r'[.!?。？！]$').hasMatch(text)) {
      lastEnd = text.length;
    }
    return lastEnd > 0 ? lastEnd : null;
  }

  /// Find last soft break point (comma, semicolon, or em dash).
  int? _findLastSoftBreak(String text) {
    int lastBreak = -1;
    for (final char in [',', ';', '—', '，', '；']) {
      final idx = text.lastIndexOf(char);
      if (idx > lastBreak) lastBreak = idx;
    }
    return lastBreak > 0 ? lastBreak + 1 : null;
  }

  void _speak(String text) {
    final cleaned = _extractor.extract(text).trim();
    if (cleaned.length < 3) return;
    _log.info('BufferedSpeaker speak (${cleaned.split(RegExp(r"\s+")).length}w): "${cleaned.length > 80 ? '${cleaned.substring(0, 80)}...' : cleaned}"');
    ttsAdapter.speak(cleaned);
    _spokenCount++;
  }
}
