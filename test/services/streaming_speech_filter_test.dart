import 'package:chatmcp/services/streaming_speech_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StreamingSpeechFilter', () {
    late StreamingSpeechFilter filter;

    setUp(() {
      filter = StreamingSpeechFilter();
    });

    test('passes plain text through unchanged', () {
      final out = filter.feed('Hello, how can I help you?');
      expect(out, 'Hello, how can I help you?');
    });

    test('strips complete <think> block', () {
      final out = filter.feed('Before<think>internal thoughts</think>After');
      expect(out, contains('Before'));
      expect(out, contains('After'));
      expect(out, isNot(contains('internal thoughts')));
    });

    test('strips complete <thought> block', () {
      final out = filter.feed('Hi<thought>reasoning here</thought> there');
      expect(out, isNot(contains('reasoning here')));
      expect(out, contains('Hi'));
    });

    test('strips complete <function> block', () {
      final out = filter.feed('Answer: <function name="tool">{"a":1}</function> done');
      expect(out, isNot(contains('{"a":1}')));
    });

    test('strips <call_function_result> block', () {
      final out = filter.feed('Result: <call_function_result>data</call_function_result> ok');
      expect(out, isNot(contains('data')));
    });

    test('handles streaming across multiple feeds', () {
      filter.feed('Hello ');
      filter.feed('<think>');
      filter.feed('thinking...');
      final out = filter.feed('</think> world');
      // "thinking..." should be stripped, "world" (and possibly "Hello") should pass
      expect(out, isNot(contains('thinking...')));
    });

    test('strips <think start-time="..."> with attributed closing tag', () {
      final out = filter.feed('Before<think start-time="2026-06-04T16:13:44.585915">reasoning here</think end-time="2026-06-04T16:13:46.123456">After');
      expect(out, isNot(contains('reasoning here')));
      expect(out, isNot(contains('start-time')));
      expect(out, isNot(contains('end-time')));
      expect(out, contains('Before'));
      expect(out, contains('After'));
    });

    test('strips <think...> across streaming chunks with attributes', () {
      filter.feed('Hello <think');
      filter.feed(' start-time="t1">secret');
      filter.feed('</think');
      final out = filter.feed(' end-time="t2"> world');
      expect(out, isNot(contains('secret')));
      expect(out, isNot(contains('start-time')));
      expect(out, isNot(contains('end-time')));
    });

    test('reset clears state', () {
      filter.feed('<think>still open');
      filter.reset();
      final out = filter.feed('clean text');
      expect(out, contains('clean'));
    });

    test('plain text with no tags returns text', () {
      final out = filter.feed('The answer is 42.');
      expect(out, contains('42'));
    });

    test('multiple plain feeds accumulate correctly', () {
      final a = filter.feed('Hello');
      final b = filter.feed(' world');
      expect(a + b, contains('Hello'));
      expect(a + b, contains('world'));
    });
  });
}
