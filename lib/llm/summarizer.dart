import 'model.dart';
import 'context_manager.dart';

class ConversationSummary {
  final String summary;
  final int originalMessageCount;
  final int originalTokenCount;
  final int summaryTokenCount;

  const ConversationSummary({
    required this.summary,
    required this.originalMessageCount,
    required this.originalTokenCount,
    required this.summaryTokenCount,
  });

  int get tokensSaved => originalTokenCount - summaryTokenCount;
}

class ConversationSummarizer {
  static String _buildSummaryPrompt(List<ChatMessage> messages) {
    final buffer = StringBuffer();
    buffer.writeln('You are a conversation summarizer. Summarize the following conversation concisely while preserving:');
    buffer.writeln('- Key facts, decisions, and conclusions');
    buffer.writeln('- User requirements and preferences');
    buffer.writeln('- Technical details, code patterns, and configurations');
    buffer.writeln('- The conversation flow and context');
    buffer.writeln('');
    buffer.writeln('Output ONLY the summary text, no preamble. Keep it under 500 tokens.');
    buffer.writeln('---CONVERSATION START---');

    for (final message in messages) {
      final role = message.role == MessageRole.user ? 'User' : 'Assistant';
      final content = message.content ?? '';
      final hasImages = message.files?.any((f) => f.fileType.startsWith('image/')) ?? false;
      final fileCount = message.files?.length ?? 0;

      buffer.writeln('[$role]: $content');
      if (hasImages) {
        buffer.writeln('  [${fileCount} image(s) attached]');
      }
      buffer.writeln('');
    }

    buffer.writeln('---CONVERSATION END---');
    return buffer.toString();
  }

  static Future<ConversationSummary> summarize({
    required List<ChatMessage> messages,
    required Future<String> Function(String prompt) summarizeWithLLM,
  }) async {
    if (messages.isEmpty) {
      return ConversationSummary(
        summary: '',
        originalMessageCount: 0,
        originalTokenCount: 0,
        summaryTokenCount: 0,
      );
    }

    final originalTokenCount = TokenEstimator.estimateMessagesTokens(messages);
    final prompt = _buildSummaryPrompt(messages);

    String summary;
    try {
      summary = await summarizeWithLLM(prompt);
    } catch (e) {
      return ConversationSummary(
        summary: '[Conversation summary failed: $e]',
        originalMessageCount: messages.length,
        originalTokenCount: originalTokenCount,
        summaryTokenCount: TokenEstimator.estimateTextTokens('[Conversation summary failed: $e]'),
      );
    }

    final summaryTokenCount = TokenEstimator.estimateTextTokens(summary);

    return ConversationSummary(
      summary: summary,
      originalMessageCount: messages.length,
      originalTokenCount: originalTokenCount,
      summaryTokenCount: summaryTokenCount,
    );
  }

  static String buildContextWithSummary({
    required List<ChatMessage> recentMessages,
    required ConversationSummary summary,
    String? systemPrompt,
  }) {
    final buffer = StringBuffer();

    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      buffer.writeln(systemPrompt);
      buffer.writeln('');
    }

    if (summary.summary.isNotEmpty) {
      buffer.writeln('[Previous conversation summary: ${summary.summary}]');
      buffer.writeln('');
    }

    buffer.writeln('[Current conversation continues below:]');

    return buffer.toString();
  }

  static List<ChatMessage> buildCompressedMessages({
    required List<ChatMessage> allMessages,
    required List<ChatMessage> summarizedMessages,
    required ConversationSummary summary,
  }) {
    final result = <ChatMessage>[];
    final summarizedIds = summarizedMessages.map((m) => m.messageId).toSet();

    String? systemContent;
    if (allMessages.isNotEmpty && allMessages.first.role == MessageRole.system) {
      systemContent = allMessages.first.content;
      result.add(ChatMessage(role: MessageRole.system, content: systemContent));
    }

    if (summary.summary.isNotEmpty) {
      result.add(ChatMessage(
        role: MessageRole.system,
        content: '[Context summary of earlier conversation]: ${summary.summary}',
      ));
    }

    for (final message in allMessages) {
      if (summarizedIds.contains(message.messageId)) continue;

      result.add(message);
    }

    return result;
  }
}
