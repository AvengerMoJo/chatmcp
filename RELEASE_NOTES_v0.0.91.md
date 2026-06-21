# ChatMCP v0.0.91

## Highlights
Patch release that fixes two regressions shipped in v0.0.90 plus a silent save failure. No new features — purely a stability cut before v0.0.92.

## Fixes

### OAuth (desktop)
- **PKCE `code_challenge` strips base64 `=` padding** per RFC 7636 §4.2. The desktop handler was emitting the challenge WITH padding while the web handler correctly stripped it. Strict OAuth servers (e.g. CF Workers MCP, including `https://slidr-mcp.pks-lc89.workers.dev/mcp`) store the challenge verbatim and reject padded values at token exchange with `invalid_grant`, so the desktop build could authenticate successfully in the browser but never receive a token. Web build was already correct.
- **Secure RNG for verifier / state.** `_generateRandomString` now uses `Random.secure()` instead of `DateTime.now().microsecondsSinceEpoch % 256` in a tight loop, which produced highly correlated bytes when the loop ran faster than the system clock resolution.
- **`_saveOAuthConfigForServer` verifies persistence.** The function now returns `bool`, re-reads `mcp_server.json` after writing, and reports `false` (→ orange snackbar in the UI) if the access_token didn't actually land. On desktop, `saveServers` swallows IO errors; without the verify step, the UI could show a green "Authenticated successfully" snackbar while the token never persisted. Same verification pattern applied to `authenticateServer` and `refreshServerToken`.

### Voice / TTS
- **`_extractQuotedSpokenText` regex anchored to start of content.** The pattern was `Input\s*text\s*:\s*["“](.+?)["”]` and matched anywhere in the input. If a model output or tool-result echo contained the literal phrase `Input text: "..."` mid-response, the entire quoted fragment was pulled out as the spoken text — overriding the actual reply. Symptom: "TTS starts talking about a story with nothing to do with the reply content". Common trigger: the voice summarizer occasionally wrapping its output in this format despite the prompt telling it not to. Fix: prepend `^\s*` so it only matches at the start (with optional leading whitespace).

## Tests
- 6 new in `test/utils/oauth_desktop_test.dart` — PKCE challenge format/determinism, secure RNG entropy.
- 12 new in `test/page/layout/chat_page/extract_quoted_spoken_text_test.dart` — anchoring cases (start of content, leading whitespace, case-insensitive, curly quotes, multi-line) plus regression coverage for the original bug (mid-content match, tool-result echo, narrative that mentions the phrase).
- **Total: 207 pass** (was 195 in v0.0.90).

## Upgrade notes
- No data migration, no config changes, no new dependencies.
- Users on v0.0.90 who hit "auth succeeded but token never saved" or "TTS speaks a random story" should pick up this build.

## Version
- App version: `0.0.91`
- Tag: `v0.0.91`
