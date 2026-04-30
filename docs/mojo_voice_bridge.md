# MoJo Voice Bridge — ChatMCP Integration Spec

## Overview

Add a parallel voice channel to ChatMCP that connects to a MoJo voice backend.
The voice channel and the existing text LLM channel run **simultaneously and independently**.

### Two-brain architecture

```
User speaks
     ↓
┌──────────────────────────┐    ┌───────────────────────────────┐
│   AUDIO BRAIN (MoJo)     │    │   TEXT BRAIN (ChatMCP LLM)    │
│                          │    │                               │
│  Fast, small model       │    │  Full LLM + MCP tools         │
│  Probes for clarity      │◄──►│  Deep execution               │
│  Engages user            │    │  Rich text output in chat     │
│  Presents results simply │    │  Pushes summaries to audio    │
└──────────────────────────┘    └───────────────────────────────┘
         ↕ talking to user                ↕ working in background
         └──────── MoJo bridge API ───────┘
```

The audio brain keeps the user engaged and probes for missing context while
the text brain executes. Neither waits on the other.

---

## MoJo Voice Backend API

Base URL configured in settings as `MOJO_VOICE_URL` (e.g. `http://192.168.2.248:9089`).

### Session lifecycle

```
POST /voice/session
  → { "session_id": "uuid" }

DELETE /voice/session/{session_id}
  → 200 OK
```

### Audio query (existing endpoint, now session-aware)

```
POST /voice/query/{session_id}
  Body: {
    "audio_base64": "<base64 wav>",
    "mcp_mode": "search_memory",   // optional
    "role_id": "assistant"         // optional
  }
  Response: {
    "transcript": "what the user said",
    "reply_text": "audio brain's reply text",
    "reply_audio_base64": "<base64 wav>",
    "reply_audio_format": "wav",
    "session_id": "uuid"
  }
```

### Text brain → audio brain (push results)

```
POST /voice/push/{session_id}
  Body: {
    "type": "progress" | "result" | "question",
    "summary": "2-3 sentence plain text summary, no markdown"
  }
  Response: { "queued": true }
```

### Poll for pending audio (ChatMCP → MoJo)

```
GET /voice/pending/{session_id}
  Response (nothing pending): { "pending": false }
  Response (audio ready):     {
    "pending": true,
    "type": "progress" | "result" | "question",
    "reply_text": "what the audio brain will say",
    "reply_audio_base64": "<base64 wav>",
    "reply_audio_format": "wav"
  }
```

### Poll for context updates (audio brain → text brain)

```
GET /voice/context/{session_id}
  Response (no update): { "update": false }
  Response (new context): {
    "update": true,
    "type": "clarification" | "refinement",
    "content": "user clarified: timeframe is Q3 2025",
    "context_version": 2
  }
```

---

## What ChatMCP needs to implement

### 1. Settings

Add to general settings:
- `mojoVoiceUrl` — string, URL of the MoJo voice backend (e.g. `http://192.168.2.248:9089`)
- `mojoVoiceEnabled` — bool, toggle to enable/disable the MoJo voice channel

### 2. MojoVoiceService  (`lib/services/mojo_voice_service.dart`)

Stateful service managing one session per conversation. Responsibilities:
- `createSession()` → POST /voice/session, store session_id
- `closeSession()` → DELETE /voice/session/{id}
- `queryAudio(Uint8List wavBytes)` → base64 encode → POST /voice/query/{session_id} → return reply WAV bytes + transcript
- `pushResult(String summary, String type)` → POST /voice/push/{session_id}
- `pollPending()` → GET /voice/pending/{session_id} → return WAV bytes or null
- `pollContext()` → GET /voice/context/{session_id} → return context update or null

### 3. Audio recording  

The existing mic button uses `speech_to_text` which returns text only — no raw audio bytes.
A second recording path is needed for the MoJo channel:

- Add `record` Flutter package for raw PCM/WAV capture
- Add `audioplayers` or `just_audio` for WAV playback
- macOS: add microphone entitlement to `macos/Runner/Release.entitlements` and `DebugProfile.entitlements`:
  ```xml
  <key>com.apple.security.device.audio-input</key>
  <true/>
  ```

### 4. New MoJo mic button  (`lib/page/layout/chat_page/input_area.dart`)

Add a second mic button alongside the existing one. Visually distinct (e.g. filled vs outlined, or different color).

Behaviour:
- **Press**: start recording raw audio (via `record` package)
- **Release**: stop recording → send to MoJo → play reply audio
- **While recording**: show pulsing indicator
- **While waiting for reply**: show spinner on button
- The existing `speech_to_text` mic button is unchanged

The MoJo mic button is only shown when `mojoVoiceEnabled` is true and `mojoVoiceUrl` is configured.

### 5. Session lifecycle in chat  (`lib/page/layout/chat_page/chat_page.dart`)

- On conversation open/start: call `MojoVoiceService.createSession()`
- On conversation close/switch: call `MojoVoiceService.closeSession()`
- Pass `MojoVoiceService` instance down to `InputArea`

### 6. Text brain → audio brain bridge  (`lib/provider/chat_provider.dart`)

After each LLM response completes:
1. Take the final assistant message text
2. Send a small summarization prompt to the LLM: *"Summarize the following in 2-3 plain spoken sentences with no markdown, tables, or lists. Focus on the most important insight:"*
3. POST the summary to `/voice/push/{session_id}` with `type: "result"`

If the LLM response is trivially short (< 100 chars) or is a clarifying question, skip the push.

### 7. Background poller  (`lib/services/mojo_voice_service.dart`)

Start polling when a session is active:

```
every 2 seconds:
  pollPending() → if audio: play WAV bytes via audioplayers
  pollContext() → if context update: call onContextUpdate callback
```

Stop polling when session is closed or conversation switches.

### 8. Context feedback to text brain

When `pollContext()` returns a context update:
- Append a system-role message to the current conversation context:
  `"[Voice context update] {content}"`
- If the text brain is currently idle (not composing), optionally re-trigger a follow-up LLM call with the updated context
- Show a subtle indicator in the chat UI that context was updated (e.g. small info chip)

---

## Audio playback

`_playAudio(Uint8List wavBytes)`:
1. Write bytes to a temp file (`getTemporaryDirectory()/mojo_reply_{timestamp}.wav`)
2. Play via `audioplayers` AudioPlayer
3. Queue if already playing (do not cut off in-progress audio)

---

## Data flow diagram

```
User presses MoJo mic
  → record raw WAV
  → MojoVoiceService.queryAudio(wavBytes)
      → POST /voice/query/{session_id}
      → MoJo: STT → audio brain LLM → TTS
      → reply_audio_base64 + transcript
  → play reply WAV
  → (transcript shown as subtle label, not chat message)

Text LLM finishes streaming
  → summarize response
  → MojoVoiceService.pushResult(summary, "result")
      → POST /voice/push/{session_id}
      → MoJo queues audio synthesis

Background poller fires (2s)
  → GET /voice/pending/{session_id}
  → if pending: play proactive audio reply
  → GET /voice/context/{session_id}
  → if context: inject into text brain conversation
```

---

## Files to create / modify

| File | Action | Notes |
|------|--------|-------|
| `lib/services/mojo_voice_service.dart` | Create | Session mgmt, HTTP calls, poller |
| `lib/page/layout/chat_page/input_area.dart` | Modify | Add MoJo mic button, wire recording |
| `lib/page/layout/chat_page/chat_page.dart` | Modify | Session lifecycle |
| `lib/provider/chat_provider.dart` | Modify | Push summary after LLM complete |
| `lib/page/setting/general_setting.dart` | Modify | Add mojoVoiceUrl + mojoVoiceEnabled |
| `lib/provider/settings_provider.dart` | Modify | Add new settings fields |
| `pubspec.yaml` | Modify | Add `record`, `audioplayers` packages |
| `macos/Runner/*.entitlements` | Modify | Add audio-input entitlement |

---

## Out of scope for this spec

- The MoJo voice backend implementation (handled separately in mojo-voice module)
- Authentication between ChatMCP and MoJo backend
- Streaming audio (chunked WAV) — start with complete WAV round-trip
- Mobile-specific audio permission handling (Android/iOS) — macOS/desktop first
