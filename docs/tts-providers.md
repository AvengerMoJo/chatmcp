# TTS Providers

ChatMCP supports four TTS (text-to-speech) backends for the voice console and chat→voice TTS path. Pick based on quality needs, deployment constraints, and cost.

| Provider | Type | Cost | Quality | Best for |
|---|---|---|---|---|
| CosyVoice2 | Self-hosted | Free | Good | Local dev, no network, privacy |
| MiMo (Xiaomi) | Cloud | Free tier | Good | Chinese voices, multilingual |
| OpenAI TTS | Cloud | Paid | Good | Existing OpenAI customers, low friction |
| ElevenLabs | Cloud | Paid (per char) | Best | Premium voices, voice cloning, low latency |

## ElevenLabs

ElevenLabs integration lives in `lib/services/tts_adapter.dart` as `ElevenLabsAdapter`. API reference: https://elevenlabs.io/docs/api-reference/text-to-speech/convert

### Setup

1. Sign up at https://elevenlabs.io and copy your API key from Profile → API Keys.
2. Pick a voice from the [Voice Library](https://elevenlabs.io/voice-library) and copy its Voice ID (e.g. `JBFqnCBsd6RMkjVDRZzb`).
3. In ChatMCP: Settings → Voice & TTS → TTS Provider → **ElevenLabs (Cloud)**.
4. Paste the API key and Voice ID. Pick a model (default: `eleven_multilingual_v2`).

### Models

- `eleven_multilingual_v2` — default, ~70 languages
- `eleven_turbo_v2_5` — lower latency, slight quality tradeoff
- `eleven_flash_v2_5` — fastest, lowest quality
- `eleven_monolingual_v1` — English only

### Regional endpoints

Set a custom Base URL in `GeneralSetting.elevenLabsBaseUrl` for:

- US: `https://api.us.elevenlabs.io`
- EU: `https://api.eu.residency.elevenlabs.io`
- Asia (Singapore): `https://api.sg.residency.elevenlabs.io`
- India: `https://api.in.residency.elevenlabs.io`

### Cost note

ElevenLabs bills per character generated. Free tier is ~10k chars/month. `voiceConsoleTtsProvider='elevenlabs'` + chat→voice auto-speak can rack up quickly on long sessions — disable the auto-speak switch (`voiceConsoleTtsEnabled=false`) if you're close to the limit.

### Implementation notes

- Output format is hardcoded to `mp3_44100_128` (the free-tier-supported default). WAV/PCM options require Pro tier and are deferred.
- No streaming endpoint support yet — single-shot POST per `speak()`. Latency for first-audio is ~300-800ms depending on model and text length.
- Voice settings (`stability`, `similarity_boost`, `style`, `speed`) are not exposed in v1 — defaults are used. Add via `GeneralSetting` if needed.
