class VoiceResponseExtractor {
  static final VoiceResponseExtractor _instance = VoiceResponseExtractor._internal();
  factory VoiceResponseExtractor() => _instance;
  VoiceResponseExtractor._internal();

  String extract(String raw) {
    if (raw.isEmpty) return '';

    var text = raw;

    // Remove reasoning / thinking blocks
    text = _stripTag(text, 'thought');
    text = _stripTag(text, 'think');
    text = _stripTag(text, 'reasoning');

    // Remove function / tool call blocks
    text = _stripTag(text, 'function');
    text = _stripTag(text, 'tool_call');
    text = text.replaceAll(RegExp(r'<call_function_result[^>]*>[\s\S]*?</call_function_result>'), ' ');

    // Remove code blocks
    text = text.replaceAll(RegExp(r'```[\s\S]*?```'), ' ');
    text = text.replaceAll(RegExp(r'`[^`\n]+`'), ' ');

    // Remove XML-style tags that models emit for structured output
    text = text.replaceAll(RegExp(r'</?[^>\n]{1,40}>'), ' ');

    // Remove markdown formatting
    text = text.replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '');
    text = text.replaceAllMapped(RegExp(r'\*\*([^*]+)\*\*'), (m) => m.group(1) ?? '');
    text = text.replaceAllMapped(RegExp(r'\*([^*]+)\*'), (m) => m.group(1) ?? '');
    text = text.replaceAllMapped(RegExp(r'__([^_]+)__'), (m) => m.group(1) ?? '');
    text = text.replaceAllMapped(RegExp(r'_([^_]+)_'), (m) => m.group(1) ?? '');
    text = text.replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '');
    text = text.replaceAll(RegExp(r'^\s*\d+\.\s+', multiLine: true), '');
    text = text.replaceAllMapped(RegExp(r'\[([^\]]*)\]\([^)]*\)'), (m) => m.group(1) ?? '');

    // Remove URL noise
    text = text.replaceAll(RegExp(r'https?://\S+'), '');

    // Remove meta-commentary prefixes
    text = text.replaceAll(RegExp(r'^\s*(Here is|Here are|The answer is|Sure[,!]?|Certainly[,!]?)\s*', caseSensitive: false), '');

    // Clean up whitespace
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    text = text.replaceAll(RegExp(r' {2,}'), ' ');
    text = text.trim();

    // If extraction stripped everything, fall back to raw
    if (text.length < 5 && raw.length > 10) {
      return raw.trim();
    }

    return text;
  }

  String _stripTag(String text, String tag) {
    final pattern = RegExp('<$tag[^>]*>[\\s\\S]*?</$tag>', caseSensitive: false);
    return text.replaceAll(pattern, ' ');
  }
}
