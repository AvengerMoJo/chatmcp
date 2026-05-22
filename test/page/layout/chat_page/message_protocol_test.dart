import 'package:chatmcp/llm/model.dart';
import 'package:chatmcp/page/layout/chat_page/message_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MessageProtocol.prepareForLlm', () {
    test('drops loading/error and empty assistant placeholder', () {
      final input = [
        ChatMessage(role: MessageRole.user, content: 'hi'),
        ChatMessage(role: MessageRole.loading, content: ''),
        ChatMessage(role: MessageRole.error, content: 'err'),
        ChatMessage(role: MessageRole.assistant, content: '   '),
      ];

      final out = MessageProtocol.prepareForLlm(input);
      expect(out.length, 1);
      expect(out.first.role, MessageRole.user);
      expect(out.first.content, 'hi');
    });

    test('keeps assistant message with toolCalls even when content is empty', () {
      final input = [
        ChatMessage(role: MessageRole.user, content: 'hi'),
        ChatMessage(
          role: MessageRole.assistant,
          content: '',
          toolCalls: [
            {
              'id': 'call_1',
              'type': 'function',
              'function': {'name': 'get_context', 'arguments': '{}'},
            },
          ],
        ),
      ];

      final out = MessageProtocol.prepareForLlm(input);
      expect(out.length, 2);
      expect(out[1].role, MessageRole.assistant);
      expect(out[1].toolCalls, isNotNull);
      expect(out[1].toolCalls!.length, 1);
    });

    test('reorders tool reply before paired user message', () {
      final user = ChatMessage(role: MessageRole.user, content: 'question');
      final tool = ChatMessage(role: MessageRole.tool, content: '{}', toolCallId: 'call_1', name: 'get_context');
      final out = MessageProtocol.prepareForLlm([user, tool]);
      expect(out[0].role, MessageRole.tool);
      expect(out[1].role, MessageRole.user);
    });

    test('truncates oversized tool payloads before LLM serialization', () {
      final huge = 'x' * 90510;
      final out = MessageProtocol.prepareForLlm([ChatMessage(role: MessageRole.tool, content: huge, toolCallId: 'call_1', name: 'big_tool_result')]);
      expect(out.length, 1);
      expect(out.first.role, MessageRole.tool);
      expect(out.first.content!.length, lessThan(20000));
      expect(out.first.content, contains('[... omitted'));
    });
  });

  group('MessageProtocol.mergeForContext', () {
    test('does not merge assistant text with call_function_result xml', () {
      final input = [
        ChatMessage(role: MessageRole.user, content: 'who am i'),
        ChatMessage(role: MessageRole.assistant, content: 'I will check.'),
        ChatMessage(role: MessageRole.assistant, content: '<call_function_result name="get_context">{"timestamp":"x"}</call_function_result>'),
      ];

      final out = MessageProtocol.mergeForContext(input);
      expect(out.length, 4);
      expect(out[0].role, MessageRole.user);
      expect(out[1].role, MessageRole.assistant);
      expect(out[2].role, MessageRole.assistant);
      expect(out[3].role, MessageRole.user);
      expect(out[3].content, 'continue');
    });

    test('merges adjacent plain assistant text', () {
      final input = [
        ChatMessage(role: MessageRole.user, content: 'hi'),
        ChatMessage(role: MessageRole.assistant, content: 'hello'),
        ChatMessage(role: MessageRole.assistant, content: 'how can I help?'),
      ];
      final out = MessageProtocol.mergeForContext(input);
      expect(out.length, 3);
      expect(out[1].content, 'hello\n\nhow can I help?');
      expect(out[2].role, MessageRole.user);
      expect(out[2].content, 'continue');
    });

    test('does NOT add continue message after tool result', () {
      final input = [
        ChatMessage(role: MessageRole.user, content: 'hi'),
        ChatMessage(role: MessageRole.assistant, content: '', toolCalls: [
          {'id': 'c1', 'type': 'function', 'function': {'name': 'get_context', 'arguments': '{}'}},
        ]),
        ChatMessage(role: MessageRole.tool, name: 'get_context', toolCallId: 'c1', content: '{"result":"ok"}'),
      ];
      final out = MessageProtocol.mergeForContext(input);
      expect(out.last.role, MessageRole.tool);
      expect(out.last.content, '{"result":"ok"}');
      final hasContinueAfterTool = out.length > 1 && out.last.role == MessageRole.user && out.last.content == 'continue';
      expect(hasContinueAfterTool, isFalse, reason: 'should not add continue after tool result');
    });

    test('adds continue only after assistant message, not after user or tool', () {
      final input = [
        ChatMessage(role: MessageRole.user, content: 'hi'),
        ChatMessage(role: MessageRole.assistant, content: 'hello'),
      ];
      final out = MessageProtocol.mergeForContext(input);
      expect(out.last.role, MessageRole.user);
      expect(out.last.content, 'continue');
    });
  });
}