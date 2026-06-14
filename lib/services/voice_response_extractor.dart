import 'package:chatmcp/utils/think_tags.dart';

class VoiceResponseExtractor {
  static final VoiceResponseExtractor _instance = VoiceResponseExtractor._internal();
  factory VoiceResponseExtractor() => _instance;
  VoiceResponseExtractor._internal();

  String extract(String raw) {
    if (raw.isEmpty) return '';

    var text = raw;

    // Remove reasoning / thinking / function / tool blocks via the shared helpers.
    text = stripProtocolBlocks(text);

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
}
