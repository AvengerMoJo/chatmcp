import 'package:chatmcp/utils/toast.dart';
import 'package:http/http.dart' as http;
import 'base_llm_client.dart';
import 'dart:convert';
import 'model.dart';
import 'package:logging/logging.dart';
import 'package:chatmcp/utils/file_content.dart';

class FoundryClient extends BaseLLMClient {
  final String apiKey;
  final String baseUrl;
  final String apiVersion;
  final String modelVersion = '2023-03-15-preview';
  final Map<String, String> _headers;

  FoundryClient({required this.apiKey, String? apiVersion, String? baseUrl})
    : baseUrl = (baseUrl == null || baseUrl.isEmpty) ? 'https://YOUR_RESOURCE_NAME.openai.azure.com' : baseUrl,
      apiVersion = apiVersion ?? 'preview',
      _headers = {'Content-Type': 'application/json; charset=utf-8', 'api-key': apiKey};

  @override
  Future<LLMResponse> chatCompletion(CompletionRequest request) async {
    final body = {'model': request.model, 'messages': chatMessageToOpenAIMessage(request.messages)};

    addModelSettingsToBody(body, request.modelSetting);

    if (request.tools != null && request.tools!.isNotEmpty) {
      body['tools'] = request.tools!;
      body['tool_choice'] = 'auto';
    }

    final bodyStr = jsonEncode(body);
    Logger.root.finer('OpenAI request: ${bodyStr.length} bytes');

    final endpoint = apiVersion == "preview"
        ? "${getEndpoint(baseUrl, '/openai/v1/chat/completions')}?api-version=$apiVersion"
        : "${getEndpoint(baseUrl, '/openai/deployments/${request.model}/chat/completions')}?api-version=$apiVersion";

    try {
      final httpClient = BaseLLMClient.createHttpClient();
      final response = await httpClient.post(Uri.parse(endpoint), headers: _headers, body: jsonEncode(body));

      final responseBody = utf8.decode(response.bodyBytes);
      Logger.root.finer('OpenAI response: ${responseBody.length} bytes');

      if (response.statusCode >= 400) {
        throw Exception('HTTP ${response.statusCode}: $responseBody');
      }

      final jsonData = jsonDecode(responseBody);

      final message = jsonData['choices'][0]['message'];

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

      return LLMResponse(content: message['content'], toolCalls: toolCalls);
    } catch (e) {
      throw await handleError(e, 'Foundry', endpoint, bodyStr);
    }
  }

  @override
  Stream<LLMResponse> chatStreamCompletion(CompletionRequest request) async* {
    final body = {'model': request.model, 'messages': chatMessageToOpenAIMessage(request.messages), 'stream': true};

    addModelSettingsToBody(body, request.modelSetting);

    Logger.root.finer("foundry stream: ${request.model}, ${request.messages.length} messages, ${jsonEncode(body).length} bytes");

    final endpoint = apiVersion == "preview"
        ? "${getEndpoint(baseUrl, '/openai/v1/chat/completions')}?api-version=$apiVersion"
        : "${getEndpoint(baseUrl, '/openai/deployments/${request.model}/chat/completions')}?api-version=$apiVersion";

    try {
      final request = http.Request('POST', Uri.parse(endpoint));
      request.headers.addAll(_headers);
      request.body = jsonEncode(body);

      final httpClient = BaseLLMClient.createHttpClient();
      final response = await httpClient.send(request);

      if (response.statusCode >= 400) {
        final responseBody = await response.stream.bytesToString();
        Logger.root.finer('OpenAI response: ${responseBody.length} bytes');

        throw Exception('HTTP ${response.statusCode}: $responseBody');
      }

      final stream = response.stream.transform(utf8.decoder).transform(const LineSplitter());

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

          final toolCalls = delta['tool_calls']
              ?.map<ToolCall>(
                (t) => ToolCall(
                  id: t['id'] ?? '',
                  type: t['type'] ?? '',
                  function: FunctionCall(name: t['function']?['name'] ?? '', arguments: t['function']?['arguments'] ?? '{}'),
                ),
              )
              ?.toList();

          if (delta['content'] != null || toolCalls != null) {
            yield LLMResponse(content: delta['content'], toolCalls: toolCalls);
          }
        } catch (e) {
          Logger.root.severe('Failed to parse event data: $data $e');
          continue;
        }
      }
    } catch (e) {
      throw await handleError(e, 'Foundry', endpoint, jsonEncode(body));
    }
  }

  @override
  Future<List<String>> models() async {
    if (apiKey.isEmpty) {
      ToastUtils.error('API key not set, skipping model list fetch');
      return [];
    }

    try {
      final httpClient = BaseLLMClient.createHttpClient();
      final response = await httpClient.get(Uri.parse("${getEndpoint(baseUrl, "/openai/deployments")}?api-version=$modelVersion"), headers: _headers);

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }

      final data = jsonDecode(response.body);

      // Filter out models o1-mini and o1-preview, because of unsupported system message
      final models = (data['data'] as List)
          .where((m) => m['status'] == 'succeeded' && m['model'] != 'o1-mini' && m['model'] != 'o1-preview')
          .map((m) => m['id'].toString())
          .toList();

      return models;
    } catch (e, trace) {
      Logger.root.severe('Failed to get model list: $e, trace: $trace');
      throw LLMException(
        name: 'Foundry',
        endpoint: Uri.parse("${getEndpoint(baseUrl, "/openai/deployments")}?api-version=$modelVersion").toString(),
        requestBody: '',
        originalError: e,
      );
    }
  }
}

List<Map<String, dynamic>> chatMessageToOpenAIMessage(List<ChatMessage> messages) {
  final result = <Map<String, dynamic>>[];
  for (final message in messages) {
    if (message.role == MessageRole.loading || message.role == MessageRole.error) continue;

    var role = message.role.value;
    if (message.role == MessageRole.function) {
      role = MessageRole.tool.value;
    }

    final json = <String, dynamic>{'role': role};
    final content = message.content ?? '';
    final files = message.files;

    if (files != null && files.isNotEmpty && role == MessageRole.user.value) {
      final contentParts = <Map<String, dynamic>>[];
      for (final file in files) {
        if (isImageFile(file.fileType) && file.fileContent.isNotEmpty) {
          contentParts.add({
            'type': 'image_url',
            'image_url': {'url': 'data:${file.fileType};base64,${file.fileContent}'},
          });
        } else if (isTextFile(file.fileType) && file.fileContent.isNotEmpty) {
          contentParts.add({'type': 'text', 'text': file.fileContent});
        }
      }
      if (content.isNotEmpty) {
        contentParts.add({'type': 'text', 'text': content});
      }
      json['content'] = contentParts.isEmpty ? '' : contentParts;
    } else {
      json['content'] = content;
    }

    if (role == MessageRole.tool.value) {
      if (message.toolCallId == null || message.toolCallId!.isEmpty) continue;
      json['tool_call_id'] = message.toolCallId!;
    }

    if (role == MessageRole.assistant.value && message.toolCalls != null && message.toolCalls!.isNotEmpty) {
      final validToolCalls = message.toolCalls!.where((tc) {
        final fn = tc['function'];
        final fnName = fn is Map ? (fn['name']?.toString().trim() ?? '') : '';
        final fnArgs = fn is Map ? (fn['arguments']?.toString() ?? '') : '';
        return fnName.isNotEmpty && fnArgs.isNotEmpty;
      }).toList();
      if (validToolCalls.isNotEmpty) {
        json['tool_calls'] = validToolCalls;
      }
    }

    result.add(json);
  }
  return result;
}
