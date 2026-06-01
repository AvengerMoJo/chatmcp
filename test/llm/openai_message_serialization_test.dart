import 'package:chatmcp/llm/model.dart';
import 'package:chatmcp/llm/openai_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('chatMessageToOpenAIMessage', () {
    test('skips UI-only roles', () {
      final input = [
        ChatMessage(role: MessageRole.user, content: 'hi'),
        ChatMessage(role: MessageRole.loading, content: ''),
        ChatMessage(role: MessageRole.error, content: 'err'),
      ];
      final out = chatMessageToOpenAIMessage(input);
      expect(out.length, 1);
      expect(out.first['role'], 'user');
      expect(out.first['content'], 'hi');
    });

    test('drops malformed tool message without tool_call_id', () {
      final input = [ChatMessage(role: MessageRole.tool, name: 'get_context', content: '{}')];
      final out = chatMessageToOpenAIMessage(input);
      expect(out, isEmpty);
    });

    test('keeps protocol-correct assistant tool call + tool result turn', () {
      final input = [
        ChatMessage(role: MessageRole.system, content: 'system'),
        ChatMessage(role: MessageRole.user, content: 'who am i'),
        ChatMessage(
          role: MessageRole.assistant,
          content: '',
          toolCalls: [
            {
              'id': 'call_ctx_1',
              'type': 'function',
              'function': {'name': 'get_context', 'arguments': '{"type":"orientation"}'},
            },
          ],
        ),
        ChatMessage(role: MessageRole.tool, name: 'get_context', toolCallId: 'call_ctx_1', content: '{"timestamp":"2026-05-07T00:02:40"}'),
      ];

      final out = chatMessageToOpenAIMessage(input);
      expect(out.length, 4);
      expect(out[2]['role'], 'assistant');
      expect((out[2]['tool_calls'] as List).length, 1);
      expect(out[3]['role'], 'tool');
      expect(out[3]['tool_call_id'], 'call_ctx_1');
    });

    test('assistant message with toolCalls but empty content sends content=null (not "")', () {
      final input = [
        ChatMessage(role: MessageRole.user, content: 'hi'),
        ChatMessage(
          role: MessageRole.assistant,
          content: '',
          toolCalls: [
            {'id': 'c1', 'type': 'function', 'function': {'name': 'get_context', 'arguments': '{}'}},
          ],
        ),
      ];

      final out = chatMessageToOpenAIMessage(input);
      expect(out.length, 2);
      expect(out[1]['role'], 'assistant');
      expect(out[1]['content'], isNull);
      expect(out[1]['tool_calls'], isNotNull);
    });

    test('tool_calls without type:function gets type normalized', () {
      final input = [
        ChatMessage(role: MessageRole.user, content: 'hi'),
        ChatMessage(
          role: MessageRole.assistant,
          content: 'done',
          toolCalls: [
            {'id': 'c1', 'function': {'name': 'get_context', 'arguments': '{}'}},
          ],
        ),
      ];

      final out = chatMessageToOpenAIMessage(input);
      final tc = (out[1]['tool_calls'] as List).first;
      expect(tc['type'], 'function');
    });

    test('merges consecutive assistant messages: tool_calls + content-only', () {
      final input = [
        ChatMessage(role: MessageRole.user, content: 'status'),
        ChatMessage(
          role: MessageRole.assistant,
          content: '',
          toolCalls: [
            {'id': 'c1', 'type': 'function', 'function': {'name': 'get_context', 'arguments': '{}'}},
          ],
        ),
        ChatMessage(role: MessageRole.assistant, content: 'Here is the status:'),
        ChatMessage(role: MessageRole.tool, name: 'get_context', toolCallId: 'c1', content: '{"ok":true}'),
      ];

      final out = chatMessageToOpenAIMessage(input);
      expect(out.length, 3);
      expect(out[1]['role'], 'assistant');
      expect(out[1]['content'], 'Here is the status:');
      expect((out[1]['tool_calls'] as List).length, 1);
      expect(out[2]['role'], 'tool');
    });

    test('merges consecutive assistant messages: both with tool_calls', () {
      final input = [
        ChatMessage(role: MessageRole.user, content: 'go'),
        ChatMessage(
          role: MessageRole.assistant,
          content: '',
          toolCalls: [
            {'id': 'c1', 'type': 'function', 'function': {'name': 'get_context', 'arguments': '{}'}},
          ],
        ),
        ChatMessage(
          role: MessageRole.assistant,
          content: '',
          toolCalls: [
            {'id': 'c2', 'type': 'function', 'function': {'name': 'search_memory', 'arguments': '{"q":"test"}'}},
          ],
        ),
      ];

      final out = chatMessageToOpenAIMessage(input);
      expect(out.length, 2);
      expect(out[1]['role'], 'assistant');
      expect((out[1]['tool_calls'] as List).length, 2);
      expect(out[1]['content'], isNull);
    });

    test('merges consecutive assistant messages: both with content', () {
      final input = [
        ChatMessage(role: MessageRole.user, content: 'hi'),
        ChatMessage(role: MessageRole.assistant, content: 'Part 1'),
        ChatMessage(role: MessageRole.assistant, content: 'Part 2'),
      ];

      final out = chatMessageToOpenAIMessage(input);
      expect(out.length, 2);
      expect(out[1]['role'], 'assistant');
      expect(out[1]['content'], 'Part 1\n\nPart 2');
    });

    test('merges consecutive assistant messages: tool_calls with content + text-only', () {
      final input = [
        ChatMessage(role: MessageRole.user, content: 'status'),
        ChatMessage(
          role: MessageRole.assistant,
          content: 'Let me check.',
          toolCalls: [
            {'id': 'c1', 'type': 'function', 'function': {'name': 'get_context', 'arguments': '{"type":"orientation"}'}},
          ],
        ),
        ChatMessage(role: MessageRole.assistant, content: 'All systems operational.'),
      ];

      final out = chatMessageToOpenAIMessage(input);
      expect(out.length, 2);
      expect(out[1]['role'], 'assistant');
      expect(out[1]['content'], 'Let me check.\n\nAll systems operational.');
      expect((out[1]['tool_calls'] as List).length, 1);
    });

    test('does not merge non-consecutive assistant messages', () {
      final input = [
        ChatMessage(role: MessageRole.user, content: 'go'),
        ChatMessage(
          role: MessageRole.assistant,
          content: '',
          toolCalls: [
            {'id': 'c1', 'type': 'function', 'function': {'name': 'get_context', 'arguments': '{}'}},
          ],
        ),
        ChatMessage(role: MessageRole.tool, name: 'get_context', toolCallId: 'c1', content: '{"ok":true}'),
        ChatMessage(role: MessageRole.assistant, content: 'Done'),
      ];

      final out = chatMessageToOpenAIMessage(input);
      expect(out.length, 4);
      expect(out[1]['role'], 'assistant');
      expect(out[2]['role'], 'tool');
      expect(out[3]['role'], 'assistant');
      expect(out[3]['content'], 'Done');
    });
  });
}