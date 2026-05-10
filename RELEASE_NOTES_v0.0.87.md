# ChatMCP v0.0.87

## Highlights
This release focuses on stability and usability for complex tool-calling + voice workflows.

## Fixes
- Protocol rendering
  - Tool results now render as structured collapsible blocks instead of raw text.
  - Unified protocol rendering path to reduce duplicate/incorrect bubble states.
- Message pipeline hardening
  - Normalized tool-turn protocol flow for better compatibility across providers.
  - Added hard payload caps before LLM serialization to prevent oversized tool results from breaking streaming requests.
- Voice improvements
  - Voice output now prefers finalized answer extraction over raw stream content.
  - Suppresses thinking/tool/protocol intermediate content from speech output.
  - Uses concise final-answer summaries for TTS instead of reading full long replies.
  - Improved fallback behavior to avoid silent turns.
- Chat UX
  - Input/send unlocks earlier after stream completion.
  - Voice console updated to compact bottom-right overlay to keep chat visible.

## Known Limitations
- Some edge cases with highly interleaved reasoning + tool output can still affect summary quality.
- Multi-window startup warning may still appear on macOS logs.

## Community Help Wanted
Please report voice/tooling edge cases using:
- `.github/ISSUE_TEMPLATE/voice-complex-tooling.md`

Include:
- model/provider, app version, exact prompt
- `openai message schema` lines
- `VoiceConsole chat->voice speak` logs
- payload dump path (`/tmp/chatmcp_openai_payload_*`) when available

## Version
- App version: `0.0.87`
- Tag: `v0.0.87`
