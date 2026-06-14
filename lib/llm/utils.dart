import '../utils/think_tags.dart';

List<Map<String, dynamic>> convertToOpenAITools(Map<String, List<Map<String, dynamic>>> toolsByClient) {
  List<Map<String, dynamic>> allTools = [];

  // Merge tool lists from all clients
  for (var tools in toolsByClient.values) {
    final openAITools = tools
        .map(
          (tool) => {
            'type': 'function',
            'function': {
              'name': tool['name'].toString(),
              'description': tool['description'].toString(),
              'parameters': Map<String, dynamic>.from(tool['inputSchema']),
            },
          },
        )
        .toList();

    allTools.addAll(openAITools);
  }

  return allTools;
}

/// Extracts `<think>…</think>` blocks from assistant messages into a sibling
/// `reasoning_content` field and strips them from `content`.
///
/// Used by OpenAI-compat providers (DeepSeek, Foundry, etc.) that pass
/// reasoning back to the model on subsequent turns. Without this, prior
/// reasoning bleeds into the conversation and the next model turn re-echos
/// it (or providers reject the payload).
///
/// The matching regex lives in [thinkBlockRegex] (see `lib/utils/think_tags.dart`)
/// so the TTS path and the wire path stay in sync when new shapes are added.
void extractReasoningContent(List<Map<String, dynamic>> messages) {
  for (final msg in messages) {
    if (msg['role'] != 'assistant') continue;
    final content = msg['content'];
    if (content is! String || !content.contains('<think')) continue;

    final matches = thinkBlockRegex.allMatches(content).toList();
    if (matches.isEmpty) continue;

    // Slice out the inner text of each block. The shared regex has no capture
    // group, so we strip the opener/closer manually.
    final inner = <String>[];
    for (final m in matches) {
      final raw = content.substring(m.start, m.end);
      final openEnd = raw.indexOf('>');
      final closeStart = raw.lastIndexOf('</');
      if (openEnd == -1 || closeStart == -1 || closeStart <= openEnd) continue;
      final text = raw.substring(openEnd + 1, closeStart).trim();
      if (text.isNotEmpty) inner.add(text);
    }
    if (inner.isEmpty) continue;

    msg['reasoning_content'] = inner.join('\n');
    final clean = content
        .replaceAll(thinkBlockRegex, '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    if (clean.isEmpty) {
      if (msg.containsKey('tool_calls')) {
        msg.remove('content');
      } else {
        msg['content'] = '';
      }
    } else {
      msg['content'] = clean;
    }
  }
}
