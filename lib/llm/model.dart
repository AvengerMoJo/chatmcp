import 'dart:convert';
import 'package:chatmcp/provider/settings_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:chatmcp/dao/chat_message.dart';

// Message role enumeration
enum MessageRole {
  system,
  user,
  assistant,
  function,
  tool,
  error,
  loading;

  String get value => name;
}

class File {
  final String name;
  final int size;
  final String? path;
  final String fileType;
  final String fileContent;

  File({required this.name, required this.path, required this.size, required this.fileType, this.fileContent = ''});

  Map<String, dynamic> toJson() {
    return {'name': name, 'path': path, 'size': size, 'fileType': fileType, 'fileContent': fileContent};
  }

  factory File.fromJson(Map<String, dynamic> json) {
    return File(name: json['name'], path: json['path'], size: json['size'], fileType: json['fileType'], fileContent: json['fileContent']);
  }
}

// Message structure
class ChatMessage {
  final String messageId;
  final String parentMessageId;
  final MessageRole role;
  final String? content;
  final String? name;
  final String? mcpServerName;
  final String? toolCallId;
  final TokenUsage? tokenUsage;
  final List<Map<String, dynamic>>? toolCalls;
  final List<File>? files;
  List<String>? brotherMessageIds;
  List<String>? childMessageIds;

  ChatMessage({
    required this.role,
    this.content,
    this.name,
    this.mcpServerName,
    this.toolCallId,
    this.tokenUsage,
    this.toolCalls,
    this.files,
    this.brotherMessageIds,
    this.childMessageIds,
    String? messageId,
    String? parentMessageId,
  }) : messageId = messageId ?? Uuid().v4(),
       parentMessageId = parentMessageId ?? '';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{'role': role.value, if (content != null) 'content': content};

    if (role == MessageRole.tool && name != null && toolCallId != null) {
      json['name'] = name!;
      json['tool_call_id'] = toolCallId!;
    }

    if (toolCalls != null) {
      json['tool_calls'] = toolCalls;
    }

    if (tokenUsage != null) {
      json['tokenUsage'] = tokenUsage!.toJson();
    }

    if (mcpServerName != null) {
      json['mcpServerName'] = mcpServerName!;
    }

    if (files != null) {
      json['files'] = files?.map((file) => file.toJson()).toList();
    }

    json['messageId'] = messageId;
    json['parentMessageId'] = parentMessageId;
    if (brotherMessageIds != null) {
      json['brotherMessageIds'] = brotherMessageIds;
    }

    if (childMessageIds != null) {
      json['childMessageIds'] = childMessageIds;
    }

    return json;
  }

  factory ChatMessage.fromDb(DbChatMessage dbChatMessage) {
    return ChatMessage.fromJson(dbChatMessage.messageId, dbChatMessage.parentMessageId, jsonDecode(dbChatMessage.body));
  }

  factory ChatMessage.fromJson(String messageId, String parentMessageId, Map<String, dynamic> json) {
    // Handle type conversion for toolCalls
    List<Map<String, dynamic>>? toolCalls;
    if (json['tool_calls'] != null) {
      toolCalls = (json['tool_calls'] as List).map((item) => Map<String, dynamic>.from(item)).toList();
    }

    List<File>? files;
    if (json['files'] != null) {
      files = (json['files'] as List).map((item) => File.fromJson(Map<String, dynamic>.from(item))).toList();
    }

    return ChatMessage(
      role: MessageRole.values.firstWhere((e) => e.value == json['role']),
      content: json['content'],
      name: json['name'],
      mcpServerName: json['mcpServerName'],
      toolCallId: json['tool_call_id'],
      tokenUsage: json['tokenUsage'] != null ? TokenUsage.fromJson(Map<String, dynamic>.from(json['tokenUsage'])) : null,
      toolCalls: toolCalls,
      files: files,
      messageId: messageId,
      parentMessageId: parentMessageId,
    );
  }

  @override
  String toString() {
    return jsonEncode(toJson());
  }

  DbChatMessage toDb(int chatId) {
    return DbChatMessage(chatId: chatId, messageId: messageId, parentMessageId: parentMessageId, body: toString());
  }

  ChatMessage copyWith({String? messageId, String? parentMessageId, String? content, MessageRole? role, TokenUsage? tokenUsage, List<Map<String, dynamic>>? toolCalls, List<File>? files}) {
    return ChatMessage(
      messageId: messageId ?? this.messageId,
      parentMessageId: parentMessageId ?? this.parentMessageId,
      role: role ?? this.role,
      content: content ?? this.content,
      tokenUsage: tokenUsage ?? this.tokenUsage,
      name: name,
      mcpServerName: mcpServerName,
      toolCallId: toolCallId,
      toolCalls: toolCalls ?? this.toolCalls,
      files: files ?? this.files,
    );
  }
}

// Add tool call data structure
class ToolCall {
  final String id;
  final String type;
  final FunctionCall function;

  ToolCall({required this.id, required this.type, required this.function});

  Map<String, dynamic> toJson() => {'id': id, 'type': type, 'function': function.toJson()};
}

class FunctionCall {
  final String name;
  final String arguments;

  FunctionCall({required this.name, required this.arguments});

  Map<String, dynamic> toJson() => {'name': name, 'arguments': arguments};

  // Parse arguments to Map
  Map<String, dynamic> get parsedArguments => json.decode(arguments) as Map<String, dynamic>;
}

// LLM response data structure
class LLMResponse {
  final String? content;
  final List<ToolCall>? toolCalls;
  final bool needToolCall;
  final TokenUsage? tokenUsage; // Token usage information

  LLMResponse({this.content, this.toolCalls, this.tokenUsage}) : needToolCall = toolCalls != null && toolCalls.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'content': content,
    'tool_calls': toolCalls?.map((t) => t.toJson()).toList(),
    'need_tool_call': needToolCall,
    if (tokenUsage != null) 'token_usage': tokenUsage!.toJson(),
  };

  // Factory method for creating LLMResponse from JSON
  factory LLMResponse.fromJson(Map<String, dynamic> json) {
    return LLMResponse(
      content: json['content'],
      toolCalls: json['tool_calls'] != null
          ? (json['tool_calls'] as List)
                .map(
                  (t) => ToolCall(
                    id: t['id'],
                    type: t['type'],
                    function: FunctionCall(name: t['function']['name'], arguments: t['function']['arguments']),
                  ),
                )
                .toList()
          : null,
      tokenUsage: json['token_usage'] != null ? TokenUsage.fromJson(json['token_usage']) : null,
    );
  }

  // Create a copy of LLMResponse with optional parameter updates
  LLMResponse copyWith({String? content, List<ToolCall>? toolCalls, TokenUsage? tokenUsage}) {
    return LLMResponse(content: content ?? this.content, toolCalls: toolCalls ?? this.toolCalls, tokenUsage: tokenUsage ?? this.tokenUsage);
  }
}

class TokenUsage {
  final int inputTokens;
  final int outputTokens;
  final int totalTokens;
  final int? thoughtTokens; // Optional for models with reasoning tokens
  final DateTime timestamp; // When the tokens were counted
  final String? modelName; // Which model was used
  final double? cost; // Estimated cost based on token usage
  final String? requestId; // Unique identifier for the request

  TokenUsage({
    required this.inputTokens,
    required this.outputTokens,
    required this.totalTokens,
    this.thoughtTokens,
    DateTime? timestamp,
    this.modelName,
    this.cost,
    this.requestId,
  }) : timestamp = timestamp ?? DateTime.now();
  //cost = cost ?? (modelName != null ? _calculateInitialCost(inputTokens, outputTokens, modelName) : null), // for later use

  /* // Calculate initial cost based on model pricing
  static double? _calculateInitialCost(int inputTokens, int outputTokens, String modelName) {
    final pricing = _getModelPricing(modelName);
    if (pricing == null) return null;
    
    final inputCost = (inputTokens / 1000000) * pricing['input']!;
    final outputCost = (outputTokens / 1000000) * pricing['output']!;
    return inputCost + outputCost;
  }*/

  Map<String, dynamic> toJson() {
    return {
      'inputTokens': inputTokens,
      'outputTokens': outputTokens,
      'totalTokens': totalTokens,
      if (thoughtTokens != null) 'thoughtTokens': thoughtTokens,
      'timestamp': timestamp.toIso8601String(),
      if (modelName != null) 'modelName': modelName,
      if (cost != null) 'cost': cost,
      if (requestId != null) 'requestId': requestId,
    };
  }

  factory TokenUsage.fromJson(Map<String, dynamic> json) {
    return TokenUsage(
      inputTokens: json['inputTokens'] ?? 0,
      outputTokens: json['outputTokens'] ?? 0,
      totalTokens: json['totalTokens'] ?? 0,
      thoughtTokens: json['thoughtTokens'],
      timestamp: json['timestamp'] != null ? DateTime.parse(json['timestamp']) : DateTime.now(),
      modelName: json['modelName'],
      cost: json['cost']?.toDouble(),
      requestId: json['requestId'],
    );
  }

  factory TokenUsage.fromGemini(Map<String, dynamic> usage, {String? modelName, double? cost, String? requestId}) {
    return TokenUsage(
      inputTokens: usage['promptTokenCount'] ?? 0,
      outputTokens: usage['candidatesTokenCount'] ?? 0,
      totalTokens: usage['totalTokenCount'] ?? 0,
      thoughtTokens: usage['thoughtsTokenCount'],
      modelName: modelName,
      cost: cost,
      requestId: requestId,
    );
  }

  factory TokenUsage.fromOpenAI(Map<String, dynamic> usage, {int? timestamp, String? modelName, double? cost, String? requestId}) {
    final completionTokensDetails = usage['completion_tokens_details'] as Map<String, dynamic>?;

    return TokenUsage(
      inputTokens: usage['prompt_tokens'] ?? 0,
      outputTokens: usage['completion_tokens'] ?? 0,
      totalTokens: usage['total_tokens'] ?? 0,
      thoughtTokens: completionTokensDetails?['reasoning_tokens'],
      timestamp: timestamp != null ? DateTime.fromMillisecondsSinceEpoch(timestamp) : DateTime.now(),
      modelName: modelName,
      cost: cost,
      requestId: requestId,
    );
  }

  // Calculate estimated cost based on model pricing
  double calculateCost(String modelName) {
    final pricing = _getModelPricing(modelName);
    if (pricing == null) return 0.0;

    final inputCost = (inputTokens / 1000000) * pricing['input']!;
    final outputCost = (outputTokens / 1000000) * pricing['output']!;
    return inputCost + outputCost;
  }

  // Add tokens from another counter (for conversation totals)
  TokenUsage operator +(TokenUsage other) {
    return TokenUsage(
      inputTokens: inputTokens + other.inputTokens,
      outputTokens: outputTokens + other.outputTokens,
      totalTokens: totalTokens + other.totalTokens,
      thoughtTokens: (thoughtTokens != null || other.thoughtTokens != null) ? (thoughtTokens ?? 0) + (other.thoughtTokens ?? 0) : null,
      timestamp: timestamp.isAfter(other.timestamp) ? timestamp : other.timestamp,
      modelName: modelName ?? other.modelName,
      cost: (cost ?? 0.0) + (other.cost ?? 0.0),
    );
  }

  // Check if token usage is within limits
  bool isWithinLimit(int maxTokens) => totalTokens <= maxTokens;

  // Get efficiency ratio (output/input)
  double get efficiency => inputTokens > 0 ? outputTokens / inputTokens : 0.0;

  // Format for display in UI
  String get displayString => '$inputTokens→$outputTokens (${totalTokens})';

  // Copy with additional information
  TokenUsage copyWith({
    int? inputTokens,
    int? outputTokens,
    int? totalTokens,
    int? thoughtTokens,
    DateTime? timestamp,
    String? modelName,
    double? cost,
    String? requestId,
  }) {
    return TokenUsage(
      inputTokens: inputTokens ?? this.inputTokens,
      outputTokens: outputTokens ?? this.outputTokens,
      totalTokens: totalTokens ?? this.totalTokens,
      thoughtTokens: thoughtTokens ?? this.thoughtTokens,
      timestamp: timestamp ?? this.timestamp,
      modelName: modelName ?? this.modelName,
      cost: cost ?? this.cost,
      requestId: requestId ?? this.requestId,
    );
  }

  @override
  String toString() => jsonEncode(toJson());

  // Private method to get model pricing (per million tokens)
  static Map<String, double>? _getModelPricing(String modelName) {
    // Simplified pricing table - extend as needed
    const pricing = {
      'gpt-4': {'input': 30.0, 'output': 60.0},
      'gpt-4-turbo': {'input': 10.0, 'output': 30.0},
      'gpt-3.5-turbo': {'input': 0.5, 'output': 1.5},
      'claude-3-opus': {'input': 15.0, 'output': 75.0},
      'claude-3-sonnet': {'input': 3.0, 'output': 15.0},
      'gemini-pro': {'input': 0.5, 'output': 1.5},
      "gemini-2.5-flash": {'input': 0.5, 'output': 1.5},
    };

    return pricing[modelName.toLowerCase()];
  }

  String toMarkdown() {
    final buffer = StringBuffer();
    buffer.writeln('**Input Tokens:** $inputTokens');
    buffer.writeln('**Output Tokens:** $outputTokens');
    buffer.writeln('**Total Tokens:** $totalTokens');
    if (thoughtTokens != null) {
      buffer.writeln('**Thought Tokens:** $thoughtTokens');
    }
    buffer.writeln('**Timestamp:** ${timestamp.toIso8601String()}');
    if (modelName != null) {
      buffer.writeln('**Model Name:** $modelName');
    }
    if (cost != null) {
      buffer.writeln('**Estimated Cost:** \$$cost');
    }
    if (requestId != null) {
      buffer.writeln('**Request ID:** $requestId');
    }
    return buffer.toString();
  }
}

class Model {
  final String name;
  final String label;
  final String providerId;
  final String apiStyle;
  final String icon;
  final String providerName;
  final int priority;

  Model({
    required this.name,
    required this.label,
    required this.providerId,
    required this.icon,
    required this.providerName,
    required this.apiStyle,
    this.priority = 0,
  });

  factory Model.fromJson(Map<String, dynamic> json) {
    return Model(
      name: json['name'],
      label: json['label'],
      providerId: json['provider'],
      icon: json['icon'],
      providerName: json['providerName'],
      apiStyle: json['apiStyle'],
      priority: json['priority'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'label': label,
    'provider': providerId,
    'icon': icon,
    'providerName': providerName,
    'apiStyle': apiStyle,
    'priority': priority,
  };

  @override
  String toString() => jsonEncode(toJson());
}

class CompletionRequest {
  final String model;
  final List<ChatMessage> messages;
  final List<Map<String, dynamic>>? tools;
  final bool stream;
  ChatSetting? modelSetting;

  CompletionRequest({required this.model, required this.messages, this.tools, this.stream = false, this.modelSetting});
}
