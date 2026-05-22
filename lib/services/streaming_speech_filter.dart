/// Strips thinking blocks, function calls, and tool XML from streaming LLM output.
/// Only passes through clean speech text suitable for TTS.
class StreamingSpeechFilter {
  final StringBuffer _buffer = StringBuffer();
  bool _inThink = false;
  bool _inFunction = false;
  bool _inCallFunctionResult = false;
  bool _inCallFunction = false;
  bool _inPipeToolCall = false; // <|tool_call>...</tool_call|>
  bool _inJsonToolCall = false; // <tool_call>{...}</tool_call> (no attributes)

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
          final tailLen = 30;
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
    _inPipeToolCall = false;
    _inJsonToolCall = false;
  }

  bool get _inAnyBlock =>
      _inThink || _inFunction || _inCallFunctionResult || _inCallFunction || _inPipeToolCall || _inJsonToolCall;

  void _enterTag(String tag) {
    if (tag == 'think' || tag == 'thought')
      _inThink = true;
    else if (tag == 'function')
      _inFunction = true;
    else if (tag == 'call_function_result')
      _inCallFunctionResult = true;
    else if (tag == 'call_function')
      _inCallFunction = true;
    else if (tag == '|tool_call' || tag == '|function_call')
      _inPipeToolCall = true;
    else if (tag == 'tool_call_json' || tag == 'tool_call_body')
      _inJsonToolCall = true;
  }

  void _exitBlock() {
    _inThink = false;
    _inFunction = false;
    _inCallFunctionResult = false;
    _inCallFunction = false;
    _inPipeToolCall = false;
    _inJsonToolCall = false;
  }

  _TagMatch? _findNextOpenTag(String s, int from) {
    _TagMatch? best;

    // Standard XML-style open tags: <tagname ...>
    for (final tag in ['think', 'thought', 'function', 'call_function_result', 'call_function']) {
      final openPattern = '<$tag';
      final idx = s.indexOf(openPattern, from);
      if (idx == -1) continue;
      final closeAngle = s.indexOf('>', idx + openPattern.length);
      if (closeAngle == -1) continue;
      final match = _TagMatch(tag, idx, closeAngle + 1);
      if (best == null || match.offset < best.offset) best = match;
    }

    // Pipe-bracket open tags: <|tool_call> or <|function_call>
    for (final tag in ['|tool_call', '|function_call']) {
      final openPattern = '<$tag>';
      final idx = s.indexOf(openPattern, from);
      if (idx == -1) continue;
      final match = _TagMatch(tag, idx, idx + openPattern.length);
      if (best == null || match.offset < best.offset) best = match;
    }

    // Plain <tool_call> with no attributes (JSON body format) — distinguish from
    // attribute-style by checking that the char after <tool_call is '>' not ' ' or '='
    for (final plain in ['tool_call', 'function_call']) {
      final openPattern = '<$plain>';
      final idx = s.indexOf(openPattern, from);
      if (idx == -1) continue;
      final syntheticTag = '${plain}_body';
      final match = _TagMatch(syntheticTag, idx, idx + openPattern.length);
      if (best == null || match.offset < best.offset) best = match;
    }

    return best;
  }

  int? _findCloseTag(String s, int from) {
    String closePattern;
    if (_inThink) {
      closePattern = '</think>';
    } else if (_inFunction) {
      closePattern = '</function>';
    } else if (_inCallFunctionResult) {
      closePattern = '</call_function_result>';
    } else if (_inCallFunction) {
      closePattern = '</call_function>';
    } else if (_inPipeToolCall) {
      // Closing is <tool_call|> or <function_call|>
      final a = s.indexOf('<tool_call|>', from);
      final b = s.indexOf('<function_call|>', from);
      int? idx;
      if (a != -1 && (b == -1 || a < b)) {
        idx = a + '<tool_call|>'.length;
      } else if (b != -1) {
        idx = b + '<function_call|>'.length;
      }
      return idx;
    } else if (_inJsonToolCall) {
      // Match both possible closing tags for JSON body format
      final a = s.indexOf('</tool_call>', from);
      final b = s.indexOf('</function_call>', from);
      int? idx;
      if (a != -1 && (b == -1 || a < b)) {
        idx = a + '</tool_call>'.length;
      } else if (b != -1) {
        idx = b + '</function_call>'.length;
      }
      return idx;
    } else {
      return null;
    }

    final idx = s.indexOf(closePattern, from);
    if (idx == -1) return null;
    return idx + closePattern.length;
  }

  /// Find a safe cut point that doesn't split a potential opening tag.
  int _safeOutputEnd(String s, int from) {
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
