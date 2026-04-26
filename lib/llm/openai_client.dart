import 'package:chatmcp/utils/toast.dart';
import 'package:http/http.dart' as http;
import 'base_llm_client.dart';
import 'dart:convert';
import 'model.dart';
import 'package:logging/logging.dart';
import 'package:chatmcp/utils/file_content.dart';

class OpenAIClient extends BaseLLMClient {
  final String apiKey;
  final String baseUrl;
  final Map<String, String> _headers;

  OpenAIClient({required this.apiKey, String? baseUrl})
    : baseUrl = (baseUrl == null || baseUrl.isEmpty) ? 'https://api.openai.com/v1' : baseUrl,
      _headers = {'Content-Type': 'application/json; charset=utf-8', 'Authorization': 'Bearer $apiKey'};

  @override
  Future<LLMResponse> chatCompletion(CompletionRequest request) async {
    final httpClient = BaseLLMClient.createHttpClient();

    final body = {'model': request.model, 'messages': chatMessageToOpenAIMessage(request.messages)};

    addModelSettingsToBody(body, request.modelSetting);

    if (request.tools != null && request.tools!.isNotEmpty) {
      body['tools'] = request.tools!;
      body['tool_choice'] = 'auto';
    }

    final bodyStr = jsonEncode(body);
    Logger.root.fine('OpenAI request: $bodyStr');

    final endpoint = getEndpoint(baseUrl, "/chat/completions");

    try {
      final response = await httpClient.post(Uri.parse(endpoint), headers: _headers, body: bodyStr);

      final responseBody = utf8.decode(response.bodyBytes);
      Logger.root.fine('OpenAI response: $responseBody');

      if (response.statusCode >= 400) {
        throw Exception('HTTP ${response.statusCode}: $responseBody');
      }

      final jsonData = jsonDecode(responseBody);

      final message = jsonData['choices'][0]['message'];

      // Check for reasoning_content (used by thinking models like Gemma)
      final reasoningContent = message['reasoning_content'] as String?;
      final content = message['content'] as String?;

      // If reasoning_content exists, wrap it in think tags for proper display
      String finalContent = content ?? '';
      if (reasoningContent != null && reasoningContent.isNotEmpty) {
        finalContent = '<think start-time="${DateTime.now().toIso8601String()}">$reasoningContent</think>';
        if (content != null && content.isNotEmpty) {
          finalContent = '$finalContent\n\n$content';
        }
      }

      // Parse tool calls
      final toolCalls = message['tool_calls']
          ?.map<ToolCall>(
            (t) => ToolCall(
              id: t['id'],
              type: t['type'],
              function: FunctionCall(name: t['function']['name'], arguments: t['function']['arguments']),
            ),
          )
          ?.toList();
      TokenUsage? tokenUsage;
      if (jsonData['usage'] != null) {
        tokenUsage = TokenUsage.fromOpenAI(jsonData['usage'], modelName: jsonData['model']);
      }
      return LLMResponse(content: finalContent, toolCalls: toolCalls, tokenUsage: tokenUsage);
    } catch (e) {
      throw await handleError(e, 'OpenAI', endpoint, bodyStr);
    } finally {
      httpClient.close();
    }
  }

  @override
  Stream<LLMResponse> chatStreamCompletion(CompletionRequest request) async* {
    final httpClient = BaseLLMClient.createHttpClient();

    final body = {'model': request.model, 'messages': chatMessageToOpenAIMessage(request.messages), 'stream': true};

    addModelSettingsToBody(body, request.modelSetting);

    Logger.root.finer("openai stream: ${request.model}, ${request.messages.length} messages, ${jsonEncode(body).length} bytes");

    final endpoint = getEndpoint(baseUrl, "/chat/completions");

    try {
      final httpRequest = http.Request('POST', Uri.parse(endpoint));
      httpRequest.headers.addAll(_headers);
      httpRequest.body = jsonEncode(body);

      final response = await httpClient.send(httpRequest);

      if (response.statusCode >= 400) {
        final responseBody = await response.stream.bytesToString();
        Logger.root.fine('OpenAI response: $responseBody');

        throw Exception('HTTP ${response.statusCode}: $responseBody');
      }

      final stream = response.stream.transform(utf8.decoder).transform(const LineSplitter());

      Logger.root.info('openai start stream response');
      bool reasoningContentStart = false;
      bool reasoningContentEnd = false;
      bool reasoningStyle = false;

      await for (final line in stream) {
        if (!line.startsWith('data: ')) continue;
        final data = line.substring(6);
        if (data.isEmpty || data == '[DONE]') continue;

        try {
          final json = jsonDecode(data);

          if (json['choices'] == null || json['choices'].isEmpty) {
            continue;
          }

          final delta = json['choices'][0]['delta'];
          if (delta == null) continue;

          // Check for reasoning_content in delta (used by thinking models)
          final reasoningContent = delta != null ? (delta['reasoning_content'] ?? '') : '';
          final content = delta != null ? (delta['content'] ?? '') : '';

          // Parse tool calls from delta
          final toolCalls = delta['tool_calls']
              ?.map<ToolCall>(
                (t) => ToolCall(
                  id: t['id'] ?? '',
                  type: t['type'] ?? 'function',
                  function: FunctionCall(
                    name: t['function']?['name'] ?? '',
                    arguments: t['function']?['arguments'] ?? '{}',
                  ),
                ),
              )
              ?.toList();

          if (reasoningContent.isNotEmpty) {
            reasoningStyle = true;
            if (!reasoningContentStart) {
              reasoningContentStart = true;
              yield LLMResponse(content: '\n<think start-time="${DateTime.now().toIso8601String()}">\n$reasoningContent', toolCalls: toolCalls);
            } else {
              yield LLMResponse(content: reasoningContent, toolCalls: toolCalls);
            }
          }

          if (reasoningStyle && content.isNotEmpty) {
            if (!reasoningContentEnd) {
              reasoningContentEnd = true;
              yield LLMResponse(content: '\n</think end-time="${DateTime.now().toIso8601String()}">\n$content', toolCalls: toolCalls);
            } else {
              yield LLMResponse(content: content, toolCalls: toolCalls);
            }
          } else if (!reasoningStyle && (content.isNotEmpty || (toolCalls != null && toolCalls.isNotEmpty))) {
            yield LLMResponse(content: content.isNotEmpty ? content : null, toolCalls: toolCalls);
          }

          if (json['usage'] != null) {
            yield LLMResponse(tokenUsage: TokenUsage.fromOpenAI(json['usage'], modelName: json['model']));
          }
        } catch (e) {
          Logger.root.severe('Failed to parse event data: $data $e');
          continue;
        }
      }
    } catch (e) {
      throw await handleError(e, 'OpenAI', endpoint, jsonEncode(body));
    } finally {
      httpClient.close();
    }
  }

  @override
  Future<List<String>> models() async {
    if (apiKey.isEmpty) {
      ToastUtils.error('API key not set, skipping model list fetch');
      return [];
    }

    final httpClient = BaseLLMClient.createHttpClient();

    try {
      final response = await httpClient.get(Uri.parse(getEndpoint(baseUrl, "/models")), headers: _headers);

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }

      final data = jsonDecode(response.body);
      final models = (data['data'] as List).map((m) => m['id'].toString()).toList();

      return models;
    } catch (e, trace) {
      Logger.root.severe('Failed to get model list: $e, trace: $trace');
      throw LLMException(name: 'OpenAI', endpoint: getEndpoint(baseUrl, "/models"), requestBody: '', originalError: e);
    } finally {
      httpClient.close();
    }
  }
}

List<Map<String, dynamic>> chatMessageToOpenAIMessage(List<ChatMessage> messages) {
  return messages.map((message) {
    final json = <String, dynamic>{'role': message.role.value};

    // If there is both text content and files, use array format
    if (message.content != null || message.files != null) {
      final List<Map<String, dynamic>> contentParts = [];

      // Add file content
      if (message.files != null) {
        for (final file in message.files!) {
          if (isImageFile(file.fileType)) {
            contentParts.add({
              'type': 'image_url',
              'image_url': {'url': 'data:${file.fileType};base64,${file.fileContent}'},
            });
          }
          if (isTextFile(file.fileType)) {
            contentParts.add({'type': 'text', 'text': file.fileContent});
          }
        }
      }

      // Add text content
      if (message.content != null) {
        contentParts.add({'type': 'text', 'text': message.content});
      }

      // If there is only one text content and no files, use simple string format
      if (contentParts.length == 1 && message.files == null) {
        json['content'] = message.content;
      } else {
        json['content'] = contentParts;
      }
    }

    // Add tool call related fields
    if (message.role == MessageRole.tool && message.name != null && message.toolCallId != null) {
      json['name'] = message.name!;
      json['tool_call_id'] = message.toolCallId!;
    }

    if (message.toolCalls != null) {
      json['tool_calls'] = message.toolCalls;
    }

    return json;
  }).toList();
}
