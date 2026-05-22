import 'package:chatmcp/services/sentence_chunker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SentenceChunker', () {
    late SentenceChunker chunker;

    setUp(() {
      chunker = SentenceChunker();
    });

    test('returns empty when no sentence enders yet', () {
      chunker.append('Hello there');
      expect(chunker.flushSentences(), isEmpty);
    });

    test('flushes sentence ending with period', () {
      chunker.append('Hello world.');
      final sentences = chunker.flushSentences();
      expect(sentences.length, 1);
      expect(sentences[0], 'Hello world.');
    });

    test('flushes sentence ending with question mark', () {
      chunker.append('How are you?');
      final sentences = chunker.flushSentences();
      expect(sentences, contains('How are you?'));
    });

    test('flushes sentence ending with exclamation', () {
      chunker.append('Great!');
      final sentences = chunker.flushSentences();
      expect(sentences, contains('Great!'));
    });

    test('flushes multiple sentences', () {
      chunker.append('Hello. How are you? Fine!');
      final sentences = chunker.flushSentences();
      expect(sentences.length, 3);
    });

    test('keeps partial sentence in buffer', () {
      chunker.append('Hello. This is partial');
      final sentences = chunker.flushSentences();
      expect(sentences.length, 1);
      expect(sentences[0], 'Hello.');
      // Partial text should still be in buffer
      final remaining = chunker.flushRemaining();
      expect(remaining, contains('partial'));
    });

    test('flushRemaining returns leftover text', () {
      chunker.append('Incomplete sentence');
      expect(chunker.flushRemaining(), 'Incomplete sentence');
    });

    test('flushRemaining clears buffer', () {
      chunker.append('Some text');
      chunker.flushRemaining();
      expect(chunker.flushRemaining(), '');
    });

    test('force-flushes when buffer exceeds maxBufferLength', () {
      final chunkerSmall = SentenceChunker(maxBufferLength: 20);
      chunkerSmall.append('A' * 25); // 25 chars, exceeds 20
      final sentences = chunkerSmall.flushSentences();
      expect(sentences, isNotEmpty);
    });

    test('handles Chinese sentence enders', () {
      chunker.append('你好吗。很好！');
      final sentences = chunker.flushSentences();
      expect(sentences.length, 2);
    });

    test('clear empties buffer', () {
      chunker.append('Hello world.');
      chunker.clear();
      expect(chunker.flushSentences(), isEmpty);
      expect(chunker.flushRemaining(), isEmpty);
    });

    test('handles streaming word by word', () {
      // Simulate streaming chunks
      for (final word in ['The', ' answer', ' is', ' 42.']) {
        chunker.append(word);
      }
      final sentences = chunker.flushSentences();
      expect(sentences.length, 1);
      expect(sentences[0], 'The answer is 42.');
    });
  });
}
