# ChatMCP v0.0.82 Release Notes

## 🆕 New Features

### Model Configuration System
- **Save/Save As Functionality**: Clear distinction between modifying existing configs and creating new ones
- **Auto-Sync for Custom Configs**: Settings changes automatically save to selected custom configuration
- **Smart Button Display**: 
  - "Save" button (blue) appears only when custom config is selected
  - "Save As" button (green) always available for creating new configurations
- **Default Configs Preserved**: Default, Balanced, Creative, and Precise presets remain unchanged by manual adjustments

### System Prompt Configuration
- **System Prompt Picker**: New dropdown in General Settings to switch between different prompt configurations
- **Default Prompt Presets**: Built-in system prompt templates for different use cases:
  - **Default**: Recommended settings for general use
  - **Concise**: Brief and to-the-point responses
  - **Detailed**: Comprehensive explanations with examples
  - **Creative**: More imaginative and creative responses
  - **Technical**: Focus on technical accuracy and precision
- **Custom Prompt Management**: Save, edit, and delete custom system prompt configurations
- **Auto-Sync Support**: Text changes automatically sync to selected custom system prompt config

## 🐛 Bug Fixes

### Input & Typing
- **Fixed Cursor Jump in MaxTokens Input**: Prevented cursor from resetting to beginning when typing numbers
- **Fixed Text Highlighting Issue**: Numbers no longer get highlighted after each keystroke
- **Smooth Number Input**: Can now type numbers continuously without having to reposition cursor

### Speech Recognition
- **Fixed macOS Crash**: Added `NSSpeechRecognitionUsageDescription` to macOS Info.plist
- **Fixed iOS Crash**: Added `NSSpeechRecognitionUsageDescription` to iOS Info.plist
- **Proper Privacy Permissions**: App now correctly requests speech recognition permission from users

### Configuration
- **Fixed Duplicate Config Definitions**: Removed duplicate default configs, now uses single source of truth from `globalModelConfigs`

## 🔧 Improvements

### Settings UI
- **Consistent UI Pattern**: Model and system prompt configurations follow the same Save/Save As pattern
- **Better Visual Feedback**: Different button colors for Save (blue) vs Save As (green) actions
- **Configuration Persistence**: Changes to custom configs are automatically saved
- **Simplified Configuration Management**: Single source of truth for default configurations

### Code Quality
- **Improved Controller Management**: Better TextEditingController lifecycle management
- **Reduced Code Duplication**: Shared patterns between model and system prompt configuration systems
- **Updated Dependencies**: Latest package versions including analyzer 10.0.1

## 🗑️ Removed

### Default MCP Servers
- **Removed 'knownissue' MCP Server**: Default server removed due to unresponsiveness and service reliability issues
- **Clean Server Configuration**: Assets now start with empty MCP server list

## 📝 Technical Details

### Changed Files
- `lib/model/system_prompt_config.dart`: New model for system prompt configurations
- `lib/provider/system_prompt_config_provider.dart`: New provider for managing system prompt configs
- `lib/page/layout/widgets/system_prompt_config_picker.dart`: New picker widget for system prompts
- `lib/page/layout/widgets/chat_setting.dart`: Enhanced with Save/Save As buttons and auto-sync
- `lib/page/setting/general_setting.dart`: Added system prompt picker and management
- `lib/provider/model_config_provider.dart`: Removed duplicates, added auto-sync logic
- `lib/provider/provider_manager.dart`: Added system prompt provider registration
- `lib/provider/settings_provider.dart`: Added default system prompt configs
- `lib/page/layout/widgets/config_picker.dart`: Updated for consistency
- `macos/Runner/Info.plist`: Added speech recognition permission
- `ios/Runner/Info.plist`: Added speech recognition permission
- `assets/mcp_server.json`: Removed knownissue default server
- `pubspec.yaml`: Version bumped to 0.0.82
- `pubspec.lock`: Updated dependency versions

---

## 📋 Known Issues

- None reported in this release

## 🙏 Acknowledgments

Thanks to all users who reported bugs, provided feedback, and helped improve the configuration system!
