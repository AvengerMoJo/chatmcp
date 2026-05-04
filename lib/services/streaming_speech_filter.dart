/// Strips thinking blocks, function calls, and tool XML from streaming LLM output.
/// Only passes through clean speech text suitable for TTS.
class StreamingSpeechFilter {
  final StringBuffer _buffer = StringBuffer();
  bool _inThink = false;
  bool _inFunction = false;
  bool _inCallFunctionResult = false;
  bool _inCallFunction = false;

  /// Feed a streaming chunk and get back only speech-worthy text.
  String feed(String chunk) {
    _buffer.write(chunk);
    final raw = _buffer.toString();
    final output = StringBuffer();
    int i = 0;

    while (i < raw.length) {
      if (!_inAnyBlock) {
        // Look for opening tags
        final tag = _findNextOpenTag(raw, i);
        if (tag != null && tag.offset == i) {
          _enterTag(tag.tag);
          i = tag.endIndex;
          continue;
        }

        if (tag != null) {
          // Output text up to the tag
          output.write(raw.substring(i, tag.offset));
          i = tag.offset;
        } else {
          // No more tags, output rest but keep tail for incomplete tags
          final safeEnd = _safeOutputEnd(raw, i);
          if (safeEnd > i) {
            output.write(raw.substring(i, safeEnd));
          }
          // Keep potential incomplete tag in buffer
          _buffer.clear();
          if (safeEnd < raw.length) {
            _buffer.write(raw.substring(safeEnd));
          }
          return output.toString();
        }
      } else {
        // Inside a block, look for closing tag
        final closeIdx = _findCloseTag(raw, i);
        if (closeIdx != null) {
          i = closeIdx;
          _exitBlock();
        } else {
          // Still inside, keep buffer tail
          _buffer.clear();
          final tailLen = 20; // Keep enough for incomplete close tag
          if (raw.length > tailLen) {
            _buffer.write(raw.substring(raw.length - tailLen));
          }
          return output.toString();
        }
      }
    }

    _buffer.clear();
    return output.toString();
  }

  void reset() {
    _buffer.clear();
    _inThink = false;
    _inFunction = false;
    _inCallFunctionResult = false;
    _inCallFunction = false;
  }

  bool get _inAnyBlock => _inThink || _inFunction || _inCallFunctionResult || _inCallFunction;

  void _enterTag(String tag) {
    if (tag == 'think' || tag == 'thought') _inThink = true;
    else if (tag == 'function') _inFunction = true;
    else if (tag == 'call_function_result') _inCallFunctionResult = true;
    else if (tag == 'call_function') _inCallFunction = true;
  }

  void _exitBlock() {
    _inThink = false;
    _inFunction = false;
    _inCallFunctionResult = false;
    _inCallFunction = false;
  }

  _TagMatch? _findNextOpenTag(String s, int from) {
    _TagMatch? best;
    for (final tag in ['think', 'thought', 'function', 'call_function_result', 'call_function']) {
      final openPattern = '<$tag';
      final idx = s.indexOf(openPattern, from);
      if (idx == -1) continue;
      final closeAngle = s.indexOf('>', idx + openPattern.length);
      if (closeAngle == -1) continue; // Incomplete tag
      final match = _TagMatch(tag, idx, closeAngle + 1);
      if (best == null || match.offset < best.offset) {
        best = match;
      }
    }
    return best;
  }

  int? _findCloseTag(String s, int from) {
    String tag;
    if (_inThink) tag = 'think';
    else if (_inFunction) tag = 'function';
    else if (_inCallFunctionResult) tag = 'call_function_result';
    else tag = 'call_function';

    final closePattern = '</$tag>';
    final idx = s.indexOf(closePattern, from);
    if (idx == -1) return null;
    return idx + closePattern.length;
  }

  /// Find a safe cut point that doesn't split a potential opening tag.
  int _safeOutputEnd(String s, int from) {
    // Don't cut if we're potentially inside a tag opening
    for (int j = s.length - 1; j >= from && j >= s.length - 30; j--) {
      if (s[j] == '<') return j;
    }
    return s.length;
  }
}

class _TagMatch {
  final String tag;
  final int offset;
  final int endIndex;
  _TagMatch(this.tag, this.offset, this.endIndex);
}
