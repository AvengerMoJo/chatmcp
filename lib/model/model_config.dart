import 'dart:convert';
import 'package:chatmcp/provider/settings_provider.dart';

class ModelConfig {
  final String id;
  final String label;
  final String? description;
  final String? modelId;
  final ChatSetting settings;
  final bool isDefault;
  final bool isCustom;

  ModelConfig({
    required this.id,
    required this.label,
    this.description,
    this.modelId,
    required this.settings,
    this.isDefault = false,
    this.isCustom = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'description': description,
      'modelId': modelId,
      'settings': settings.toJson(),
      'isDefault': isDefault,
      'isCustom': isCustom,
    };
  }

  factory ModelConfig.fromJson(Map<String, dynamic> json) {
    return ModelConfig(
      id: json['id'] as String,
      label: json['label'] as String,
      description: json['description'] as String?,
      modelId: json['modelId'] as String?,
      settings: ChatSetting.fromJson(json['settings'] as Map<String, dynamic>),
      isDefault: json['isDefault'] as bool? ?? false,
      isCustom: json['isCustom'] as bool? ?? false,
    );
  }
}
