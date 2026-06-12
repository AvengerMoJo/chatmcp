# AI Context — `chatmcp`

Quick-stake for AI sessions working in this repo. Re-discover with `pwd`, `ls`, `git status`, `cat pubspec.yaml`, and `ls docs/`. This file is a hint, not a source of truth.

## Project
- **Name:** chatmcp — cross-platform AI chat client (macOS / Windows / Linux / iOS / Android / Web)
- **Framework:** Flutter (Dart SDK ^3.8.1)
- **State mgmt:** `provider`
- **Branch / version:** active branch varies (e.g. `v0.0.90`); `pubspec.yaml` is the version source of truth
- **Locales:** en, zh, de, tr (ARB → `flutter gen-l10n`)

## Core domains
- **LLM clients** (`lib/llm/`): openai, claude, claude_code, deepseek, gemini, copilot, ollama, foundry
- **Model registry** (`lib/llm/model_registry.dart`): singleton, resolves `ModelCapabilities` from bundled → 7-day disk cache → models.dev live fetch (5s timeout, never throws)
- **MCP** (`lib/mcp/`, `lib/plugin/`): stdio, SSE, streamable HTTP, in-memory, plugin adapters
- **Voice — ChatMCP side** (`lib/services/mojo_voice_service.dart`, `voice/`): two-brain bridge to a MoJo backend
- **TTS** (`lib/services/tts_adapter.dart`, `glm4voice_local_service.dart`): CosyVoice2, MiMo-V2.5, OpenAI TTS, GLM4Voice local
- **Storage** (`lib/dao/`, `lib/repository/`): `sqflite` (mobile/desktop) + `sqflite_common_ffi_web` (web)
- **LAN sync** (`lib/services/network_sync_service.dart`, `lib/utils/`): `shelf` server, `qr_flutter`, `mobile_scanner`
- **Plugin runtime** (`lib/plugin/`): in-process plugin manager with MCP server adapter

## Path overrides
- `third_party/speech_to_text_patched` — patched `speech_to_text` (macOS SwiftPM target fix)
- `third_party/pdf_render_patched` — patched `pdf_render`

## Build / dev
- `make lan` — regenerate l10n
- `make clean` — `flutter clean && flutter pub get`
- `make android-apk` / `make android-aab` / `make release-android`
- `make build-icon` — regenerate launcher icons
- CI: Codemagic (macOS), GitHub Actions

## Doc anchors
- `docs/mojo_voice_bridge.md` — two-brain voice spec + API contract (sessions, query, push, pending, context)
- `docs/pagination_config.dart` — pagination config (lives under `docs/`)
- `docs/android-signing.md` — keystore / signing flow
- `docs/mcp_oauth_servers.md` — OAuth for MCP servers
- `RELEASE_NOTES_v0.0.*.md` — shipped scope per release

## Voice rules (project-specific, enforced in code)
- TTS must only speak **finalized** answers — no thinking dumps, no tool spam
- `voice_output_rules` system prompt is injected **only** during an active voice console session
- Strip provider-specific think/reasoning tags (e.g. DeepSeek `<think>…</think>`, with or without attributes) from TTS input

## Conventions
- No comments unless asked
- Don't fix unrelated bugs you find — mention them, move on
- Match existing style; don't add formatters/linters the repo doesn't have
- Use `provider` (not Riverpod/Bloc) for new state

## Memory split (for the AI layer above this repo)
- **Local (this file / repo):** paths, versions, build commands, project conventions
- **Global (MoJoAssistant):** cross-project preferences, recurring gotchas, stable policies
- Promote a fact to global only if it is **stable across repos** and worth remembering next session

## Model capabilities
- `Model` (`lib/llm/model.dart`) carries optional `ModelCapabilities` (contextWindow, maxOutputTokens, supportsImages, supportsThinking, inputModalities, outputModalities, family, status, source)
- `ModelRegistry.instance.enrich(name, providerId: ...)` is the single entry point; do not reimplement caching
- Cache TTL: **7 days** (weekly). Override with `cacheDirectoryOverride` in tests
- Source labels: `bundled` | `models.dev` | `unknown`
- Bundled fallback lives at `assets/model_capabilities.json`
