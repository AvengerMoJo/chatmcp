# Plan: Provider-Aware MCP Bundles & Runtime Model Discovery

**Date:** 2026-06-12
**Trigger:** GLM-5.1 launch + Z.AI MCP servers (Vision, Search, Reader, Zread)

## Problem

1. **MCP servers are decoupled from providers.** Z.AI ships 4 MCP servers with its Coding Plan, but users must discover and configure each manually with duplicate API keys.
2. **Model capabilities are opaque.** The `Model` class carries no metadata — context window, vision support, thinking mode are all unknown at runtime. The `models()` API calls return `List<String>` and **discard** all metadata from provider responses.
3. **No feedback loop.** When users find a public MCP server that should be bundled with a provider, there's no way to report it.

## Design Principles

- **Models: discover, don't hardcode.** Parse capability metadata from provider API responses. Only fall back to a lookup when APIs don't provide it.
- **MCP: bundle by provider.** Each provider declares its default MCP servers. Follow `awesome-mcp-servers` (88.9k stars) as the reference source for discovery. Pull manually or via script — no CI automation.
- **Users report gaps.** "Report Missing MCP" button in UI → pre-filled GitHub issue.

---

## Phase 1: Runtime Model Discovery

### 1.1 Enhance the `Model` class

Current `Model` (`lib/provider/settings_provider.dart` ~line 413):
```dart
class Model {
  final String name;
  final String label;
  final String providerId;
  final String apiStyle;
  final String icon;
  final String providerName;
  final int priority;
}
```

Add capability fields:
```dart
class Model {
  // ... existing fields ...
  final int? contextWindow;      // e.g. 200000
  final int? maxOutputTokens;    // e.g. 128000
  final bool supportsImages;     // true for vision models
  final bool supportsThinking;   // true for reasoning/thinking models
  final List<String> modalities; // ['text', 'image', 'audio', 'video']
}
```

### 1.2 Enhance `models()` to return metadata

Currently all `models()` methods return `List<String>` and discard API metadata. Change the return type to `List<ModelInfo>` where `ModelInfo` carries parsed metadata.

**What each API actually returns (already available, just not parsed):**

| Provider | Endpoint | Fields available but ignored |
|----------|----------|------------------------------|
| OpenAI-compatible | `GET /models` | `id`, `owned_by`, `created` |
| Z.AI (OpenAI-compat) | `GET /models` | Same as OpenAI — but model page docs have context/output info |
| Claude | `GET /models` | `id`, `display_name`, `created_at` |
| Gemini | `GET /models` | `name`, `displayName`, `description`, `inputTokenLimit`, `outputTokenLimit`, `supportedGenerationMethods` |
| Ollama | `GET /api/tags` | `name`, `details.parameter_size`, `details.families` |

**Enhancement approach:**

1. **Parse what the API gives us** — Gemini already returns `inputTokenLimit`/`outputTokenLimit`. Use it.
2. **Supplement from a lightweight lookup table** — only for fields APIs don't return (e.g., vision support). This table is small and infrequent — not a full model registry, just capability flags.
3. **Let users override** — provider settings already have `contextWindow` per-provider. Keep that as the override.

### 1.3 Add a `ModelCapabilities` lookup

A small JSON file `assets/model_capabilities.json` — only for fields that APIs don't return:

```json
{
  "glm-5.1": {"contextWindow": 200000, "maxOutput": 131072, "supportsThinking": true},
  "glm-5v-turbo": {"contextWindow": 128000, "supportsImages": true},
  "glm-4.6v": {"contextWindow": 128000, "supportsImages": true},
  "claude-opus-4-6": {"contextWindow": 200000, "maxOutput": 128000, "supportsImages": true, "supportsThinking": true},
  "claude-sonnet-4-6": {"contextWindow": 200000, "maxOutput": 128000, "supportsImages": true, "supportsThinking": true},
  "gpt-4.1": {"contextWindow": 1047576, "maxOutput": 32768, "supportsImages": true},
  "o4-mini": {"contextWindow": 200000, "maxOutput": 100000, "supportsThinking": true}
}
```

This is a **fallback**, not the primary source. The API response is primary. This file covers gaps.

### 1.4 Update `getAvailableModels()`

Currently at `settings_provider.dart` ~line 777. Enhance to:
1. Call `models()` on the provider client (or read cached result)
2. Parse metadata from response
3. Supplement from `model_capabilities.json` lookup
4. Return `Model` objects with full capability fields

### 1.5 Use capabilities at runtime

- `chat_page.dart`: Use `model.contextWindow` instead of provider-level `contextWindow` for token estimation
- `model_selector.dart`: Show badges (vision, thinking) in the model picker
- `file_upload_handler.dart`: Gate image uploads on `model.supportsImages` instead of hardcoded `providerId` checks

---

## Phase 2: Provider MCP Bundles

### 2.1 Create `assets/provider_mcp_bundles.json`

MCP servers linked to providers. Models are NOT included here — they're discovered at runtime.

```json
{
  "version": "2026-06-12",
  "source": "https://github.com/punkpeye/awesome-mcp-servers",
  "bundles": {
    "glm": {
      "providerId": "glm",
      "displayName": "GLM (Z.AI)",
      "mcpServers": {
        "zai-vision": {
          "type": "stdio",
          "command": "npx",
          "args": ["-y", "@z_ai/mcp-server"],
          "env": {"Z_AI_API_KEY": "${provider.apiKey}", "Z_AI_MODE": "ZAI"},
          "description": "Image analysis, video understanding, OCR, UI-to-code",
          "tools": ["ui_to_artifact", "extract_text_from_screenshot", "diagnose_error_screenshot", "understand_technical_diagram", "analyze_data_visualization", "ui_diff_check", "image_analysis", "video_analysis"],
          "source": "https://docs.z.ai/devpack/mcp/vision-mcp-server"
        },
        "zai-web-search": {
          "type": "streamable",
          "url": "https://api.z.ai/api/mcp/web_search_prime/mcp",
          "headers": {"Authorization": "Bearer ${provider.apiKey}"},
          "description": "Real-time web search",
          "tools": ["webSearchPrime"],
          "source": "https://docs.z.ai/devpack/mcp/search-mcp-server"
        },
        "zai-web-reader": {
          "type": "streamable",
          "url": "https://api.z.ai/api/mcp/web_reader/mcp",
          "headers": {"Authorization": "Bearer ${provider.apiKey}"},
          "description": "Full-page content extraction",
          "tools": ["webReader"],
          "source": "https://docs.z.ai/devpack/mcp/reader-mcp-server"
        },
        "zai-zread": {
          "type": "streamable",
          "url": "https://api.z.ai/api/mcp/zread/mcp",
          "headers": {"Authorization": "Bearer ${provider.apiKey}"},
          "description": "Open-source repo docs, structure, and code reading",
          "tools": ["search_doc", "get_repo_structure", "read_file"],
          "source": "https://docs.z.ai/devpack/mcp/zread-mcp-server"
        }
      }
    },
    "openai": {
      "providerId": "openai",
      "displayName": "OpenAI",
      "mcpServers": {}
    },
    "claude": {
      "providerId": "claude",
      "displayName": "Claude",
      "mcpServers": {}
    }
  }
}
```

### 2.2 `McpServerProvider` bundle support

Add to `lib/provider/mcp_server_provider.dart`:

- `loadBundleServers()` — reads `provider_mcp_bundles.json`
- `installBundleServer(String providerId, String serverId)` — installs a single bundled MCP server, resolving `${provider.apiKey}` from provider settings
- `installAllBundleServers(String providerId)` — installs all MCP servers for a provider
- `removeBundleServers(String providerId)` — removes all bundle-installed servers for a provider
- Track which servers are bundle-installed vs user-installed (add `source: 'bundle' | 'user'` field)

### 2.3 Auto-populate on provider enable

When a provider is enabled in settings:
1. Check if it has MCP bundle entries
2. If yes, auto-install the bundled MCP servers (with API key templating)
3. Show a notification: "Installed 4 Z.AI MCP servers"

When disabled:
1. Optionally remove bundle-installed servers (with confirmation)

### 2.4 MCP Server Settings UI updates

Add a **"Provider Bundled"** tab alongside All/Installed/InMemory:
- Shows servers grouped by provider
- Install/Remove buttons per server
- Badge showing which provider owns each server
- Link to source docs for each server

---

## Phase 3: MCP Discovery Script

### 3.1 `scripts/pull_mcp_registry.dart`

A Dart CLI script that:

1. **Fetches `awesome-mcp-servers` README** from GitHub raw
2. **Parses the markdown table** — extracts server name, description, URL, category
3. **Filters for provider-relevant servers** — matches by keyword (e.g., "z.ai", "zai", "glm", "openai", "anthropic")
4. **Cross-references with existing bundles** — identifies servers not yet in `provider_mcp_bundles.json`
5. **Outputs a report** — new servers found, potential provider matches, source URLs

This is a **manual discovery tool**, not an automated pipeline. Run it periodically to check for new servers.

### 3.2 Reference sources

| Source | URL | What |
|--------|-----|------|
| awesome-mcp-servers | `github.com/punkpeye/awesome-mcp-servers` | 88.9k stars, curated list, markdown tables |
| MCP Server Market | `github.com/chatmcpclient/mcp_server_market` | JSON manifest, already used by app |
| Z.AI Docs | `docs.z.ai/devpack/mcp/` | Official Z.AI MCP server docs |
| Glama MCP Servers | `glama.ai/mcp/servers` | Searchable MCP server directory |
| GitHub MCP Registry | `github.com/mcp` | GitHub's official MCP registry (new) |

### 3.3 `scripts/check_provider_updates.dart`

A companion script that:

1. **Queries provider `/models` APIs** — fetches current model lists
2. **Compares with `model_capabilities.json`** — identifies new models not in our lookup
3. **Fetches model docs pages** — for new models, pulls the doc page to extract capabilities
4. **Outputs suggested additions** to `model_capabilities.json`

Run manually when you hear about a new model launch.

---

## Phase 4: User-Driven MCP Reporting

### 4.1 "Report Missing MCP" button

In the MCP Server Settings UI, add a button that:

1. Opens a dialog: "Found an MCP server that should be bundled with a provider?"
2. User selects: Provider (dropdown), MCP Server Name, URL/Package, Why it should be included
3. Pre-fills a GitHub issue URL with all the structured data:

```
https://github.com/chatmcpclient/chatmcp/issues/new?title=MCP%20Bundle%20Request:%20{server_name}%20for%20{provider}&body=...
```

The body template:
```markdown
## MCP Bundle Request

**Provider:** {provider_name} ({provider_id})
**MCP Server:** {server_name}
**Source URL:** {server_url}
**Type:** stdio | sstreamable | sse
**Command/URL:** {command_or_url}
**Description:** {user_description}

### Why should this be bundled?
{user_reasoning}

### Reference
- Provider docs: {provider_docs_url}
- MCP server repo: {server_repo_url}
```

### 4.2 Quick-add from issue

When a maintainer reviews and approves a bundle request:
1. Add the server to `provider_mcp_bundles.json`
2. Bump the version
3. Users get the update via the pull script or manual update

---

## Implementation Steps

### Step 1: Model capabilities (Day 1-2)
- [ ] Add capability fields to `Model` class
- [ ] Create `assets/model_capabilities.json` with known models
- [ ] Enhance `models()` in OpenAI client to parse metadata where available
- [ ] Enhance `models()` in Gemini client to parse `inputTokenLimit`/`outputTokenLimit`
- [ ] Update `getAvailableModels()` to merge API metadata + lookup table
- [ ] Update `Model` serialization for persistence

### Step 2: MCP bundle data (Day 2)
- [ ] Create `assets/provider_mcp_bundles.json` with Z.AI bundles
- [ ] Add to `pubspec.yaml` assets
- [ ] Load bundles in `McpServerProvider`

### Step 3: MCP bundle install logic (Day 3-4)
- [ ] Add `installBundleServer()` with API key templating
- [ ] Add `installAllBundleServers()` / `removeBundleServers()`
- [ ] Track `source: 'bundle' | 'user'` on each server
- [ ] Auto-install on provider enable

### Step 4: UI updates (Day 4-5)
- [ ] Add "Provider Bundled" tab in MCP server settings
- [ ] Show capability badges in model selector (vision, thinking icons)
- [ ] Add "Report Missing MCP" button with issue template
- [ ] Use `model.contextWindow` in token estimation

### Step 5: Discovery scripts (Day 5-6)
- [ ] Create `scripts/pull_mcp_registry.dart` — parse awesome-mcp-servers
- [ ] Create `scripts/check_provider_updates.dart` — check provider APIs for new models
- [ ] Document how to run and interpret results

---

## Key Design Decisions

1. **API response is primary, lookup is fallback.** Don't hardcode model lists. Parse what the API gives us, supplement only what's missing.

2. **MCP bundles are provider-scoped.** A provider "owns" its MCP servers. When you enable Z.AI, you get Z.AI's MCP servers with your Z.AI API key — no duplicate configuration.

3. **No CI automation.** Discovery scripts are manual tools. The reference source is `awesome-mcp-servers`. Maintainers run the script, review output, update the bundle JSON.

4. **Users drive gap-filling.** "Report Missing MCP" is the feedback mechanism. Low friction, structured data, easy for maintainers to process.

5. **Backward compatible.** Existing user-configured MCP servers and model lists are preserved. Bundles add defaults on top. Capability lookup enriches, never overrides user settings.
