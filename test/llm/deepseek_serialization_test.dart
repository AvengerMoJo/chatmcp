import 'package:chatmcp/llm/deepseek_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('extractReasoningContent', () {
    test('extracts reasoning from think tags into separate field', () {
      final messages = [
        {'role': 'user', 'content': 'hi'},
        {'role': 'assistant', 'content': '<think start-time="...">thinking here</think end-time="...">\nactual response'},
      ];
      extractReasoningContent(messages);
      expect(messages[1]['reasoning_content'], 'thinking here');
      expect(messages[1]['content'], 'actual response');
    });

    test('removes content when only thinking and tool_calls exist', () {
      final messages = [
        {'role': 'user', 'content': 'hi'},
        {'role': 'assistant', 'content': '<think start-time="...">reasoning</think end-time="...">', 'tool_calls': [{'id': 'c1'}]},
      ];
      extractReasoningContent(messages);
      expect(messages[1]['reasoning_content'], 'reasoning');
      expect(messages[1].containsKey('content'), isFalse);
    });

    test('no change when no think tags present', () {
      final messages = [
        {'role': 'user', 'content': 'hi'},
        {'role': 'assistant', 'content': 'just a response'},
      ];
      extractReasoningContent(messages);
      expect(messages[1].containsKey('reasoning_content'), isFalse);
      expect(messages[1]['content'], 'just a response');
    });

    test('skips non-assistant messages with think tags', () {
      final messages = [
        {'role': 'user', 'content': '<think start-time="...">thinking</think end-time="...">'},
      ];
      extractReasoningContent(messages);
      expect(messages[0].containsKey('reasoning_content'), isFalse);
    });

    test('skips null content (tool_calls-only messages)', () {
      final messages = [
        {'role': 'assistant', 'content': null, 'tool_calls': [{'id': 'c1'}]},
      ];
      extractReasoningContent(messages);
      expect(messages[0].containsKey('reasoning_content'), isFalse);
    });

    test('handles multiple think blocks', () {
      final messages = [
        {'role': 'assistant', 'content': '<think start-time="...">first</think end-time="...">\nmiddle\n<think start-time="...">second</think end-time="...">\nresponse'},
      ];
      extractReasoningContent(messages);
      expect(messages[0]['reasoning_content'], 'first\nsecond');
      expect(messages[0]['content'], 'middle\n\nresponse');
    });

    test('handles multiline reasoning content', () {
      final messages = [
        {'role': 'assistant', 'content': '<think start-time="...">\nLine 1\nLine 2\nLine 3\n</think end-time="...">\nresponse text'},
      ];
      extractReasoningContent(messages);
      expect(messages[0]['reasoning_content'], 'Line 1\nLine 2\nLine 3');
      expect(messages[0]['content'], 'response text');
    });

    test('sets empty string content when only thinking no tool_calls', () {
      final messages = [
        {'role': 'assistant', 'content': '<think start-time="...">reasoning</think end-time="...">'},
      ];
      extractReasoningContent(messages);
      expect(messages[0]['reasoning_content'], 'reasoning');
      expect(messages[0]['content'], '');
    });
  });
}
