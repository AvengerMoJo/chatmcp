# ChatMCP v0.0.80 Release Notes

## 🆕 New Features

### Model Configuration
- **Model Config Picker**: New dropdown in chat settings to quickly switch between different model configurations
- **Save Custom Configurations**: Save current settings (temperature, max tokens, topP, etc.) as named presets
- **Delete Configurations**: Remove custom configurations with confirmation dialog
- **Default Configs**: Built-in presets (Default, Balanced, Creative, Precise) for quick access

## 🐛 Bug Fixes

### UI & Focus
- **Fixed dropdown focus issues**: Replaced DropdownButton with ModalBottomSheet to prevent UI freeze after pressing ESC
- **Fixed RTL input**: Set TextDirection.ltr for Max Tokens input field to fix reversed number input

### Config Picker
- **Fixed config label display**: Now shows actual selected config name instead of placeholder
- **Fixed rebuild issues**: Uses ListenableBuilder to properly update UI when config changes

## 🔧 Improvements

### Settings UI
- Better modal bottom sheet UI for config picker
- Confirmation dialog before deleting custom configurations
- Smooth transitions and better touch targets

## 📝 Technical Details

### Changed Files
- `lib/page/layout/widgets/config_picker.dart`: New widget with ModalBottomSheet
- `lib/page/layout/widgets/chat_setting.dart`: Integrated config picker and fixed input direction
- `lib/provider/model_config_provider.dart`: Model configuration state management
- `lib/model/model_config.dart`: Model configuration data model

---

## 📋 Known Issues

- LaTeX rendering may show parse errors for malformed math expressions from MCP tools

## 🙏 Acknowledgments

Thanks to all users who reported bugs and provided feedback!
