import XCTest
@testable import Idle

final class SettingsTests: XCTestCase {

  // MARK: - CursorStyle

  func testCursorStyleRawValues() {
    XCTAssertEqual(CursorStyle.block.rawValue, "block")
    XCTAssertEqual(CursorStyle.bar.rawValue, "bar")
    XCTAssertEqual(CursorStyle.underline.rawValue, "underline")
  }

  func testCursorStyleDisplayNames() {
    XCTAssertEqual(CursorStyle.block.displayName, "Block")
    XCTAssertEqual(CursorStyle.bar.displayName, "Beam")
    XCTAssertEqual(CursorStyle.underline.displayName, "Underline")
  }

  func testCursorStyleFromRawValue() {
    XCTAssertEqual(CursorStyle(rawValue: "block"), .block)
    XCTAssertEqual(CursorStyle(rawValue: "bar"), .bar)
    XCTAssertEqual(CursorStyle(rawValue: "underline"), .underline)
    XCTAssertNil(CursorStyle(rawValue: "invalid"))
  }

  // MARK: - SettingsManager config string

  func testConfigStringDefaultSettings() {
    let mgr = SettingsManager.shared
    let config = mgr.configString()
    XCTAssertTrue(config.contains("font-size = "))
    XCTAssertTrue(config.contains("cursor-style = "))
    XCTAssertTrue(config.contains("cursor-style-blink = "))
    XCTAssertTrue(config.contains("scrollback-limit = "))
  }

  func testConfigStringQuotesFontFamilyWithSpaces() {
    let mgr = SettingsManager.shared
    mgr.applySettings(
      fontFamily: "JetBrains Mono",
      fontSize: mgr.fontSize,
      cursorStyle: mgr.cursorStyle,
      cursorBlink: mgr.cursorBlink,
      scrollbackLines: mgr.scrollbackLines
    )
    let config = mgr.configString()
    XCTAssertTrue(config.contains("font-family = \"JetBrains Mono\""),
                  "Font family with spaces should be quoted. Got: \(config)")
    // Reset
    mgr.applySettings(fontFamily: "", fontSize: 14, cursorStyle: .block,
                       cursorBlink: true, scrollbackLines: 10_000_000)
  }

  func testConfigStringOmitsFontFamilyWhenEmpty() {
    let mgr = SettingsManager.shared
    mgr.applySettings(fontFamily: "", fontSize: 14, cursorStyle: .block,
                       cursorBlink: true, scrollbackLines: 10_000_000)
    let config = mgr.configString()
    XCTAssertFalse(config.contains("font-family"),
                   "Empty font family should not appear in config")
  }

  func testConfigStringIncludesAllSettings() {
    let mgr = SettingsManager.shared
    mgr.applySettings(fontFamily: "Menlo", fontSize: 16, cursorStyle: .underline,
                       cursorBlink: false, scrollbackLines: 5_000_000)
    let config = mgr.configString()
    XCTAssertTrue(config.contains("font-family = \"Menlo\""))
    XCTAssertTrue(config.contains("font-size = 16"))
    XCTAssertTrue(config.contains("cursor-style = underline"))
    XCTAssertTrue(config.contains("cursor-style-blink = false"))
    XCTAssertTrue(config.contains("scrollback-limit = 5000000"))
    // Reset
    mgr.applySettings(fontFamily: "", fontSize: 14, cursorStyle: .block,
                       cursorBlink: true, scrollbackLines: 10_000_000)
  }

  // MARK: - Font size adjustment

  func testAdjustFontSizeClampsBounds() {
    let mgr = SettingsManager.shared
    let original = mgr.fontSize

    mgr.adjustFontSize(by: 100)
    XCTAssertEqual(mgr.fontSize, 32, "Font size should clamp at 32")

    mgr.adjustFontSize(by: -100)
    XCTAssertEqual(mgr.fontSize, 8, "Font size should clamp at 8")

    // Reset
    mgr.applySettings(fontFamily: "", fontSize: original, cursorStyle: .block,
                       cursorBlink: true, scrollbackLines: 10_000_000)
  }

  func testResetFontSize() {
    let mgr = SettingsManager.shared
    mgr.adjustFontSize(by: 5)
    mgr.resetFontSize()
    XCTAssertEqual(mgr.fontSize, 14.0)
  }

  // MARK: - ThemeManager

  func testThemeManagerHasThemes() {
    XCTAssertFalse(ThemeManager.shared.themes.isEmpty)
  }

  func testDefaultThemeIsIdleDark() {
    let theme = ThemeManager.shared.themes[0]
    XCTAssertEqual(theme.name, "Idle Dark")
  }

  func testThemeGhosttyConfigContainsRequiredKeys() {
    let theme = ThemeManager.shared.themes[0]
    let config = theme.toGhosttyConfig()
    XCTAssertTrue(config.contains("background = "))
    XCTAssertTrue(config.contains("foreground = "))
    XCTAssertTrue(config.contains("cursor-color = "))
    XCTAssertTrue(config.contains("cursor-text = "))
    XCTAssertTrue(config.contains("selection-background = "))
    XCTAssertTrue(config.contains("selection-foreground = "))
    XCTAssertTrue(config.contains("palette = 0="))
    XCTAssertTrue(config.contains("palette = 15="))
  }

  func testAllThemesHave16PaletteColors() {
    for theme in ThemeManager.shared.themes {
      XCTAssertEqual(theme.palette.count, 16,
                     "Theme \(theme.name) should have 16 palette colors")
    }
  }

  // MARK: - IdleTheme colors

  func testIdleThemeUpdateChangesColors() {
    let original = IdleTheme.bgColor
    let testBg = NSColor.red
    let testFg = NSColor.green
    let testAccent = NSColor.blue

    IdleTheme.update(background: testBg, foreground: testFg, accent: testAccent)
    XCTAssertEqual(IdleTheme.bgColor, testBg)
    XCTAssertEqual(IdleTheme.accentColor, testAccent)

    // Restore
    IdleTheme.update(background: original, foreground: NSColor(white: 0.92, alpha: 1),
                     accent: NSColor(srgbRed: 0.40, green: 0.56, blue: 1.0, alpha: 1))
  }

  func testIdleThemeDerivedColorsAreComputed() {
    // Verify derived colors change when base changes
    let bg1 = IdleTheme.dividerColor

    let newBg = NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)
    IdleTheme.update(background: newBg, foreground: NSColor.white,
                     accent: NSColor.blue)
    let bg2 = IdleTheme.dividerColor
    XCTAssertNotEqual(bg1, bg2, "Derived colors should change with base color")

    // Restore
    IdleTheme.update(
      background: NSColor(srgbRed: 0.067, green: 0.067, blue: 0.075, alpha: 1),
      foreground: NSColor(white: 0.92, alpha: 1),
      accent: NSColor(srgbRed: 0.40, green: 0.56, blue: 1.0, alpha: 1)
    )
  }
}
