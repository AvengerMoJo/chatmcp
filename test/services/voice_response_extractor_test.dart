import 'package:chatmcp/services/voice_response_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final extractor = VoiceResponseExtractor();

  group('VoiceResponseExtractor.extract', () {
    test('returns empty for empty input', () {
      expect(extractor.extract(''), '');
    });

    test('passes plain text through', () {
      const input = 'The weather is sunny today.';
      expect(extractor.extract(input), input);
    });

    test('strips <think> blocks', () {
      // Answer must be longer than 5 chars to avoid the short-result fallback
      const input = '<think>internal reasoning</think>The capital of France is Paris.';
      final out = extractor.extract(input);
      expect(out, isNot(contains('internal reasoning')));
      expect(out, contains('Paris'));
    });

    test('strips <thought> blocks', () {
      const input = '<thought>let me consider</thought>Done.';
      final out = extractor.extract(input);
      expect(out, isNot(contains('let me consider')));
      expect(out, contains('Done'));
    });

    test('strips <function> blocks', () {
      const input = '<function name="search">{"q":"foo"}</function>Result found.';
      final out = extractor.extract(input);
      expect(out, isNot(contains('"q":"foo"')));
      expect(out, contains('Result'));
    });

    test('strips <call_function_result> blocks', () {
      const input = 'Here is: <call_function_result name="x">data</call_function_result> done.';
      final out = extractor.extract(input);
      expect(out, isNot(contains('data')));
    });

    test('strips markdown code blocks', () {
      const input = 'Here is code:\n```dart\nvoid main() {}\n```\nDone.';
      final out = extractor.extract(input);
      expect(out, isNot(contains('void main')));
      expect(out, contains('Done'));
    });

    test('strips inline code', () {
      const input = 'Call `print("hello")` to output.';
      final out = extractor.extract(input);
      expect(out, isNot(contains('`print')));
    });

    test('strips markdown bold', () {
      const input = 'This is **important** text.';
      final out = extractor.extract(input);
      expect(out, isNot(contains('**')));
      expect(out, contains('important'));
    });

    test('strips markdown italic', () {
      const input = 'This is *emphasized* text.';
      final out = extractor.extract(input);
      expect(out, isNot(contains('*emphasized*')));
      expect(out, contains('emphasized'));
    });

    test('strips markdown headers', () {
      const input = '## Section Title\nSome content here.';
      final out = extractor.extract(input);
      expect(out, isNot(contains('##')));
      expect(out, contains('Section Title'));
    });

    test('strips bullet list markers', () {
      const input = '- Item one\n- Item two';
      final out = extractor.extract(input);
      expect(out, isNot(contains('- ')));
      expect(out, contains('Item one'));
    });

    test('strips numbered list markers', () {
      const input = '1. First\n2. Second';
      final out = extractor.extract(input);
      expect(out, isNot(startsWith('1.')));
      expect(out, contains('First'));
    });

    test('strips URLs', () {
      const input = 'Visit https://example.com for more.';
      final out = extractor.extract(input);
      expect(out, isNot(contains('https://')));
    });

    test('strips meta-commentary prefix "Here is"', () {
      const input = 'Here is your answer: 42.';
      final out = extractor.extract(input);
      expect(out, isNot(startsWith('Here is')));
    });

    test('strips meta-commentary prefix "Sure,"', () {
      const input = 'Sure, let me help. The answer is 7.';
      final out = extractor.extract(input);
      expect(out, isNot(startsWith('Sure,')));
    });

    test('falls back to raw if extraction strips too much', () {
      // Short but meaningful raw text that gets over-stripped
      const input = 'OK.'; // Very short, should return something
      final out = extractor.extract(input);
      expect(out, isNotEmpty);
    });

    test('handles combined think + clean answer', () {
      // Long enough answer (>5 chars) so the short-result fallback is not triggered
      const input = '<think>Let me reason step by step...</think>The capital of France is Paris, a beautiful city.';
      final out = extractor.extract(input);
      expect(out, isNot(contains('reason step')));
      expect(out, contains('Paris'));
    });

    test('strips markdown links but keeps link text', () {
      const input = 'See [the docs](https://docs.example.com) for details.';
      final out = extractor.extract(input);
      expect(out, contains('the docs'));
      expect(out, isNot(contains('https://')));
    });
  });
}
