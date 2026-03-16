import 'package:flutter/material.dart';
import 'package:chatmcp/model/model_config.dart';
import 'package:chatmcp/provider/settings_provider.dart';
import 'package:chatmcp/provider/provider_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

final List<ModelConfig> defaultConfigs = [
  ModelConfig(
    id: 'default',
    label: 'Default',
    description: 'Recommended settings for general use',
    modelId: null,
    settings: ChatSetting(temperature: 1.0, maxTokens: null, topP: 1.0, frequencyPenalty: 0.0, presencePenalty: 0.0),
    isDefault: true,
    isCustom: false,
  ),
  ModelConfig(
    id: 'balanced',
    label: 'Balanced',
    description: 'Balanced between creativity and precision',
    modelId: null,
    settings: ChatSetting(temperature: 0.7, maxTokens: 2000, topP: 0.9, frequencyPenalty: 0.0, presencePenalty: 0.0),
    isDefault: false,
    isCustom: false,
  ),
  ModelConfig(
    id: 'creative',
    label: 'Creative',
    description: 'Higher randomness for creative tasks',
    modelId: null,
    settings: ChatSetting(temperature: 1.3, maxTokens: 4096, topP: 0.95, frequencyPenalty: 0.0, presencePenalty: 0.0),
    isDefault: false,
    isCustom: false,
  ),
  ModelConfig(
    id: 'precise',
    label: 'Precise',
    description: 'Lower randomness for factual tasks',
    modelId: null,
    settings: ChatSetting(temperature: 0.2, maxTokens: 1000, topP: 0.8, frequencyPenalty: 0.0, presencePenalty: 0.0),
    isDefault: false,
    isCustom: false,
  ),
];

class ModelConfigProvider extends ChangeNotifier {
  static final ModelConfigProvider _instance = ModelConfigProvider._internal();
  factory ModelConfigProvider() => _instance;
  ModelConfigProvider._internal() {
    _loadConfigs();
  }

  static const String _configsKey = 'model_configs';
  static const String _selectedConfigKey = 'selected_model_config';
  List<ModelConfig> _configs = [];
  String? _selectedConfigId;

  List<ModelConfig> get configs => _configs;
  String? get selectedConfigId => _selectedConfigId;

  Future<void> _loadConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    final configsJson = prefs.getString(_configsKey);
    if (configsJson != null) {
      final List<dynamic> decoded = jsonDecode(configsJson!);
      _configs = decoded.map((json) => ModelConfig.fromJson(json)).toList();
    } else {
      _configs = List.from(defaultConfigs);
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

  Future<String> createCustomConfig(String name) async {
    final currentSettings = ProviderManager.settingsProvider.modelSetting;
    final newConfig = ModelConfig(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      label: name,
      description: null,
      modelId: null,
      settings: currentSettings,
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

  Future<void> applyConfig(String configId) async {
    final config = _configs.firstWhere((c) => c.id == configId);

    await ProviderManager.settingsProvider.updateModelSettings(
      temperature: config.settings.temperature,
      maxTokens: config.settings.maxTokens,
      topP: config.settings.topP,
      frequencyPenalty: config.settings.frequencyPenalty,
      presencePenalty: config.settings.presencePenalty,
    );
  }

  Future<void> selectConfig(String configId) async {
    _selectedConfigId = configId;
    await _saveSelectedConfig();
    notifyListeners();
    await applyConfig(configId);
  }

  Future<void> resetToDefault() async {
    _selectedConfigId = null;
    await _saveSelectedConfig();
    notifyListeners();
  }

  ModelConfig? getSelectedConfig() {
    if (_selectedConfigId == null) {
      return null;
    }
    try {
      return _configs.firstWhere((c) => c.id == _selectedConfigId);
    } catch (e) {
      return null;
    }
  }
}
