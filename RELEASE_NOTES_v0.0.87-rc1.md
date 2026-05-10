# ChatMCP v0.0.87-rc1

## Summary
This release focuses on protocol-safe rendering and voice-console stability for complex tool-calling sessions.

## What Improved
- Fixed tool-result rendering to structured collapsible blocks (instead of raw text dumps).
- Added protocol normalization for tool turns to reduce malformed message chains.
- Added payload safeguards for oversized tool outputs before LLM serialization.
- Improved voice behavior:
  - suppresses intermediate think/function/tool content from speech output
  - extracts finalized answer text before TTS
  - summarizes final answer for concise speech
  - avoids blocking chat input after stream completion
- Updated voice console UI:
  - compact bottom-right floating panel
  - removed redundant large response text area to keep chat readable

## Known Issues
- In some mixed-content turns (heavy tool + reasoning + final answer), voice may still miss speaking or skip unexpectedly.
- Summary quality can vary by model and prompt behavior.
- Multi-window startup warning on macOS (`desktop_multi_window` invalid engine handle) still appears in logs.

## Community Help Requested
We need reproducible cases and patches for:
1. Voice not speaking on complex tool-calling turns.
2. Voice speaking wrong segment when model interleaves JSON/thinking/final text.
3. Any regressions in tool-call render flow.

## How To Report
Please include:
- Model/provider and app version
- Exact prompt used
- Whether tool calls were involved
- Logs around:
  - `openai message schema`
  - `VoiceConsole chat->voice speak ...`
  - TTS adapter logs
- If available, payload dump path from `/tmp/chatmcp_openai_payload_*`

## Candidate Commit Window
Includes fixes up to commit: `7465325` and voice extraction follow-up in current branch.
