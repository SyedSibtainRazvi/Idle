import AppKit

extension Notification.Name {
  static let idleThemeDidChange = Notification.Name("IdleThemeDidChange")
}

struct TerminalTheme {
  let name: String
  let background: String
  let foreground: String
  let cursor: String
  let cursorText: String
  let selectionBg: String
  let selectionFg: String
  /// 16-color ANSI palette (indices 0-15)
  let palette: [String]

  func toGhosttyConfig() -> String {
    var lines: [String] = []
    lines.append("background = \(background)")
    lines.append("foreground = \(foreground)")
    lines.append("cursor-color = \(cursor)")
    lines.append("cursor-text = \(cursorText)")
    lines.append("selection-background = \(selectionBg)")
    lines.append("selection-foreground = \(selectionFg)")
    for (i, color) in palette.enumerated() {
      lines.append("palette = \(i)=\(color)")
    }
    return lines.joined(separator: "\n") + "\n"
  }
}

final class ThemeManager {
  static let shared = ThemeManager()

  private static let selectedThemeKey = "IdleSelectedTheme"

  let themes: [TerminalTheme] = [
    // Idle Dark (default — One Dark inspired)
    TerminalTheme(
      name: "Idle Dark",
      background: "#111113", foreground: "#e0e0e0",
      cursor: "#668fff", cursorText: "#111113",
      selectionBg: "#668fff", selectionFg: "#111113",
      palette: [
        "#111113", "#e06c75", "#98c379", "#e5c07b",
        "#668fff", "#c678dd", "#56b6c2", "#abb2bf",
        "#5c6370", "#e06c75", "#98c379", "#e5c07b",
        "#668fff", "#c678dd", "#56b6c2", "#f0f0f0",
      ]
    ),
    // Catppuccin Mocha
    TerminalTheme(
      name: "Catppuccin Mocha",
      background: "#1e1e2e", foreground: "#cdd6f4",
      cursor: "#f5e0dc", cursorText: "#1e1e2e",
      selectionBg: "#585b70", selectionFg: "#cdd6f4",
      palette: [
        "#45475a", "#f38ba8", "#a6e3a1", "#f9e2af",
        "#89b4fa", "#f5c2e7", "#94e2d5", "#bac2de",
        "#585b70", "#f38ba8", "#a6e3a1", "#f9e2af",
        "#89b4fa", "#f5c2e7", "#94e2d5", "#a6adc8",
      ]
    ),
    // Dracula
    TerminalTheme(
      name: "Dracula",
      background: "#282a36", foreground: "#f8f8f2",
      cursor: "#f8f8f2", cursorText: "#282a36",
      selectionBg: "#44475a", selectionFg: "#f8f8f2",
      palette: [
        "#21222c", "#ff5555", "#50fa7b", "#f1fa8c",
        "#bd93f9", "#ff79c6", "#8be9fd", "#f8f8f2",
        "#6272a4", "#ff6e6e", "#69ff94", "#ffffa5",
        "#d6acff", "#ff92df", "#a4ffff", "#ffffff",
      ]
    ),
    // Tokyo Night
    TerminalTheme(
      name: "Tokyo Night",
      background: "#1a1b26", foreground: "#c0caf5",
      cursor: "#c0caf5", cursorText: "#1a1b26",
      selectionBg: "#33467c", selectionFg: "#c0caf5",
      palette: [
        "#15161e", "#f7768e", "#9ece6a", "#e0af68",
        "#7aa2f7", "#bb9af7", "#7dcfff", "#a9b1d6",
        "#414868", "#f7768e", "#9ece6a", "#e0af68",
        "#7aa2f7", "#bb9af7", "#7dcfff", "#c0caf5",
      ]
    ),
    // Gruvbox Dark
    TerminalTheme(
      name: "Gruvbox Dark",
      background: "#282828", foreground: "#ebdbb2",
      cursor: "#ebdbb2", cursorText: "#282828",
      selectionBg: "#504945", selectionFg: "#ebdbb2",
      palette: [
        "#282828", "#cc241d", "#98971a", "#d79921",
        "#458588", "#b16286", "#689d6a", "#a89984",
        "#928374", "#fb4934", "#b8bb26", "#fabd2f",
        "#83a598", "#d3869b", "#8ec07c", "#ebdbb2",
      ]
    ),
    // Solarized Dark
    TerminalTheme(
      name: "Solarized Dark",
      background: "#002b36", foreground: "#839496",
      cursor: "#839496", cursorText: "#002b36",
      selectionBg: "#073642", selectionFg: "#93a1a1",
      palette: [
        "#073642", "#dc322f", "#859900", "#b58900",
        "#268bd2", "#d33682", "#2aa198", "#eee8d5",
        "#002b36", "#cb4b16", "#586e75", "#657b83",
        "#839496", "#6c71c4", "#93a1a1", "#fdf6e3",
      ]
    ),
    // Nord
    TerminalTheme(
      name: "Nord",
      background: "#2e3440", foreground: "#d8dee9",
      cursor: "#d8dee9", cursorText: "#2e3440",
      selectionBg: "#434c5e", selectionFg: "#d8dee9",
      palette: [
        "#3b4252", "#bf616a", "#a3be8c", "#ebcb8b",
        "#81a1c1", "#b48ead", "#88c0d0", "#e5e9f0",
        "#4c566a", "#bf616a", "#a3be8c", "#ebcb8b",
        "#81a1c1", "#b48ead", "#8fbcbb", "#eceff4",
      ]
    ),
    // Rose Pine
    TerminalTheme(
      name: "Rosé Pine",
      background: "#191724", foreground: "#e0def4",
      cursor: "#524f67", cursorText: "#e0def4",
      selectionBg: "#403d52", selectionFg: "#e0def4",
      palette: [
        "#26233a", "#eb6f92", "#31748f", "#f6c177",
        "#9ccfd8", "#c4a7e7", "#ebbcba", "#e0def4",
        "#6e6a86", "#eb6f92", "#31748f", "#f6c177",
        "#9ccfd8", "#c4a7e7", "#ebbcba", "#e0def4",
      ]
    ),
    // Monokai Pro
    TerminalTheme(
      name: "Monokai Pro",
      background: "#2d2a2e", foreground: "#fcfcfa",
      cursor: "#fcfcfa", cursorText: "#2d2a2e",
      selectionBg: "#403e41", selectionFg: "#fcfcfa",
      palette: [
        "#403e41", "#ff6188", "#a9dc76", "#ffd866",
        "#fc9867", "#ab9df2", "#78dce8", "#fcfcfa",
        "#727072", "#ff6188", "#a9dc76", "#ffd866",
        "#fc9867", "#ab9df2", "#78dce8", "#fcfcfa",
      ]
    ),
    // Everforest Dark
    TerminalTheme(
      name: "Everforest",
      background: "#2d353b", foreground: "#d3c6aa",
      cursor: "#d3c6aa", cursorText: "#2d353b",
      selectionBg: "#475258", selectionFg: "#d3c6aa",
      palette: [
        "#475258", "#e67e80", "#a7c080", "#dbbc7f",
        "#7fbbb3", "#d699b6", "#83c092", "#d3c6aa",
        "#859289", "#e67e80", "#a7c080", "#dbbc7f",
        "#7fbbb3", "#d699b6", "#83c092", "#d3c6aa",
      ]
    ),
  ]

  private(set) var selectedThemeName: String

  private init() {
    selectedThemeName = UserDefaults.standard.string(forKey: Self.selectedThemeKey) ?? "Idle Dark"
  }

  var selectedTheme: TerminalTheme {
    themes.first(where: { $0.name == selectedThemeName }) ?? themes[0]
  }

  func applyTheme(_ theme: TerminalTheme) {
    selectedThemeName = theme.name
    UserDefaults.standard.set(theme.name, forKey: Self.selectedThemeKey)

    // Update app chrome colors
    updateIdleTheme(from: theme)

    guard let app = GhosttyRuntime.shared.app else { return }

    // Write theme to temp file, load into a new config, and apply
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("idle-theme.conf")
    do {
      try theme.toGhosttyConfig().write(to: tempURL, atomically: true, encoding: .utf8)
    } catch {
      NSLog("[Idle] Failed to write theme config: %@", error.localizedDescription)
      return
    }

    guard let newCfg = ghostty_config_new() else { return }
    tempURL.path.withCString { ghostty_config_load_file(newCfg, $0) }
    ghostty_config_finalize(newCfg)
    ghostty_app_update_config(app, newCfg)
    ghostty_config_free(newCfg)

    try? FileManager.default.removeItem(at: tempURL)

    NotificationCenter.default.post(name: .idleThemeDidChange, object: nil)
  }

  /// Apply the persisted theme. Called once at startup after surfaces are created.
  func applyPersistedTheme() {
    let theme = selectedTheme
    updateIdleTheme(from: theme)
    guard theme.name != "Idle Dark" else { return }
    applyTheme(theme)
  }

  private func updateIdleTheme(from theme: TerminalTheme) {
    let bg = Self.colorFromHex(theme.background)
    let fg = Self.colorFromHex(theme.foreground)
    let accent = Self.colorFromHex(theme.palette[4]) // blue
    IdleTheme.update(background: bg, foreground: fg, accent: accent)
  }

  static func colorFromHex(_ hex: String) -> NSColor {
    let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    var rgb: UInt64 = 0
    Scanner(string: hex).scanHexInt64(&rgb)
    let r = CGFloat((rgb >> 16) & 0xFF) / 255
    let g = CGFloat((rgb >> 8) & 0xFF) / 255
    let b = CGFloat(rgb & 0xFF) / 255
    return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
  }
}
