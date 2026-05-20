import 'dart:math';
import 'model.dart';

class ModelContextWindow {
  static const int _defaultWindow = 128000;

  /// Returns the context window for a model.
  /// If the provider setting has a custom contextWindow, that takes priority.
  static int getWindow(String modelName, {int? providerContextWindow}) {
    if (providerContextWindow != null && providerContextWindow > 0) {
      return providerContextWindow;
    }
    return _defaultWindow;
  }

  static const double summarizationThreshold = 1.0;
  static const double criticalThreshold = 1.0;
}

class ContextUsage {
  final int textTokens;
  final int imageTokens;
  final int fileTokens;
  final int totalTokens;
  final int contextWindow;
  final double usageRatio;

  ContextUsage({
    required this.textTokens,
    required this.imageTokens,
    required this.fileTokens,
    required this.totalTokens,
    required this.contextWindow,
  }) : usageRatio = contextWindow > 0 ? totalTokens / contextWindow : 0;

  bool get needsSummarization => usageRatio >= ModelContextWindow.summarizationThreshold;
  bool get isCritical => usageRatio >= ModelContextWindow.criticalThreshold;
}

class TokenEstimator {
  static int estimateTextTokens(String text) {
    if (text.isEmpty) return 0;
    return (text.length / 4).ceil();
  }

  static int estimateImageTokens(int width, int height, {bool highRes = false}) {
    if (width <= 0 || height <= 0) return 0;

    if (!highRes) {
      final tiles = ((width + 511) ~/ 512) * ((height + 511) ~/ 512);
      return 85 + 85 * tiles;
    }

    final tiles = ((width + 511) ~/ 512) * ((height + 511) ~/ 512);
    return 85 + 170 * tiles;
  }

  static int estimateMessageTokens(ChatMessage message) {
    int tokens = estimateTextTokens(message.content ?? '');

    if (message.files != null) {
      for (final file in message.files!) {
        tokens += estimateFileTokens(file);
      }
    }

    return tokens;
  }

  static int estimateFileTokens(File file) {
    if (file.fileContent.isEmpty) return 0;

    if (file.fileType.startsWith('image/')) {
      final rawBytes = (file.fileContent.length * 3) ~/ 4;
      final approxPixels = rawBytes ~/ 4;
      final side = sqrt(approxPixels).ceil();
      return estimateImageTokens(side, side, highRes: false);
    }

    return estimateTextTokens(file.fileContent);
  }

  static int estimateMessagesTokens(List<ChatMessage> messages) {
    int total = 0;
    for (final message in messages) {
      total += estimateMessageTokens(message);
      total += 4;
    }
    total += 3;
    return total;
  }

  static ContextUsage analyzeContextUsage(List<ChatMessage> messages, String modelName, {int? providerContextWindow}) {
    int textTokens = 0;
    int imageTokens = 0;
    int fileTokens = 0;

    for (final message in messages) {
      textTokens += estimateTextTokens(message.content ?? '');

      if (message.files != null) {
        for (final file in message.files!) {
          if (file.fileType.startsWith('image/')) {
            final rawBytes = (file.fileContent.length * 3) ~/ 4;
            final approxPixels = rawBytes ~/ 4;
            final side = sqrt(approxPixels).ceil();
            imageTokens += estimateImageTokens(side, side, highRes: false);
          } else {
            fileTokens += estimateTextTokens(file.fileContent);
          }
        }
      }
    }

    final overhead = messages.length * 4 + 3;
    final totalTokens = textTokens + imageTokens + fileTokens + overhead;
    final contextWindow = ModelContextWindow.getWindow(modelName, providerContextWindow: providerContextWindow);

    return ContextUsage(
      textTokens: textTokens,
      imageTokens: imageTokens,
      fileTokens: fileTokens,
      totalTokens: totalTokens,
      contextWindow: contextWindow,
    );
  }
}

class MessageSelector {
  static List<ChatMessage> selectMessagesToSummarize(List<ChatMessage> messages, ContextUsage usage) {
    if (messages.isEmpty || !usage.needsSummarization) return [];

    final systemMessage = messages.isNotEmpty && messages.first.role == MessageRole.system ? messages.removeAt(0) : null;

    // When at 100%+, aim to reduce by 30% of context window to make meaningful room
    const targetReductionRatio = 0.30;
    final targetTokens = (usage.contextWindow * targetReductionRatio).ceil();

    final toSummarize = <ChatMessage>[];
    int accumulatedTokens = 0;

    // Keep the last 5 messages as-is (recent context), summarize everything older
    final messagesToConsider = messages.length > 5 ? messages.sublist(0, messages.length - 5) : [];

    for (final message in messagesToConsider) {
      if (message.role == MessageRole.user && message.files != null && message.files!.any((f) => f.fileType.startsWith('image/'))) {
        toSummarize.add(message);
        accumulatedTokens += TokenEstimator.estimateMessageTokens(message);
        if (accumulatedTokens >= targetTokens) break;
        continue;
      }

      if (message.role == MessageRole.assistant && message.content != null) {
        toSummarize.add(message);
        accumulatedTokens += TokenEstimator.estimateMessageTokens(message);
      }

      if (accumulatedTokens >= targetTokens) break;
    }

    if (systemMessage != null) {
      messages.insert(0, systemMessage);
    }

    return toSummarize;
  }
}
