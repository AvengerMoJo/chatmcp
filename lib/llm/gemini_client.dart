import 'package:http/http.dart' as http;
import 'base_llm_client.dart';
import 'dart:convert';
import 'model.dart';
import 'package:logging/logging.dart';
import 'package:chatmcp/utils/file_content.dart';

class GeminiClient extends BaseLLMClient {
  final String apiKey;
  final String baseUrl;

  GeminiClient({required this.apiKey, String? baseUrl})
    : baseUrl = (baseUrl == null || baseUrl.isEmpty) ? 'https://generativelanguage.googleapis.com' : baseUrl;

  @override
  Future<LLMResponse> chatCompletion(CompletionRequest request) async {
    final modelName = request.model;

    final body = {
      'contents': chatMessageToGeminiMessage(request.messages),
      if (request.modelSetting != null)
        'generationConfig': {
          'temperature': request.modelSetting!.temperature,
          'topP': request.modelSetting!.topP,
          if (request.modelSetting!.maxTokens != null) 'maxOutputTokens': request.modelSetting!.maxTokens,
        },
    };

    try {
      final httpClient = BaseLLMClient.createHttpClient();
      final response = await httpClient.post(
        Uri.parse("$baseUrl/models/$modelName:generateContent?key=$apiKey"),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      final responseBody = utf8.decode(response.bodyBytes);
      Logger.root.fine('Gemini response: $responseBody');
      if (response.statusCode >= 400) {
        throw Exception('HTTP ${response.statusCode}: $responseBody');
      }

      final jsonData = jsonDecode(responseBody);
      final candidates = jsonData['candidates'] as List;
      if (candidates.isEmpty) {
        throw Exception('No response from Gemini API');
      }

      final content = candidates[0]['content'];
      final text = content['parts'][0]['text'];

      final usage = TokenUsage.fromGemini(jsonData['usageMetadata'], modelName: jsonData['modelVersion']);

      return LLMResponse(content: text, tokenUsage: usage);
    } catch (e) {
      throw await handleError(e, 'Gemini', '$baseUrl/models/$modelName:generateContent', jsonEncode(body));
    }
  }

  @override
  Stream<LLMResponse> chatStreamCompletion(CompletionRequest request) async* {
    final modelName = request.model;

    final Map<String, dynamic> body = {
      'contents': [...chatMessageToGeminiMessage(request.messages)],
    };

    if (request.modelSetting != null) {
      body['generationConfig'] = {
        'temperature': request.modelSetting!.temperature,
        'topP': request.modelSetting!.topP,
        if (request.modelSetting!.maxTokens != null) 'maxOutputTokens': request.modelSetting!.maxTokens,
      };
    }

    try {
      final request = http.Request('POST', Uri.parse("$baseUrl/models/$modelName:streamGenerateContent?key=$apiKey&alt=sse"));
      request.headers.addAll({'Content-Type': 'application/json'});
      request.body = jsonEncode(body);

      final httpClient = BaseLLMClient.createHttpClient();
      final response = await httpClient.send(request);

      if (response.statusCode >= 400) {
        final responseBody = await response.stream.bytesToString();
        Logger.root.fine('Gemini response: $responseBody');

        throw Exception('HTTP ${response.statusCode}: $responseBody');
      }

      final stream = response.stream.transform(utf8.decoder).transform(const LineSplitter());

      await for (final line in stream) {
        if (line.isEmpty || !line.startsWith('data: ')) continue;

        try {
          final json = jsonDecode(line.substring(6)); // Remove 'data: ' prefix

          final candidates = json['candidates'] as List;
          if (candidates.isEmpty) continue;

          final content = candidates[0]['content'];
          final text = content['parts'][0]['text'];

          final usage = TokenUsage.fromGemini(json['usageMetadata'], modelName: json['modelVersion']);

          yield LLMResponse(content: text, tokenUsage: usage);
        } catch (e) {
          Logger.root.severe('Failed to parse chunk: $line $e');
          continue;
        }
      }
    } catch (e) {
      throw await handleError(e, 'Gemini', '$baseUrl/models/$modelName:streamGenerateContent', jsonEncode(body));
    }
  }

  @override
  Future<List<String>> models() async {
    if (apiKey.isEmpty) {
      Logger.root.info('Gemini API key not set, skipping model list fetch');
      return [];
    }

    try {
      final httpClient = BaseLLMClient.createHttpClient();
      final response = await httpClient.get(Uri.parse("$baseUrl/models?key=$apiKey"), headers: {'Content-Type': 'application/json'});

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }

      final data = jsonDecode(response.body);
      final models = (data['models'] as List)
          .map((m) => m['name'].toString().replaceAll('models/', ''))
          .where((name) => name.startsWith('gemini-'))
          .toList();

      return models;
    } catch (e, trace) {
      Logger.root.severe('Failed to get model list: $e, trace: $trace');
      return [];
    }
  }
}

List<Map<String, dynamic>> chatMessageToGeminiMessage(List<ChatMessage> messages) {
  return messages.map((message) {
    final parts = <Map<String, dynamic>>[];

    // Add text content
    if (message.content != null && message.content!.isNotEmpty) {
      parts.add({'text': message.content});
    }

    // Add file content
    if (message.files != null) {
      for (final file in message.files!) {
        if (isImageFile(file.fileType)) {
          parts.add({
            'inlineData': {'mimeType': file.fileType, 'data': file.fileContent},
          });
        }
        if (isTextFile(file.fileType)) {
          parts.add({'text': file.fileContent});
        }
      }
    }

    // 确保至少有一个part
    if (parts.isEmpty) {
      parts.add({
        'text': ' ', // 添加一个空格作为默认文本
      });
    }

    return {'role': message.role == MessageRole.user ? 'user' : 'model', 'parts': parts};
  }).toList();
}

bool isImageFile(String mimeType) {
  return mimeType.startsWith('image/');
}
