import 'package:chatmcp/utils/think_tags.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('thinkBlockRegex', () {
    test('matches bare <think>…</think>', () {
      final m = thinkBlockRegex.firstMatch('hello <think>r</think> world');
      expect(m, isNotNull);
      expect(m!.start, 6);
      // <think>r</think> is 16 chars
      expect(m.end, 22);
    });

    test('matches attribute-bearing open and close tags', () {
      const input = '<think start-time="1">r</think end-time="2">';
      final m = thinkBlockRegex.firstMatch(input);
      expect(m, isNotNull);
    });

    test('matches multiple blocks in a string', () {
      const input = '<think>a</think> middle <think>b</think>';
      expect(thinkBlockRegex.allMatches(input).length, 2);
    });

    test('does not match unclosed', () {
      expect(thinkBlockRegex.hasMatch('<think>nope'), isFalse);
    });
  });

  group('stripThinkBlocks', () {
    test('replaces think and thought blocks with single space', () {
      const input = 'a<think>x</think>b<thought>y</thought>c';
      expect(stripThinkBlocks(input), 'a b c');
    });

    test('keeps non-think content intact', () {
      const input = 'no think here';
      expect(stripThinkBlocks(input), 'no think here');
    });
  });

  group('stripProtocolBlocks', () {
    test('removes think, function, and call_function_result blocks', () {
      const input = 'before <think>x</think> mid <function>y</function> after <call_function_result>z</call_function_result> end';
      final out = stripProtocolBlocks(input);
      expect(out.contains('<think'), isFalse);
      expect(out.contains('<function'), isFalse);
      expect(out.contains('<call_function_result'), isFalse);
      expect(out.contains('before'), isTrue);
      expect(out.contains('after'), isTrue);
    });

    test('leaves plain text alone', () {
      const input = 'just words';
      expect(stripProtocolBlocks(input), 'just words');
    });
  });
}
