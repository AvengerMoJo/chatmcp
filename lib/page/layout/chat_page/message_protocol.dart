import 'package:chatmcp/llm/model.dart';

class MessageProtocol {
  static List<ChatMessage> prepareForLlm(List<ChatMessage> messages) {
    final messageList = messages
        .where((m) {
          if (m.role == MessageRole.loading || m.role == MessageRole.error) return false;
          if (m.role == MessageRole.assistant && (m.content == null || m.content!.trim().isEmpty)) return false;
          return true;
        })
        .map(
          (m) => ChatMessage(
            role: m.role,
            content: m.content,
            toolCallId: m.toolCallId,
            name: m.name,
            toolCalls: null,
            files: m.files,
          ),
        )
        .toList();

    reorderForToolReplies(messageList);
    return messageList;
  }

  static List<ChatMessage> mergeForContext(List<ChatMessage> messageList) {
    if (messageList.isEmpty) return [];

    final newMessages = [messageList.first];
    for (final message in messageList.sublist(1)) {
      final last = newMessages.last;
      final lastContent = last.content ?? '';
      final currentContent = message.content ?? '';
      final hasToolXml = lastContent.contains('<function') ||
          lastContent.contains('<call_function_result') ||
          currentContent.contains('<function') ||
          currentContent.contains('<call_function_result');

      if (last.role == message.role && !hasToolXml) {
        final content = message.content ?? '';
        newMessages.last = last.copyWith(content: '${last.content}\n\n$content');
      } else {
        newMessages.add(message);
      }
    }

    if (newMessages.isNotEmpty && newMessages.last.role != MessageRole.user) {
      newMessages.add(ChatMessage(content: 'continue', role: MessageRole.user));
    }

    return newMessages;
  }

  static void reorderForToolReplies(List<ChatMessage> messageList) {
    for (int i = 0; i < messageList.length - 1; i++) {
      if (messageList[i].role == MessageRole.user && messageList[i + 1].role == MessageRole.tool) {
        final temp = messageList[i];
        messageList[i] = messageList[i + 1];
        messageList[i + 1] = temp;
        i++;
      }
    }
  }
}

