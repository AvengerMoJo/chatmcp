import 'package:chatmcp/llm/model.dart';

class MessageProtocol {
  static const int _maxToolContentChars = 12000;
  static const int _maxNonToolContentChars = 24000;

  static List<ChatMessage> prepareForLlm(List<ChatMessage> messages) {
    final messageList = messages
        .where((m) {
          if (m.role == MessageRole.loading || m.role == MessageRole.error) return false;
          if (m.role == MessageRole.assistant && (m.content == null || m.content!.trim().isEmpty) && (m.toolCalls == null || m.toolCalls!.isEmpty)) return false;
          return true;
        })
        .map((m) {
          final normalizedContent = _normalizeContentForLlm(m.role, m.content);
          return ChatMessage(role: m.role, content: normalizedContent, toolCallId: m.toolCallId, name: m.name, toolCalls: m.toolCalls, files: m.files);
        })
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
      final hasToolXml =
          lastContent.contains('<function') ||
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

    if (newMessages.isNotEmpty && newMessages.last.role == MessageRole.assistant) {
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

  static String? _normalizeContentForLlm(MessageRole role, String? content) {
    if (content == null) return null;
    final trimmed = content.trim();
    if (trimmed.isEmpty) return trimmed;

    final maxChars = role == MessageRole.tool ? _maxToolContentChars : _maxNonToolContentChars;
    if (trimmed.length <= maxChars) return trimmed;

    final head = trimmed.substring(0, maxChars ~/ 2);
    final tail = trimmed.substring(trimmed.length - (maxChars ~/ 2));
    final omitted = trimmed.length - maxChars;
    return '$head\n\n[... omitted $omitted chars due to context limit ...]\n\n$tail';
  }
}
