import 'dart:convert';

import 'package:chatmcp/provider/provider_manager.dart';

class SystemPromptGenerator {
  /// Base prompt template without tool instructions
  final String baseTemplate = '''
<system_prompt>
You will select appropriate tools and call them to solve user queries

**CRITICAL CONSTRAINT: You MUST call only ONE tool per response. Never call multiple tools simultaneously.**
</system_prompt>''';

  /// Tool-related template parts
  final String toolDefinitionsTemplate = '''

**Tool Definitions:**
Here are the functions available, described in JSONSchema format:
<tool_definitions>
{{ TOOL DEFINITIONS IN JSON SCHEMA }}
</tool_definitions>''';

  final String toolUsageTemplate = '''

<tool_usage_instructions>
TOOL USE

You have access to a set of tools that are executed upon the user's approval. You can use one tool per message, and will receive the result of that tool use in the user's response. You use tools step-by-step to accomplish a given task, with each tool use informed by the result of the previous tool use.

# Tool Use Formatting

Tool use is formatted using XML-style tags. The tool name is enclosed in opening and closing tags, and parameters must be provided in JSON format. Here's the structure:

<function name="{tool_name}">
{
  "parameter1_name": "value1",
  "parameter2_name": "value2"
}
</function>

For example:

<function name="read_file">
{
  "path": "src/main.js"
}
</function>

Always adhere to this format for the tool use to ensure proper parsing and execution.
</tool_usage_instructions>''';

  /// Default user system prompt
  final String defaultUserSystemPrompt = 'You are an intelligent assistant capable of using tools to solve user queries effectively.';

  /// Default tool configuration
  final String defaultToolConfig = 'No additional configuration is required.';

  /// Generate system prompt
  ///
  /// [tools] - JSON tool definitions
  /// [userSystemPrompt] - Optional user system prompt
  /// [toolConfig] - Optional tool configuration information
  String generatePrompt({required List<Map<String, dynamic>> tools}) {
    var userPrompt = ProviderManager.settingsProvider.generalSetting.systemPrompt;

    var language = ProviderManager.settingsProvider.generalSetting.locale;

    var prompt = userPrompt;

    if (tools.isNotEmpty) {
      prompt += "\n$baseTemplate";
      final toolsJsonSchema = const JsonEncoder.withIndent('  ').convert(tools);
      prompt += toolDefinitionsTemplate.replaceAll('{{ TOOL DEFINITIONS IN JSON SCHEMA }}', toolsJsonSchema);
      prompt += toolUsageTemplate;
    }

    if (language.isNotEmpty) {
      prompt += "\n\nLanguage: $language";
    }

    return prompt;
  }

  /// Generate system prompt
  ///
  /// [tools] - List of available tools
  /// Returns a concise, action-oriented system prompt
  String generateToolPrompt(List<Map<String, dynamic>> tools) {
    final promptGenerator = SystemPromptGenerator();
    var systemPrompt = promptGenerator.generatePrompt(tools: tools);
    return systemPrompt;
  }
}
