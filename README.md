# Idle (Beta)

A macOS terminal built on [Ghostty](https://ghostty.org) with an AI learning panel that generates quiz questions from your Claude Code sessions.

<img width="1305" height="842" alt="idle" src="https://github.com/user-attachments/assets/c177e7a4-9c0d-436c-bf94-33fe99e51bb6" />

## Download

Grab the latest DMG from [**GitHub Releases**](https://github.com/SyedSibtainRazvi/Idle/releases/latest). Requires **macOS 14.0+**.

1. Open the DMG and drag **Idle.app** to `/Applications`.
2. First launch: macOS will warn about notarization — go to **System Settings > Privacy & Security** and click **Open Anyway**.

## Features

- GPU-rendered terminal powered by Ghostty
- Tabbed sessions with split-view layout
- Theming, configurable fonts, opacity, and scrollback
- URL hover previews and click-to-open
- Background command-finished notifications
- **Idle Learning** — AI-powered quiz panel that generates questions while Claude Code works in your terminal. Uses your local `claude` CLI. Off by default.

## Building from Source

```bash
# 1. Build GhosttyKit (requires Zig 0.15.2)
cd third_party/ghostty
zig build --prefix zig-out -Doptimize=ReleaseFast -Demit-xcframework -Demit-macos-app=false
cd ../..

# 2. Generate and build
xcodegen generate
open Idle.xcodeproj   # Build & Run (Cmd+R)
```

## License

[AGPL-3.0-or-later](LICENSE). Ghostty (libghostty) is MIT-licensed. See [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).
