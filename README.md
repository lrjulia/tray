# Tray

A clipboard history app for macOS, built from the Tray design system (https://claude.ai/artifact/Kevfa8PawV2KxSooowRZSr).
SwiftUI + AppKit, macOS 14 or later, no dependencies.

> **Status: first draft, not compiled yet.** The code was written and syntax-checked outside Xcode.
> Expect a handful of compile errors on the first build; they should be small (types, signatures).

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/lrjulia/tray/main/install.sh | sh
```

or with Homebrew:

```sh
brew tap lrjulia/tray https://github.com/lrjulia/tray
brew install --cask tray
```

Releases aren't signed with a Developer ID yet, so macOS may say the app is from an unidentified developer.
If it does: System Settings › Privacy & Security › Open Anyway. (Homebrew users can also run
`xattr -dr com.apple.quarantine /Applications/Tray.app`.)

## Releasing

Every push to `main` builds the app on GitHub Actions (download it from the run's artifacts).
To publish a release that the install commands pick up:

```sh
git tag v0.1.0 && git push origin v0.1.0
```

To sign and notarize, add these repository secrets and tag again: `MACOS_CERT_P12` (base64 of your
Developer ID Application .p12), `MACOS_CERT_PASSWORD`, `MACOS_SIGNING_IDENTITY` (e.g.
"Developer ID Application: Your Name (TEAMID)"), `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD`
(an app-specific password).

## Run it from source

**Quick (Terminal):**

```sh
cd ~/Developer/Tray
swift run
```

Good for trying the UI. macOS attributes permissions to Terminal in this mode, so pasting into other apps
asks for Accessibility for Terminal.

**As a real app (recommended):**

```sh
brew install xcodegen
cd ~/Developer/Tray
xcodegen          # creates Tray.xcodeproj from project.yml
open Tray.xcodeproj
```

Pick your team under Signing & Capabilities, then Run. Tray lives in the menu bar (no Dock icon).
Open it with **⌘⇧V**.

## Permissions

- **Clipboard:** Tray checks the pasteboard's change count every 0.5 s and reads only when it changed.
  On macOS versions with pasteboard privacy, allow Tray under Privacy & Security › Paste from Other Apps.
- **Accessibility:** needed to paste into the frontmost app (Tray simulates ⌘V) and for the Paste Stack
  (it watches for ⌘V). Without it, Return copies and you paste yourself.
- **Not sandboxed**, so it can't ship on the Mac App Store as is (simulated paste isn't allowed in the sandbox).
  Distribute with Developer ID + notarization.

## What's in it

| Area | Files |
| --- | --- |
| Entry, menus, menu-bar icon, hotkeys wiring | `main.swift`, `App/AppDelegate.swift`, `App/MainMenu.swift` |
| All state and actions | `App/AppModel.swift` |
| Design tokens (light/dark, 7 accent options, type, spacing, radii) | `Design/Tokens.swift` |
| Item, pinboard and settings models | `Model/` |
| Encrypted storage (AES-GCM, key in Keychain), retention, export/import | `Store/` |
| Clipboard watcher, paste engine, global hotkeys, secret detection, OCR, text transforms, kind detection | `Services/` |
| Floating window, List / Compact / Grid views, preview, details, editor, action bar, Actions (⌘K), rename, Quick Look, Paste Stack, Settings, onboarding | `UI/` |

## Shortcuts

| Action | Keys |
| --- | --- |
| Open / close window | ⌘⇧V |
| Paste selected / copy only / paste as plain text | Return / ⌘Return / ⌥Return |
| Paste item 1–9 | ⌘1 – ⌘9 |
| Select several | ⇧↑ / ⇧↓, or ⇧/⌘-click |
| Quick Look | Space (empty search) or ⌘Y |
| Edit text / save / cancel | ⌘E / ⌘S / Esc |
| Rename · Pin · Details · Actions · Reveal secret · Open link | ⌘R · ⌘P · ⌘I · ⌘K · ⌘U · ⌘B |
| Views: List / Compact / Grid | ⌥⌘1 / ⌥⌘2 / ⌥⌘3 |
| Previous / next board | ⌘[ / ⌘] |
| Delete item | ⌘⌫ |
| Paste next without opening | ⌃⇧V |
| Paste Stack | ⌘⇧C |
| Pause recording | ⌥⌘P |

## Known gaps

- Global shortcuts are fixed (no shortcut recorder in Settings yet).
- No app icon yet (the menu-bar icon is the SF Symbol `list.clipboard`).
- Link titles aren't fetched (Tray makes no network calls); links show their host.
- "Paste Stack" relies on a 0.5 s check between copies; copying and pasting faster than that can skip an item.
- No tests yet. The pure-logic parts (`ContentClassifier`, `SensitiveDetector`, `TextTransform`) are the easiest place to start.
