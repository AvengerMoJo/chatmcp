/// Shared regex shapes used by:
///  - the wire-payload rewriter (lib/llm/utils.dart) — extracts `<think>…</think>`
///    blocks into a `reasoning_content` field and strips them from `content`.
///  - the TTS path (lib/services/streaming_speech_filter.dart,
///    lib/services/voice_response_extractor.dart) — strips the same blocks so
///    they don't get spoken.
///
/// New providers / formats should add their tag shape here, not inline.
library;

/// Matches a `<think …>…</think …>` block (attributes allowed on both ends).
/// Handles both bare (`<think>…</think>`) and attribute-bearing
/// (`<think start-time="…">…</think end-time="…">`) forms.
///
/// Used in: lib/llm/utils.dart, lib/services/streaming_speech_filter.dart,
/// lib/services/voice_response_extractor.dart.
final RegExp thinkBlockRegex = RegExp(r'<think[^>]*>[\s\S]*?</think[^>]*>', caseSensitive: false);

/// Matches a `<thought …>…</thought …>` block.
///
/// Some Qwen / DeepSeek variants emit `<thought>` instead of `<think>`.
final RegExp thoughtBlockRegex = RegExp(r'<thought[^>]*>[\s\S]*?</thought[^>]*>', caseSensitive: false);

/// Matches a `<function …>…</function>` block.
final RegExp functionBlockRegex = RegExp(r'<function[^>]*>[\s\S]*?</function[^>]*>', caseSensitive: false);

/// Matches a `<call_function_result …>…</call_function_result>` block.
final RegExp callFunctionResultBlockRegex = RegExp(r'<call_function_result[^>]*>[\s\S]*?</call_function_result>');

/// Matches a `<call_function …>…</call_function>` block.
final RegExp callFunctionBlockRegex = RegExp(r'<call_function[^>]*>[\s\S]*?</call_function>');

/// Returns the first matching think-like block (think or thought) replaced
/// with [replacement]. Convenience for the final-pass extractors.
String stripThinkBlocks(String text, {String replacement = ' '}) {
  return text
      .replaceAll(thinkBlockRegex, replacement)
      .replaceAll(thoughtBlockRegex, replacement);
}

/// Returns [text] with all known function/tool/think blocks replaced.
///
/// Used by the TTS path: never speak a thinking block, a tool call, or a
/// function result.
String stripProtocolBlocks(String text, {String replacement = ' '}) {
  return stripThinkBlocks(text, replacement: replacement)
      .replaceAll(functionBlockRegex, replacement)
      .replaceAll(callFunctionResultBlockRegex, replacement)
      .replaceAll(callFunctionBlockRegex, replacement);
}
