import 'package:chatmcp/provider/provider_manager.dart';
import 'package:chatmcp/provider/settings_provider.dart';
import 'package:logging/logging.dart';
import 'model.dart';
import 'utils.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'dart:io';

abstract class BaseLLMClient {
  static http.Client createHttpClient() {
    final generalSetting = ProviderManager.settingsProvider.generalSetting;

    if (generalSetting.enableProxy && generalSetting.proxyHost.isNotEmpty) {
      final httpClient = HttpClient();

      // Set timeout to 120 seconds (2 minutes) for local models and complex tasks
      httpClient.connectionTimeout = const Duration(seconds: 120);

      // Build proxy string - map proxy type to correct format
      String proxyType;
      switch (generalSetting.proxyType.toUpperCase()) {
        case 'HTTP':
        case 'HTTPS':
          proxyType = 'PROXY';
          break;
        case 'SOCKS4':
          proxyType = 'SOCKS4';
          break;
        case 'SOCKS5':
          proxyType = 'SOCKS5';
          break;
        default:
          proxyType = 'PROXY';
      }

      String proxyString;
      if (generalSetting.proxyUsername.isNotEmpty && generalSetting.proxyPassword.isNotEmpty) {
        proxyString =
            '$proxyType ${generalSetting.proxyUsername}:${generalSetting.proxyPassword}@${generalSetting.proxyHost}:${generalSetting.proxyPort}';
      } else {
        proxyString = '$proxyType ${generalSetting.proxyHost}:${generalSetting.proxyPort}';
      }

      httpClient.findProxy = (uri) {
        Logger.root.info('Using proxy: $proxyString for URL: $uri');
        return proxyString;
      };

      httpClient.badCertificateCallback = (cert, host, port) {
        Logger.root.warning('Accepting certificate for proxy target: $host:$port');
        return true;
      };

      return IOClient(httpClient);
    } else {
      final httpClient = HttpClient();
      httpClient.connectionTimeout = const Duration(seconds: 120);
      return IOClient(httpClient);
    }
  }

  Future<LLMResponse> chatCompletion(CompletionRequest request);

  Stream<LLMResponse> chatStreamCompletion(CompletionRequest request);

  String joinPaths(String first, String second) {
    if (first.isEmpty) return second;
    if (second.isEmpty) return first;

    final firstWithoutTrailing = first.endsWith('/') ? first.substring(0, first.length - 1) : first;
    final secondWithoutLeading = second.startsWith('/') ? second.substring(1) : second;

    return '$firstWithoutTrailing/$secondWithoutLeading';
  }

  String getEndpoint(String url, String path) {
    final urlObj = Uri.parse(url);
    final newPath = joinPaths(urlObj.path, path);
    return urlObj.replace(path: newPath).toString();
  }

  Future<Map<String, dynamic>> checkToolCall(String model, CompletionRequest request, Map<String, List<Map<String, dynamic>>> toolsResponse) async {
    final openaiTools = convertToOpenAITools(toolsResponse);

    try {
      final response = await chatCompletion(CompletionRequest(model: model, messages: request.messages, tools: openaiTools));

      if (!response.needToolCall) {
        return {'need_tool_call': false, 'content': response.content};
      }

      // Return tool call details
      return {
        'need_tool_call': true,
        'content': response.content,
        'tool_calls': response.toolCalls
            ?.map((call) => {'id': call.id, 'name': call.function.name, 'arguments': call.function.parsedArguments})
            .toList(),
      };
    } catch (e) {
      rethrow; // Re-throw the exception for outer handling
    }
  }

  Future<LLMException> handleError(dynamic e, String name, String endpoint, String bodyStr) async {
    if (e is http.ClientException) {
      return LLMException(name: name, endpoint: endpoint, requestBody: bodyStr, originalError: e);
    } else if (e is Exception && e.toString().contains('HTTP')) {
      // Handle HTTP errors (like "HTTP 400: Bad Request")
      final errorMsg = e.toString();
      final statusCodeMatch = RegExp(r'HTTP (\d+)').firstMatch(errorMsg);
      final statusCode = statusCodeMatch != null ? int.tryParse(statusCodeMatch.group(1) ?? '') : null;

      return LLMException(name: name, endpoint: endpoint, requestBody: bodyStr, statusCode: statusCode, responseData: errorMsg, originalError: e);
    } else {
      return LLMException(name: name, endpoint: endpoint, requestBody: bodyStr, originalError: e);
    }
  }

  String getGenTitleModel() {
    final model = ProviderManager.chatModelProvider.currentModel;
    final providerSetting = ProviderManager.settingsProvider.getProviderSetting(model.providerId);
    return providerSetting.genTitleModel != null && providerSetting.genTitleModel!.isNotEmpty ? providerSetting.genTitleModel! : model.name;
  }

  Future<String> genTitle(List<ChatMessage> messages) async {
    if (messages.isEmpty) return "new chat";

    // 限制内容长度，避免触发内容过滤器
    final conversationText = messages
        .map((msg) {
          final role = msg.role == MessageRole.user ? "Human" : "Assistant";
          final content = msg.content ?? '';
          // 限制每条消息最多100个字符，避免内容过长
          final truncatedContent = content.length > 100 ? '${content.substring(0, 100)}...' : content;
          return "$role: $truncatedContent";
        })
        .join("\n");

    // 进一步限制总长度
    final finalText = conversationText.length > 500 ? '${conversationText.substring(0, 500)}...' : conversationText;

    try {
      final prompt = ChatMessage(
        role: MessageRole.user,
        content:
            """Generate a concise title based on the following conversation content.

Conversation content:
$finalText

Please return the result in the following XML format:
<title>Your generated title (max 20 characters)</title>

Note: Only return the XML format result, the title should be concise and clear.""",
      );

      final response = await chatCompletion(CompletionRequest(model: getGenTitleModel(), messages: [prompt]));

      Logger.root.info('genTitle response: ${response.content}');

      final content = response.content?.trim() ?? "";

      // 从 XML 标签中提取标题
      final title = _extractTitleFromXml(content);
      return title.isNotEmpty ? title : "New Chat";
    } catch (e, trace) {
      Logger.root.severe('生成标题出错: $e, trace: $trace');
      return "New Chat";
    }
  }

  /// 从 XML 格式的响应中提取标题
  String _extractTitleFromXml(String xmlContent) {
    if (xmlContent.isEmpty) return "";

    // 尝试匹配 <title>...</title> 标签
    final titleRegex = RegExp(r'<title>(.*?)</title>', caseSensitive: false, dotAll: true);
    final match = titleRegex.firstMatch(xmlContent);

    if (match != null && match.group(1) != null) {
      return match.group(1)!.trim();
    }

    // 如果没有找到 XML 标签，尝试查找是否有其他可能的格式
    final lines = xmlContent.split('\n').where((line) => line.trim().isNotEmpty).toList();

    // 如果只有一行且不包含 XML 标签，可能是纯文本标题
    if (lines.length == 1 && !lines.first.contains('<')) {
      return lines.first.trim();
    }

    return "";
  }

  Future<List<String>> models();

  /// 将模型设置添加到请求体中，只有大于0的参数才会被设置
  Map<String, dynamic> addModelSettingsToBody(Map<String, dynamic> body, ChatSetting? modelSetting) {
    if (modelSetting == null) return body;

    if (modelSetting.temperature > 0) {
      body['temperature'] = modelSetting.temperature;
    }
    if (modelSetting.topP > 0) {
      body['top_p'] = modelSetting.topP;
    }
    if (modelSetting.frequencyPenalty > 0) {
      body['frequency_penalty'] = modelSetting.frequencyPenalty;
    }
    if (modelSetting.presencePenalty > 0) {
      body['presence_penalty'] = modelSetting.presencePenalty;
    }
    if (modelSetting.maxTokens != null && modelSetting.maxTokens! > 0) {
      body['max_tokens'] = modelSetting.maxTokens!;
    }

    return body;
  }
}

class LLMException implements Exception {
  final String name;
  final String endpoint;
  final String requestBody;
  final int? statusCode;
  final dynamic responseData;
  final dynamic originalError;

  LLMException({required this.name, required this.endpoint, required this.requestBody, this.statusCode, this.responseData, this.originalError});

  @override
  String toString() {
    return '''
$name API call failed
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Endpoint: $endpoint
${statusCode != null ? 'Status code: $statusCode\n' : ''}Request body: $requestBody
${responseData != null ? 'Response data: $responseData\n' : ''}Error message: $originalError
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━''';
  }
}
