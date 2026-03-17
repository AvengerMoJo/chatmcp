# ChatMCP v0.0.78 Release Notes

## 🆕 New Features

### Chat Management
- **Edit Chat Titles**: Users can now rename conversations by right-clicking (desktop) or long-pressing (mobile) on chat items in the sidebar
- Added context menu with Edit and Delete actions for better chat management

### File Upload Improvements
- **Provider-aware file upload handling**: Different providers now handle file uploads appropriately based on their capabilities
- **Separate buttons for desktop**: Dedicated image picker and file picker buttons for better UX
- **Text extraction support**: Automatically extracts text from uploaded files when supported

### Provider Capabilities
- **Provider capability flags**: Added `supportsImages` flag to properly handle which providers support image uploads
- **New provider icons**: Added visual icons for easier provider identification

## 🐛 Bug Fixes

### MCP & Content Handling
- **Fixed MCP response content extraction**: Properly handles structured content format `[{"type": "text", "text": "..."}]` to prevent LaTeX rendering errors
- **Fixed chat title refresh**: Chat titles now update immediately in the sidebar after editing (no app restart required)

### File Upload & Link Handling
- **Fixed concurrent modification error**: Added defensive list copying to prevent race conditions
- **Fixed text file detection**: Removed PDF/Excel from text file detection
- **Fixed git SSH URL rendering**: Prevents SSH URLs from being incorrectly rendered as mailto links
- **Fixed image_url format**: Corrected format for OpenAI and OpenRouter providers

### Provider Configuration
- **Fixed duplicate provider definitions**: Removed duplicate entries causing conflicts
- **Fixed provider endpoints**: Corrected endpoints and models for new providers
- **Fixed image support**: Properly disabled image support for providers that don't support it

## 🔧 Improvements

### File Upload Flow
- Better error handling and logging for file upload operations
- Improved file type detection and handling
- Integrated FileUploadHandler into chat submission flow

### Provider Management
- All fetch-based providers are now disabled by default to prevent accidental API usage
- Better organization of provider settings and capabilities
- Removed unwanted files from git tracking

## 📝 Technical Details

### Changed Files
- `lib/page/layout/sidebar.dart`: Added chat title editing UI
- `lib/page/layout/chat_page/chat_page.dart`: Fixed MCP content extraction
- `lib/page/layout/chat_page/input_area.dart`: Improved file upload handling
- `lib/provider/chat_provider.dart`: Added `updateChatTitle()` method with refresh fix
- `lib/provider/settings_provider.dart`: Added provider capability flags
- `lib/utils/file_upload_handler.dart`: New file for provider-aware file handling
- `lib/utils/file_content.dart`: Added text extraction utilities

### Dependencies
- Updated provider configurations with proper capability flags
- Added new provider logos (GLM, MiniMax, Moonshot)

## ⬆️ Upgrade Instructions

1. Download the latest release from GitHub Releases
2. Install the new version
3. Your existing chats and settings will be preserved

---

## 📋 Known Issues

None reported for this release

## 🙏 Acknowledgments

Thanks to all users who reported bugs and provided feedback for this release!
