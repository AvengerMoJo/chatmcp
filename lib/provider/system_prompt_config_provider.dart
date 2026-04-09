import 'package:flutter/material.dart';
import 'package:chatmcp/model/system_prompt_config.dart';
import 'package:chatmcp/provider/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class SystemPromptConfigProvider extends ChangeNotifier {
  static final SystemPromptConfigProvider _instance = SystemPromptConfigProvider._internal();
  factory SystemPromptConfigProvider() => _instance;
  SystemPromptConfigProvider._internal() {
    _loadConfigs();
  }

  static const String _configsKey = 'system_prompt_configs';
  static const String _selectedConfigKey = 'selected_system_prompt_config';
  List<SystemPromptConfig> _configs = [];
  String? _selectedConfigId;

  List<SystemPromptConfig> get configs => _configs;
  String? get selectedConfigId => _selectedConfigId;

  Future<void> _loadConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    final configsJson = prefs.getString(_configsKey);
    if (configsJson != null) {
      final List<dynamic> decoded = jsonDecode(configsJson);
      _configs = decoded.map((json) => SystemPromptConfig.fromJson(json)).toList();
    } else {
      _configs = List.from(defaultSystemPromptConfigs);
    }
    _selectedConfigId = prefs.getString(_selectedConfigKey);
    notifyListeners();
  }

  Future<void> _saveConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_configsKey, jsonEncode(_configs.map((c) => c.toJson()).toList()));
  }

  Future<void> _saveSelectedConfig() async {
    final prefs = await SharedPreferences.getInstance();
    if (_selectedConfigId != null) {
      await prefs.setString(_selectedConfigKey, _selectedConfigId!);
    } else {
      await prefs.remove(_selectedConfigKey);
    }
  }

  Future<String> createCustomConfig(String name, String prompt) async {
    final newConfig = SystemPromptConfig(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      label: name,
      description: null,
      prompt: prompt,
      isDefault: false,
      isCustom: true,
    );

    _configs.add(newConfig);
    await _saveConfigs();
    await selectConfig(newConfig.id);
    return newConfig.id;
  }

  Future<void> deleteConfig(String configId) async {
    if (_configs.any((c) => c.id == configId && c.isDefault)) {
      return;
    }
    _configs.removeWhere((c) => c.id == configId);
    await _saveConfigs();
    if (_selectedConfigId == configId) {
      _selectedConfigId = null;
      await _saveSelectedConfig();
      notifyListeners();
    }
  }

  String applyConfig(String configId) {
    final config = _configs.firstWhere((c) => c.id == configId);
    return config.prompt;
  }

  Future<void> selectConfig(String configId) async {
    _selectedConfigId = configId;
    await _saveSelectedConfig();
    notifyListeners();
  }

  Future<void> resetToDefault() async {
    _selectedConfigId = null;
    await _saveSelectedConfig();
    notifyListeners();
  }

  SystemPromptConfig? getSelectedConfig() {
    if (_selectedConfigId == null) {
      return null;
    }
    try {
      return _configs.firstWhere((c) => c.id == _selectedConfigId);
    } catch (e) {
      return null;
    }
  }

  Future<void> syncToSelectedConfig(String currentPrompt) async {
    if (_selectedConfigId == null) return;

    final configIndex = _configs.indexWhere((c) => c.id == _selectedConfigId);
    if (configIndex == -1) return;

    final config = _configs[configIndex];

    if (config.isCustom) {
      final updatedConfig = SystemPromptConfig(
        id: config.id,
        label: config.label,
        description: config.description,
        prompt: currentPrompt,
        isDefault: config.isDefault,
        isCustom: config.isCustom,
      );

      _configs[configIndex] = updatedConfig;
      await _saveConfigs();
      notifyListeners();
    }
  }

  Future<void> saveSelectedConfig(String currentPrompt) async {
    await syncToSelectedConfig(currentPrompt);
  }
}
