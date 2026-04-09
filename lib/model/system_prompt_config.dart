class SystemPromptConfig {
  final String id;
  final String label;
  final String? description;
  final String prompt;
  final bool isDefault;
  final bool isCustom;

  SystemPromptConfig({required this.id, required this.label, this.description, required this.prompt, this.isDefault = false, this.isCustom = false});

  Map<String, dynamic> toJson() {
    return {'id': id, 'label': label, 'description': description, 'prompt': prompt, 'isDefault': isDefault, 'isCustom': isCustom};
  }

  factory SystemPromptConfig.fromJson(Map<String, dynamic> json) {
    return SystemPromptConfig(
      id: json['id'] as String,
      label: json['label'] as String,
      description: json['description'] as String?,
      prompt: json['prompt'] as String,
      isDefault: json['isDefault'] as bool? ?? false,
      isCustom: json['isCustom'] as bool? ?? false,
    );
  }
}
