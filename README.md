# WhisperMic

A tiny macOS menubar dictation app. Hold a hotkey, speak, and your words get transcribed by OpenAI and pasted at the cursor — anywhere you can type.

- **Hotkey**: `⌃ + ⌥ + ⌘ + Space` to start/stop recording
- **Paste-at-cursor**: transcript lands directly in whatever app you were using
- **Language**: auto-detect, or pick one (NL / EN / DE / FR / ES / TR)
- **Model**: OpenAI `gpt-transcribe`, switchable to `gpt-4o-transcribe` or `whisper-1`
- **Nothing gets lost**: audio is kept on disk until a transcript comes back, retry with `⌘R`
- Lives in the menu bar, no dock icon

## Requirements

- macOS 14+
- Xcode command line tools (`xcode-select --install`)
- An OpenAI API key

## Setup

```bash
# 1. Store your OpenAI key in the macOS Keychain
security add-generic-password -a claude-mcp -s OPENAI_API_KEY -w sk-your-key-here

# 2. Build and install
./install.sh
```

`install.sh` builds the app, code-signs it ad-hoc, copies it to `/Applications/`, and launches it.

## Grant Accessibility permission

Paste-at-cursor requires Accessibility access. On first launch macOS will prompt, or open:

**System Settings → Privacy & Security → Accessibility → add WhisperMic**

Without this, the transcript is still copied to the clipboard, you'll just have to paste it manually.

The grant does not survive a rebuild. WhisperMic is ad-hoc signed, and macOS ties the
Accessibility approval to the binary's cdhash, which changes every time you run
`install.sh`. The checkbox keeps looking enabled while the app is in fact denied, and
toggling it off and on does not help. Remove WhisperMic from the list with the `-` button
and add it back with `+` from `/Applications`. The menu bar icon tells you which state
you're in: a crossed-out mic means no access.

## How it works

1. Hotkey toggles recording (`AudioRecorder` → 16kHz mono WAV in `~/Library/Application Support/WhisperMic/Recordings`)
2. Recording keeps running 0.4s past the hotkey, so the last syllable isn't clipped
3. The WAV is POSTed to OpenAI's `/v1/audio/transcriptions` endpoint
4. The returned text is copied to the clipboard
5. WhisperMic re-activates the previously frontmost app and simulates `⌘V`

The API key is read from the Keychain at launch. It never lives in the binary, on disk as plaintext, or in this repo.

## Retrying a recording

The audio file is only marked done once a transcript actually comes back. No internet,
an API error, an empty result: the WAV stays on disk and the menu offers **Retry Last
Recording** (`⌘R`), plus a **Failed Recordings** submenu when more than one is waiting.
Up to 10 failed recordings are kept; the oldest drops off.

The most recent *successful* recording is kept too, until the next one replaces it. That
turns **Retranscribe Last** into the fix for a transcript that came back short: switch the
model to `whisper-1` and re-run the same audio.

**Discard Saved Audio** clears the folder; **Reveal Saved Audio in Finder** opens it.

## Choosing a model

| Model | When |
|---|---|
| `gpt-transcribe` | Default. OpenAI's recommended model since July 2026: lowest word error rate, $0.0045/min. |
| `gpt-4o-transcribe` | The previous default. Has a [documented tendency](https://community.openai.com/t/gpt-4o-transcribe-truncates-the-transcript/1148347) to cut the transcript short after a pause in speech. |
| `whisper-1` | Weaker on proper nouns, but the most resilient against dropped sentences. Use it to re-run a recording that came back too short. |

Every request is sent with `temperature=0` and, for the gpt-4o-class models, a verbatim
instruction prompt that counters the "condense several sentences into one" behaviour.
`whisper-1` gets no prompt, because it treats `prompt` as preceding transcript text to
continue from, not as an instruction.

## Project layout

```
Sources/WhisperMic/
  WhisperMicApp.swift       # AppDelegate, menu bar, settings
  AudioRecorder.swift       # AVAudioRecorder wrapper
  RecordingStore.swift      # Keeps audio on disk until it's transcribed
  TranscriptionService.swift# OpenAI API call, model selection
  KeychainHelper.swift      # Reads OPENAI_API_KEY from Keychain
  HotkeyManager.swift       # Global Carbon hotkey
  PasteHelper.swift         # Clipboard + simulated ⌘V via CGEvent
  ToastOverlay.swift        # Floating status pill
  LaunchAtLoginHelper.swift # SMAppService wrapper
  Info.plist                # Bundle metadata, mic usage string
scripts/generate-icon.swift # App icon generator
build.sh / install.sh       # Build + install to /Applications
```

## License

MIT — see [LICENSE](LICENSE).
