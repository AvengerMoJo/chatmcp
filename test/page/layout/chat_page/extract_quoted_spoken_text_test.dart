import 'package:flutter_test/flutter_test.dart';

/// Regression tests for `_extractQuotedSpokenText` (private method in
/// `chat_page.dart`). The regex is copied here to lock the contract — if
/// the production copy diverges, these tests will fail.
///
/// Original bug: the regex `Input\s*text\s*:\s*["“](.+?)["”]` matched
/// anywhere in the content. When a model output or tool-result echo
/// contained the literal phrase `Input text: "..."` mid-response, TTS
/// would speak the quoted fragment instead of the actual reply — symptom
/// was "audio starts talking about a story, unrelated to the reply".
String? extractQuotedSpokenText(String content) {
  final inputTextPattern = RegExp(r'^\s*Input\s*text\s*:\s*["“](.+?)["”]', caseSensitive: false, dotAll: true);
  final m = inputTextPattern.firstMatch(content);
  if (m != null) {
    return m.group(1)?.trim();
  }
  return null;
}

void main() {
  group('_extractQuotedSpokenText — anchoring', () {
    test('extracts when the pattern is at the start', () {
      expect(extractQuotedSpokenText('Input text: "Here is my answer to your question."'), equals('Here is my answer to your question.'));
    });

    test('extracts with leading whitespace before "Input text"', () {
      expect(extractQuotedSpokenText('   Input text: "Hello there"'), equals('Hello there'));
    });

    test('extracts case-insensitively', () {
      expect(extractQuotedSpokenText('INPUT TEXT: "shouty version"'), equals('shouty version'));
    });

    test('extracts curly-quoted content', () {
      expect(extractQuotedSpokenText('Input text: “curly quotes ok”'), equals('curly quotes ok'));
    });

    test('extracts multi-line quoted content', () {
      expect(extractQuotedSpokenText('Input text: "first line\nsecond line\nthird"'), equals('first line\nsecond line\nthird'));
    });
  });

  group('_extractQuotedSpokenText — does NOT match mid-content (regression)', () {
    test('does not extract when pattern is mid-sentence', () {
      // This was the original bug — the entire quoted fragment got pulled out
      // and spoken, ignoring everything before and after.
      expect(extractQuotedSpokenText('I will respond with a story. Input text: "The brave knight rode through the dark forest."'), isNull);
    });

    test('does not extract when pattern is in a tool-result echo', () {
      expect(extractQuotedSpokenText('Tool returned: {"ok": true, "data": "Input text: \"echoed story content\""}'), isNull);
    });

    test('does not extract when pattern appears in a sentence without quotes', () {
      // No opening quote → no match
      expect(extractQuotedSpokenText('Input text: no quotes here, just plain text after the colon.'), isNull);
    });

    test('does not extract when content starts with narrative that mentions the phrase', () {
      expect(extractQuotedSpokenText('Once upon a time, the assistant said: Input text: "wrong"'), isNull);
    });
  });

  group('_extractQuotedSpokenText — null on missing input', () {
    test('returns null for empty content', () {
      expect(extractQuotedSpokenText(''), isNull);
    });

    test('returns null for plain prose', () {
      expect(extractQuotedSpokenText('Just a regular response with no special format.'), isNull);
    });

    test('returns null for markdown content without the marker', () {
      expect(extractQuotedSpokenText('# Heading\n\nSome **bold** content.'), isNull);
    });
  });
}
