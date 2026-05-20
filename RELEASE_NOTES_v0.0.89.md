# ChatMCP v0.0.89

## Highlights
This release restores and supersedes the v0.0.87 stability fixes, merged with new voice/TTS features from the `wip_tts_integration` branch.

## Fixes (from v0.0.87)
- **Protocol rendering**: Tool results now render as structured collapsible blocks instead of raw text. Unified protocol rendering path to reduce duplicate/incorrect bubble states.
- **Message pipeline hardening**: Normalized tool-turn protocol flow for better compatibility across providers. Added hard payload caps before LLM serialization to prevent oversized tool results from breaking streaming requests.
- **Voice output improvements**: Voice now speaks only finalized answers — no more thinking dumps or tool spam. Aggressive TTS filtering suppresses intermediate content. Uses concise final-answer summaries instead of reading full long replies.
- **Tool call fixes**: Prevent assistant merge of tool XML messages. Deduplicate tool calls to prevent model echoing. Ensure toolCalls visible on function-only responses.

## New Features
- **Voice Console**: New dialog-based voice interface with TTS queue management
- **MoJo Voice**: Two-brain voice architecture with local speech-to-speech engine
- **Buffered Summary Speaker**: Natural TTS pacing with sentence chunking
- **TTS Adapters**: CosyVoice2, Xiaomi MiMo-V2.5-TTS, OpenAI TTS support
- **Plugin System**: Runtime plugin manager with MCP server adapter
- **Context Manager**: Better LLM message handling and summarization

## Build & CI
- **macOS CI**: Added Codemagic macOS debug workflow with speech_to_text SwiftPM patch
- **speech_to_text**: Bundled patched version as path override (macOS target 10.15+) replacing inline sed patches
- **Linux CI**: Updated dependency installation for builds

## Voice
- **Stateless S2S**: Support for stateless /voice/s2s backend endpoint
- **Session dedup**: Deduplicated MoJo voice init/session calls and support for non-/voice endpoints
- **UI fix**: Keep MoJo voice icon visible based on settings instead of service instance state

## Community
- Please report voice/tooling edge cases using `.github/ISSUE_TEMPLATE/voice-complex-tooling.md`

## Version
- App version: `0.0.89`
- Tag: `v0.0.89`