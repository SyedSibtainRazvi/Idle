import AppKit

extension Notification.Name {
  static let idleSettingsDidChange = Notification.Name("IdleSettingsDidChange")
}

enum CursorStyle: String, CaseIterable {
  case block = "block"
  case bar = "bar"
  case underline = "underline"

  var displayName: String {
    switch self {
    case .block: return "Block"
    case .bar: return "Beam"
    case .underline: return "Underline"
    }
  }
}

// MARK: - Unified config composer

/// Composes a single Ghostty config from both theme and settings,
/// preventing partial configs from overwriting each other.
enum IdleConfigComposer {
  static func applyAll() {
    guard let app = GhosttyRuntime.shared.app else { return }

    let themeConfig = ThemeManager.shared.selectedTheme.toGhosttyConfig()
    let settingsConfig = SettingsManager.shared.configString()
    let combined = themeConfig + settingsConfig

    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("idle-config.conf")
    do {
      try combined.write(to: tempURL, atomically: true, encoding: .utf8)
    } catch {
      NSLog("[Idle] Failed to write combined config: %@", error.localizedDescription)
      return
    }

    guard let newCfg = ghostty_config_new() else { return }
    tempURL.path.withCString { ghostty_config_load_file(newCfg, $0) }
    ghostty_config_finalize(newCfg)
    ghostty_app_update_config(app, newCfg)
    ghostty_config_free(newCfg)

    try? FileManager.default.removeItem(at: tempURL)
  }
}

// MARK: - SettingsManager

final class SettingsManager {
  static let shared = SettingsManager()

  private static let fontFamilyKey = "IdleFontFamily"
  private static let fontSizeKey = "IdleFontSize"
  private static let cursorStyleKey = "IdleCursorStyle"
  private static let cursorBlinkKey = "IdleCursorBlink"
  private static let scrollbackLinesKey = "IdleScrollbackLines"
  private static let backgroundOpacityKey = "IdleBackgroundOpacity"

  private(set) var fontFamily: String
  private(set) var fontSize: Double
  private(set) var cursorStyle: CursorStyle
  private(set) var cursorBlink: Bool
  private(set) var scrollbackLines: Int
  private(set) var backgroundOpacity: Double

  private init() {
    fontFamily = UserDefaults.standard.string(forKey: Self.fontFamilyKey) ?? ""
    fontSize = UserDefaults.standard.object(forKey: Self.fontSizeKey) as? Double ?? 14.0
    cursorStyle = CursorStyle(rawValue: UserDefaults.standard.string(forKey: Self.cursorStyleKey) ?? "block") ?? .block
    cursorBlink = UserDefaults.standard.object(forKey: Self.cursorBlinkKey) as? Bool ?? true
    scrollbackLines = UserDefaults.standard.object(forKey: Self.scrollbackLinesKey) as? Int ?? 10_000_000
    backgroundOpacity = UserDefaults.standard.object(forKey: Self.backgroundOpacityKey) as? Double ?? 1.0
  }

  /// Returns the settings portion of the Ghostty config (no theme keys).
  func configString() -> String {
    var lines: [String] = []
    if !fontFamily.isEmpty {
      lines.append("font-family = \"\(fontFamily)\"")
    }
    lines.append("font-size = \(Int(fontSize))")
    lines.append("cursor-style = \(cursorStyle.rawValue)")
    lines.append("cursor-style-blink = \(cursorBlink)")
    lines.append("scrollback-limit = \(scrollbackLines)")
    if backgroundOpacity < 1.0 {
      lines.append("background-opacity = \(String(format: "%.2f", backgroundOpacity))")
    }
    return lines.joined(separator: "\n") + "\n"
  }

  func applySettings(
    fontFamily: String,
    fontSize: Double,
    cursorStyle: CursorStyle,
    cursorBlink: Bool,
    scrollbackLines: Int,
    backgroundOpacity: Double = 1.0
  ) {
    self.fontFamily = fontFamily
    self.fontSize = fontSize
    self.cursorStyle = cursorStyle
    self.cursorBlink = cursorBlink
    self.scrollbackLines = scrollbackLines
    self.backgroundOpacity = backgroundOpacity
    persistAll()
    IdleConfigComposer.applyAll()
    NotificationCenter.default.post(name: .idleSettingsDidChange, object: nil)
  }

  /// Adjust font size by a delta (e.g. +1 or -1) and apply globally.
  func adjustFontSize(by delta: Double) {
    fontSize = max(8, min(32, fontSize + delta))
    persistAll()
    IdleConfigComposer.applyAll()
    NotificationCenter.default.post(name: .idleSettingsDidChange, object: nil)
  }

  /// Reset font size to 14 and apply globally.
  func resetFontSize() {
    fontSize = 14.0
    persistAll()
    IdleConfigComposer.applyAll()
    NotificationCenter.default.post(name: .idleSettingsDidChange, object: nil)
  }

  func applyPersistedSettings() {
    let isDefault = fontFamily.isEmpty
      && fontSize == 14.0
      && cursorStyle == .block
      && cursorBlink == true
      && scrollbackLines == 10_000_000
      && backgroundOpacity == 1.0
    guard !isDefault else { return }
    IdleConfigComposer.applyAll()
  }

  private func persistAll() {
    UserDefaults.standard.set(fontFamily, forKey: Self.fontFamilyKey)
    UserDefaults.standard.set(fontSize, forKey: Self.fontSizeKey)
    UserDefaults.standard.set(cursorStyle.rawValue, forKey: Self.cursorStyleKey)
    UserDefaults.standard.set(cursorBlink, forKey: Self.cursorBlinkKey)
    UserDefaults.standard.set(scrollbackLines, forKey: Self.scrollbackLinesKey)
    UserDefaults.standard.set(backgroundOpacity, forKey: Self.backgroundOpacityKey)
  }
}
