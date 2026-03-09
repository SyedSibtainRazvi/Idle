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

final class SettingsManager {
  static let shared = SettingsManager()

  private static let fontFamilyKey = "IdleFontFamily"
  private static let fontSizeKey = "IdleFontSize"
  private static let cursorStyleKey = "IdleCursorStyle"
  private static let cursorBlinkKey = "IdleCursorBlink"
  private static let scrollbackLinesKey = "IdleScrollbackLines"

  private(set) var fontFamily: String
  private(set) var fontSize: Double
  private(set) var cursorStyle: CursorStyle
  private(set) var cursorBlink: Bool
  private(set) var scrollbackLines: Int

  private init() {
    fontFamily = UserDefaults.standard.string(forKey: Self.fontFamilyKey) ?? ""
    fontSize = UserDefaults.standard.object(forKey: Self.fontSizeKey) as? Double ?? 14.0
    cursorStyle = CursorStyle(rawValue: UserDefaults.standard.string(forKey: Self.cursorStyleKey) ?? "block") ?? .block
    cursorBlink = UserDefaults.standard.object(forKey: Self.cursorBlinkKey) as? Bool ?? true
    scrollbackLines = UserDefaults.standard.object(forKey: Self.scrollbackLinesKey) as? Int ?? 10_000_000
  }

  func applySettings(
    fontFamily: String,
    fontSize: Double,
    cursorStyle: CursorStyle,
    cursorBlink: Bool,
    scrollbackLines: Int
  ) {
    self.fontFamily = fontFamily
    self.fontSize = fontSize
    self.cursorStyle = cursorStyle
    self.cursorBlink = cursorBlink
    self.scrollbackLines = scrollbackLines

    UserDefaults.standard.set(fontFamily, forKey: Self.fontFamilyKey)
    UserDefaults.standard.set(fontSize, forKey: Self.fontSizeKey)
    UserDefaults.standard.set(cursorStyle.rawValue, forKey: Self.cursorStyleKey)
    UserDefaults.standard.set(cursorBlink, forKey: Self.cursorBlinkKey)
    UserDefaults.standard.set(scrollbackLines, forKey: Self.scrollbackLinesKey)

    applyToGhostty()
  }

  func applyPersistedSettings() {
    let isDefault = fontFamily.isEmpty
      && fontSize == 14.0
      && cursorStyle == .block
      && cursorBlink == true
      && scrollbackLines == 10_000_000
    guard !isDefault else { return }
    applyToGhostty()
  }

  private func applyToGhostty() {
    guard let app = GhosttyRuntime.shared.app else { return }

    var lines: [String] = []
    if !fontFamily.isEmpty {
      lines.append("font-family = \(fontFamily)")
    }
    lines.append("font-size = \(Int(fontSize))")
    lines.append("cursor-style = \(cursorStyle.rawValue)")
    lines.append("cursor-style-blink = \(cursorBlink)")
    lines.append("scrollback-limit = \(scrollbackLines)")

    let configStr = lines.joined(separator: "\n") + "\n"
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("idle-settings.conf")
    do {
      try configStr.write(to: tempURL, atomically: true, encoding: .utf8)
    } catch {
      NSLog("[Idle] Failed to write settings config: %@", error.localizedDescription)
      return
    }

    guard let newCfg = ghostty_config_new() else { return }
    tempURL.path.withCString { ghostty_config_load_file(newCfg, $0) }
    ghostty_config_finalize(newCfg)
    ghostty_app_update_config(app, newCfg)
    ghostty_config_free(newCfg)

    try? FileManager.default.removeItem(at: tempURL)

    NotificationCenter.default.post(name: .idleSettingsDidChange, object: nil)
  }
}
