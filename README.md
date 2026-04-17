# WhisperMic

A tiny macOS menubar dictation app. Hold a hotkey, speak, and your words get transcribed by OpenAI and pasted at the cursor — anywhere you can type.

- **Hotkey**: `⌃ + ⌥ + ⌘ + Space` to start/stop recording
- **Paste-at-cursor**: transcript lands directly in whatever app you were using
- **Language**: auto-detect, or pick one (NL / EN / DE / FR / ES / TR)
- **Model**: OpenAI `gpt-4o-transcribe`
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

Without this, the transcript is still copied to the clipboard — you'll just have to paste it manually.

## How it works

1. Hotkey toggles recording (`AudioRecorder` → 16kHz mono WAV in `/tmp`)
2. On stop, the WAV is POSTed to OpenAI's `/v1/audio/transcriptions` endpoint
3. The returned text is copied to the clipboard
4. WhisperMic re-activates the previously frontmost app and simulates `⌘V`

The API key is read from the Keychain at launch. It never lives in the binary, on disk as plaintext, or in this repo.

## Project layout

```
Sources/WhisperMic/
  WhisperMicApp.swift       # AppDelegate, menu bar, settings
  AudioRecorder.swift       # AVAudioRecorder wrapper
  TranscriptionService.swift# OpenAI API call
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
