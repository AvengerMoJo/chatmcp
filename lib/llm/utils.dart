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
/// Handles both bare (`<think>…</think>`) and attribute-bearing
/// (`<think start-time="…">…</think end-time="…">`) tags.
void extractReasoningContent(List<Map<String, dynamic>> messages) {
  final thinkRegex = RegExp(r'<think[^>]*>(.*?)</think[^>]*>', dotAll: true);
  for (final msg in messages) {
    if (msg['role'] != 'assistant') continue;
    final content = msg['content'];
    if (content is! String || !content.contains('<think')) continue;

    final matches = thinkRegex.allMatches(content).toList();
    if (matches.isEmpty) continue;

    final reasoning = matches
        .map((m) => m.group(1)?.trim() ?? '')
        .where((s) => s.isNotEmpty)
        .join('\n');
    if (reasoning.isEmpty) continue;

    msg['reasoning_content'] = reasoning;
    final clean = content
        .replaceAll(thinkRegex, '')
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
