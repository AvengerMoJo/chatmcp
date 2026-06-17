# ChatMCP v0.0.90

## Highlights
This release ships **runtime model capability discovery** — the model selector and downstream features (image gating, thinking-mode hints, 1M+ context chips) now know what each model supports at runtime via [models.dev](https://models.dev), with a small bundled fallback for cold start. It also consolidates the voice / TTS work from v0.0.89 and adds OAuth + tool-call format hardening.

## New Features

### Model capabilities (runtime)
- **Layered capability resolver** — `ModelRegistry` (`lib/llm/model_registry.dart`) resolves `ModelCapabilities` from, in order: bundled `assets/model_capabilities.json` → 7‑day disk cache → live `models.dev` (5 s timeout) → `null`. Caller decides what to show.
- **`assets/providers.json`** — weekly auto-populated manifest with provider identity (`name`, `doc`, `npm`, `api`), modalities (union across models), max context window, and total model count. `openrouter` is included as a provider; its 336 model routes come from runtime, not the bundle.
- **Bundled snapshot reduced** — `assets/model_capabilities.json` ships **~82** most-recent active models per provider instead of 646. Capped at 5 per provider, sorted by `release_date`. `openrouter` (aggregator) skipped to avoid duplicating entries that already live under their actual providers.
- **Weekly CI workflow** — `.github/workflows/update-model-capabilities.yml` runs Mondays 09:00 UTC, opens a PR when either `assets/model_capabilities.json` or `assets/providers.json` changes, with per-file counts and a reviewer checklist.
- **Model selector UI** — small capability badges per row (image / reasoning / context) backed by the resolver.

### Tool calls
- **DeepSeek DSML format** parsing (`42b1027`).
- **Format A / B2 hybrid** function calls with parameter pairs (`3cbed18`).
- **Native API `toolCalls`** detection in `message.toolCalls` (not just XML content) (`26f5c2c`).
- Dropped tool results loop fix (`683a847`); consecutive assistant message merge in OpenAI serialization (`d09f642`).

### OAuth (MCP)
- **Login button** + OAuth config fields in the MCP server edit dialog (`aa3d853`).
- **Slack confidential client** support — distinguishes user token (xoxp) from bot token (xoxb); makes PKCE optional for confidential clients (`8007743`, `043be8f`, `4b864f2`).
- **Desktop auth** — login button shown on desktop, not web-only (`71483ba`); port 3000 released before rebind; `ScaffoldMessenger` guarded with `context.mounted`; `utf8.encode` callback to survive emoji without Latin‑1 crash (`fc5dd9a`, `46207c5`, `7be45a3`).

### Voice / TTS
- **Shared think-tag helper** (`5a2a899`) — used by TTS, summarizer, and the missing‑MCP reporter.
- **In-app missing-MCP reporter** — new `.github/ISSUE_TEMPLATE/mcp-missing.yml` paired with an in-app button to prefill provider + server-name.

## Fixes

### Voice / TTS
- **Slim system prompt for voice console** (`cf33100`) — background summarization path now skips tool definitions. Saves tokens per turn and prevents tool-call XML from leaking into TTS output.
- **Bound voice summarizer** (`df9e250`) + universal think-tag stripping.
- **DeepSeek think tags with attributes** stripped from TTS (`dd5eabb`); `reasoning_content` extracted for DeepSeek API (`11f22a6`).
- **`voice_output_rules` only injected during voice console session** (`d16d12f`); removed from LLM system prompt entirely (`83c4746`).
- **Sanitize summarized text before TTS speak** (`0e15372` / `e4fddc9` / `66df75d` revert / re-apply).
- **Voice Console icon** disabled when TTS disabled; tooltip fixed (`10607af`).

### Tool calls
- Accept empty arguments as `{}` in Format A (`358cece`); accept `</tool_call>` as closing tag in Format A regex (`c9aed0f`).
- Prevent double `</function>` and double-encoding of String arguments (`52f33c9`).

### MCP / OAuth
- SSE client includes env vars as headers, matching streamable client (`25f6fe8`).

## Build & CI
- **Streamable MCP integration tests** against real backend (`eaafa53`).
- **Weekly model + provider manifest** workflow (see Highlights).
- Flutter / Dart version pins unchanged.

## Tests
- 40 tests in `test/scripts/check_provider_updates_test.dart` covering parse, capability / provider diff, filter (status, cap, skip), modalities union, downgrade detection.
- New: `test/services/mcp_streamable_integration_test.dart`, `test/utils/think_tags_test.dart`, `test/utils/report_missing_mcp_test.dart`, `test/services/sentence_chunker_test.dart`, `test/services/streaming_speech_filter_test.dart`, `test/services/voice_classifier_test.dart`, `test/services/voice_response_extractor_test.dart`, `test/llm/deepseek_serialization_test.dart`, `test/llm/openai_message_serialization_test.dart`, `test/page/layout/chat_page/function_tag_regex_test.dart`, `test/page/layout/chat_page/message_protocol_test.dart`.

## Community
- Please report voice/tooling edge cases using `.github/ISSUE_TEMPLATE/voice-complex-tooling.md`.
- Missing MCP server? Use `.github/ISSUE_TEMPLATE/mcp-missing.yml` or the in-app "Report Missing MCP" button.

## Version
- App version: `0.0.90`
- Tag: `v0.0.90`
