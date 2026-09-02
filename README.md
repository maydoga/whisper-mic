# Hulpje

A small macOS menu bar app that collects the conveniences worth having. It started as
a dictation tool; it is now a place to keep adding things.

| Feature | What it does | Shortcuts |
| --- | --- | --- |
| **Dictation** | Hold a hotkey, speak, get the transcript pasted at the cursor | `⌃⌥⌘Space` |
| **Windows** | Tile the focused window, a drop-in for the retired Spectacle | `⌘⌥←` `⌘⌥→` `⌘⌥↑` `⌘⌥↓` `⌘⌥F` `⌘⌥C` `⌘⌥Z` |
| **Menu Bar** | Collapse the third-party menu bar icons, like Ice or Dozer | click the chevron |

Every feature can be switched off from the menu, so it can live alongside the app it
replaces while you decide.

## Requirements

- macOS 14+
- Xcode command line tools (`xcode-select --install`)
- An OpenAI API key (dictation only)

## Setup

```bash
# 1. Store your OpenAI key in the macOS Keychain
security add-generic-password -a claude-mcp -s OPENAI_API_KEY -w sk-your-key-here

# 2. Build and install
./install.sh
```

`install.sh` builds the app, code-signs it ad-hoc, copies it to `/Applications/`, and launches it.

## Grant Accessibility permission

Everything except plain recording needs Accessibility: pasting at the cursor, moving
other apps' windows, watching the pointer for menu bar auto-hide. On first launch macOS
prompts, or open:

**System Settings → Privacy & Security → Accessibility → add Hulpje**

The grant does not survive a rebuild. Hulpje is ad-hoc signed, and macOS ties the
Accessibility approval to the binary's cdhash, which changes every time you run
`install.sh`. The checkbox keeps looking enabled while the app is in fact denied, and
toggling it off and on does not help. Remove Hulpje from the list with the `-` button
and add it back with `+` from `/Applications`. The menu bar icon tells you which state
you're in: a crossed-out mic means no access.

## Dictation

1. The hotkey toggles recording (`AudioRecorder` → 16kHz mono WAV in `~/Library/Application Support/Hulpje/Recordings`)
2. Recording keeps running 0.4s past the hotkey, so the last syllable isn't clipped
3. The WAV is POSTed to OpenAI's `/v1/audio/transcriptions` endpoint
4. The returned text is copied to the clipboard
5. Hulpje re-activates the previously frontmost app and simulates `⌘V`

The API key is read from the Keychain at launch. It never lives in the binary, on disk
as plaintext, or in this repo.

**Retrying.** The audio file is only marked done once a transcript actually comes back.
No internet, an API error, an empty result: the WAV stays on disk and the menu offers
**Retry Last Recording** (`⌘R`), plus a **Failed Recordings** submenu when more than one
is waiting. Up to 10 failed recordings are kept; the oldest drops off.

## Windows

Spectacle's bindings, kept identical so the muscle memory carries over.

| Shortcut | Action |
| --- | --- |
| `⌘⌥←` / `⌘⌥→` | Left / right half |
| `⌘⌥↑` / `⌘⌥↓` | Top / bottom half |
| `⌘⌥F` | Maximize |
| `⌘⌥C` | Centre, keeping the current size |
| `⌘⌥Z` | Restore to where the window was before Hulpje first moved it |

Windows are moved through the Accessibility API on whichever display holds most of the
window, respecting the dock and the menu bar. A window in native full screen is asked to
leave first.

**Conflicts.** macOS gives a global shortcut to one app. While Spectacle is still
running it holds these, and Hulpje's registration fails silently — so the menu marks
the ones that are taken and offers **Claim Shortcuts Again** once you quit Spectacle.
No restart needed.

## Menu Bar

Two extra status items appear: a thin divider and a chevron. Collapsing sets the
divider's width to something absurd, which pushes every status item left of it out of
the visible strip; expanding shrinks it back. No private API, the same trick Dozer and
Hidden Bar use.

**Arrange once.** ⌘-drag the icons you want hidden to the *left* of the divider, and the
ones that should always stay visible to its right. macOS remembers the positions.

Apple's own items (Control Center, Wi-Fi, battery, clock) sit in a region third-party
apps cannot reach and are never hidden. That is the difference with Ice, which uses
private CoreGraphics APIs to go further.

**Hide Automatically** collapses after a few seconds and reveals again when the pointer
reaches the menu bar. Off means the chevron does it on click.

## Adding a feature

Everything under `Sources/Hulpje/` that is not `Core/` is one feature. Conform to
`Feature`, which is four methods — claim your hotkeys in `start()`, release them in
`stop()`, add your items in `addMenuItems(to:)` — and append it to
`AppDelegate.features`. The enabled toggle, the UserDefaults key and the menu placement
come for free.

```
Sources/Hulpje/
  HulpjeApp.swift        status item, menu assembly
  Core/                  Feature protocol, hotkeys, Accessibility, Keychain, toast
  Dictation/             recording, transcription, paste
  Windows/               Accessibility-based tiling
  MenuBar/               status item collapsing
```
