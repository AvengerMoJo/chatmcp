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
  });
}
