# ChatMCP v0.0.88

## Focus
Stability release for protocol rendering, tool-call message flow, and voice output quality in complex turns.

## Included
- Tool-call / tool-result protocol normalization
- Structured tool-result rendering (collapsible blocks)
- Hard cap on oversized message payloads before LLM serialization
- Voice output gating to finalized answers only
- Final-answer extraction improvements to avoid speaking thinking/tool dump content
- Voice summary path improvements for concise spoken output

## Notes
This release is intended as a safer base after recent regressions and includes community-reporting support for voice edge cases.
