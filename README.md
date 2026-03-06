# Idle

A macOS terminal built on [Ghostty](https://ghostty.org) with an AI learning panel that generates quiz questions from your Claude Code sessions.

## Requirements

- macOS 14.0+
- Xcode 15+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.44.1+
- GhosttyKit (see below)

## Install

If you're running a prebuilt release (`.zip` or `.dmg`):

1. Drag **Idle.app** to `/Applications`.
2. On first launch, macOS will warn that the app is not notarized. Click **Cancel**.
3. Go to **System Settings > Privacy & Security**, scroll down, and click **Open Anyway** next to the Idle warning.
4. Idle will launch normally from now on.

## Building from Source

1. **Build GhosttyKit** — follow the instructions in `third_party/ghostty/` to produce the xcframework and resources:

   ```
   third_party/ghostty/zig-out/share/ghostty/   # shaders, keybinds, etc.
   third_party/ghostty/zig-out/share/terminfo/   # bundled terminfo
   ```

   Both directories are required. The build will fail if either is missing.

2. **Symlink the framework** (already checked in):

   ```
   GhosttyKit.xcframework -> third_party/ghostty/macos/GhosttyKit.xcframework
   ```

3. **Generate the Xcode project and build**:

   ```bash
   xcodegen generate
   open Idle.xcodeproj
   # Build & Run (Cmd+R)
   ```

## Learning Panel

The sidebar includes an AI-powered learning panel that generates interactive quiz questions from your Claude Code sessions.

- **Off by default.** Learning only activates when you explicitly toggle it on.
- **Uses your local Claude CLI.** When enabled, Idle calls `claude --print` using your local Claude installation and account. No separate API key is needed.
- **Sends recent terminal context.** The active session's recent terminal output is sent to Claude to generate relevant questions. Only the active session is read; other tabs are not accessed.
- **Token usage is visible.** Estimated input/output token counts are shown in the panel footer so you can track usage.

### How it works

1. Toggle the **Learning** switch in the sidebar. A consent dialog explains what data is sent.
2. Idle detects Claude Code by monitoring the terminal process title for the word "claude". Detection is heuristic and title-based — see limitations below.
3. When Claude is detected, the panel reads recent terminal output to classify the session phase (thinking vs. executing).
4. During thinking phases, context is sent to Claude to generate MCQ quiz questions about the concepts being discussed.
5. Questions appear one at a time with instant correct/wrong feedback and a running score.

### Known limitations

- **Title-based detection.** Claude Code is detected by checking if the terminal process title contains "claude". This is a heuristic — it won't detect Claude if the process title is customised or absent, and it may false-positive on other processes with "claude" in the title. A more robust approach would use direct process inspection, but title-based detection is simple and works for the common case.
- **Token estimates.** Input/output token counts shown in the footer are approximations (character count / 4), not actual API usage.

## Signing

Both configs are set in `project.yml` and emitted into the generated Xcode project:

- **Debug**: ad-hoc signed (`CODE_SIGN_IDENTITY = "-"`). Sufficient for local development.
- **Release**: `CODE_SIGN_IDENTITY = "Developer ID Application"`. To notarise, set your `DEVELOPMENT_TEAM` in Xcode or via an `xcconfig` overlay.

## Tests

```bash
xcodegen generate
xcodebuild -project Idle.xcodeproj -scheme IdleTests test
```

## License

Idle is licensed under **AGPL-3.0-or-later**. See [LICENSE](LICENSE).

Third-party licenses are listed in [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).
Ghostty (libghostty) is MIT-licensed.
