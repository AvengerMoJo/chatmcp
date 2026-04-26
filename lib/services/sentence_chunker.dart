class SentenceChunker {
  final StringBuffer _buffer = StringBuffer();
  final RegExp _sentenceEnd = RegExp(r'[.?!。！？\n]');
  final int maxBufferLength;

  SentenceChunker({this.maxBufferLength = 200});

  void append(String chunk) {
    _buffer.write(chunk);
  }

  /// Extracts complete sentences from the buffer.
  /// Returns a list of sentences ready for TTS.
  List<String> flushSentences() {
    final text = _buffer.toString();
    if (text.isEmpty) return [];

    final sentences = <String>[];
    int lastEnd = 0;

    for (final match in _sentenceEnd.allMatches(text)) {
      final end = match.start + 1;
      final sentence = text.substring(lastEnd, end).trim();
      if (sentence.isNotEmpty && sentence.length > 1) {
        sentences.add(sentence);
      }
      lastEnd = end;
    }

    // Keep remaining text in buffer
    final remaining = text.substring(lastEnd);
    _buffer.clear();
    if (remaining.trim().isNotEmpty) {
      // If buffer is getting too long, flush it anyway (force sentence break)
      if (remaining.length > maxBufferLength) {
        sentences.add(remaining.trim());
      } else {
        _buffer.write(remaining);
      }
    }

    return sentences;
  }

  /// Flushes everything remaining in the buffer, even without sentence end.
  String flushRemaining() {
    final text = _buffer.toString().trim();
    _buffer.clear();
    return text;
  }

  void clear() {
    _buffer.clear();
  }
}
