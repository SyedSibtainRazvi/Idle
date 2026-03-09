import AppKit

final class SettingsView: NSView {
  var onClose: (() -> Void)?

  private let headerLabel = NSTextField()
  private let closeButton = NSButton()
  private let fontFamilyPopup = NSPopUpButton()
  private let fontSizeStepper = NSStepper()
  private let fontSizeField = NSTextField()
  private let cursorSegment = NSSegmentedControl()
  private let cursorBlinkSwitch = NSSwitch()
  private let scrollbackPopup = NSPopUpButton()

  private let commonFonts = [
    "System Default",
    "Menlo",
    "SF Mono",
    "JetBrains Mono",
    "Fira Code",
    "Source Code Pro",
    "IBM Plex Mono",
    "Cascadia Code",
    "Hack",
    "Inconsolata",
    "Monaco",
  ]

  private let scrollbackOptions: [(label: String, value: Int)] = [
    ("1,000", 1_000),
    ("5,000", 5_000),
    ("10,000", 10_000),
    ("50,000", 50_000),
    ("100,000", 100_000),
    ("Unlimited", 10_000_000),
  ]

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setup()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func refreshValues() {
    let mgr = SettingsManager.shared

    // Font family
    let family = mgr.fontFamily
    if family.isEmpty {
      fontFamilyPopup.selectItem(at: 0) // "System Default"
    } else if let idx = commonFonts.firstIndex(of: family) {
      fontFamilyPopup.selectItem(at: idx)
    } else {
      // Custom font not in the list — add it temporarily
      if fontFamilyPopup.itemTitles.contains(family) {
        fontFamilyPopup.selectItem(withTitle: family)
      } else {
        fontFamilyPopup.addItem(withTitle: family)
        fontFamilyPopup.selectItem(withTitle: family)
      }
    }

    // Font size
    fontSizeField.stringValue = "\(Int(mgr.fontSize))"
    fontSizeStepper.integerValue = Int(mgr.fontSize)

    // Cursor style
    switch mgr.cursorStyle {
    case .block: cursorSegment.selectedSegment = 0
    case .bar: cursorSegment.selectedSegment = 1
    case .underline: cursorSegment.selectedSegment = 2
    }

    // Cursor blink
    cursorBlinkSwitch.state = mgr.cursorBlink ? .on : .off

    // Scrollback
    if let idx = scrollbackOptions.firstIndex(where: { $0.value == mgr.scrollbackLines }) {
      scrollbackPopup.selectItem(at: idx)
    } else {
      scrollbackPopup.selectItem(at: scrollbackOptions.count - 1) // Unlimited
    }
  }

  // MARK: - Setup

  private func setup() {
    wantsLayer = true
    layer?.cornerRadius = 10
    layer?.backgroundColor = NSColor(white: 0.12, alpha: 0.98).cgColor
    layer?.borderColor = NSColor(white: 0.25, alpha: 0.5).cgColor
    layer?.borderWidth = 0.5

    shadow = NSShadow()
    layer?.shadowColor = NSColor.black.cgColor
    layer?.shadowOpacity = 0.5
    layer?.shadowOffset = CGSize(width: 0, height: -3)
    layer?.shadowRadius = 12

    setupHeader()
    setupFontRow()
    setupCursorRow()
    setupScrollbackRow()
  }

  private func setupHeader() {
    headerLabel.translatesAutoresizingMaskIntoConstraints = false
    headerLabel.stringValue = "Settings"
    headerLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
    headerLabel.textColor = NSColor(white: 0.9, alpha: 1)
    headerLabel.backgroundColor = .clear
    headerLabel.isBordered = false
    headerLabel.isEditable = false
    headerLabel.isSelectable = false
    addSubview(headerLabel)

    closeButton.translatesAutoresizingMaskIntoConstraints = false
    closeButton.bezelStyle = .recessed
    closeButton.isBordered = false
    closeButton.title = ""
    let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
    if let img = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close") {
      closeButton.image = img.withSymbolConfiguration(config) ?? img
    } else {
      closeButton.title = "✕"
    }
    closeButton.imagePosition = .imageOnly
    closeButton.target = self
    closeButton.action = #selector(closeTapped)
    addSubview(closeButton)

    NSLayoutConstraint.activate([
      headerLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
      headerLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),

      closeButton.centerYAnchor.constraint(equalTo: headerLabel.centerYAnchor),
      closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
      closeButton.widthAnchor.constraint(equalToConstant: 22),
      closeButton.heightAnchor.constraint(equalToConstant: 22),
    ])
  }

  private func setupFontRow() {
    let fontLabel = makeLabel("Font")
    let sizeLabel = makeLabel("Size")
    addSubview(fontLabel)
    addSubview(sizeLabel)

    // Font family popup
    fontFamilyPopup.translatesAutoresizingMaskIntoConstraints = false
    fontFamilyPopup.removeAllItems()
    // Filter to fonts actually available on this system
    let available = Set(NSFontManager.shared.availableFontFamilies)
    for name in commonFonts {
      if name == "System Default" || available.contains(name) {
        fontFamilyPopup.addItem(withTitle: name)
      }
    }
    fontFamilyPopup.target = self
    fontFamilyPopup.action = #selector(settingChanged)
    (fontFamilyPopup.cell as? NSPopUpButtonCell)?.controlSize = .small
    fontFamilyPopup.font = NSFont.systemFont(ofSize: 12)
    addSubview(fontFamilyPopup)

    // Font size stepper + field
    fontSizeField.translatesAutoresizingMaskIntoConstraints = false
    fontSizeField.stringValue = "14"
    fontSizeField.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    fontSizeField.textColor = NSColor(white: 0.9, alpha: 1)
    fontSizeField.backgroundColor = NSColor(white: 0.18, alpha: 1)
    fontSizeField.isBordered = true
    fontSizeField.isEditable = true
    fontSizeField.alignment = .center
    fontSizeField.target = self
    fontSizeField.action = #selector(fontSizeFieldChanged)
    addSubview(fontSizeField)

    fontSizeStepper.translatesAutoresizingMaskIntoConstraints = false
    fontSizeStepper.minValue = 8
    fontSizeStepper.maxValue = 32
    fontSizeStepper.increment = 1
    fontSizeStepper.integerValue = 14
    fontSizeStepper.valueWraps = false
    fontSizeStepper.target = self
    fontSizeStepper.action = #selector(fontSizeStepperChanged)
    addSubview(fontSizeStepper)

    NSLayoutConstraint.activate([
      fontLabel.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 20),
      fontLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
      fontLabel.widthAnchor.constraint(equalToConstant: 70),

      fontFamilyPopup.centerYAnchor.constraint(equalTo: fontLabel.centerYAnchor),
      fontFamilyPopup.leadingAnchor.constraint(equalTo: fontLabel.trailingAnchor, constant: 4),
      fontFamilyPopup.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),

      sizeLabel.topAnchor.constraint(equalTo: fontLabel.bottomAnchor, constant: 16),
      sizeLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
      sizeLabel.widthAnchor.constraint(equalToConstant: 70),

      fontSizeField.centerYAnchor.constraint(equalTo: sizeLabel.centerYAnchor),
      fontSizeField.leadingAnchor.constraint(equalTo: sizeLabel.trailingAnchor, constant: 4),
      fontSizeField.widthAnchor.constraint(equalToConstant: 44),
      fontSizeField.heightAnchor.constraint(equalToConstant: 22),

      fontSizeStepper.centerYAnchor.constraint(equalTo: sizeLabel.centerYAnchor),
      fontSizeStepper.leadingAnchor.constraint(equalTo: fontSizeField.trailingAnchor, constant: 4),
    ])
  }

  private func setupCursorRow() {
    let cursorLabel = makeLabel("Cursor")
    let blinkLabel = makeLabel("Blink")
    addSubview(cursorLabel)
    addSubview(blinkLabel)

    // Segmented control for cursor style
    cursorSegment.translatesAutoresizingMaskIntoConstraints = false
    cursorSegment.segmentCount = 3
    cursorSegment.setLabel("Block", forSegment: 0)
    cursorSegment.setLabel("Beam", forSegment: 1)
    cursorSegment.setLabel("Underline", forSegment: 2)
    cursorSegment.segmentStyle = .texturedRounded
    cursorSegment.selectedSegment = 0
    cursorSegment.target = self
    cursorSegment.action = #selector(settingChanged)
    (cursorSegment.cell as? NSSegmentedCell)?.controlSize = .small
    cursorSegment.font = NSFont.systemFont(ofSize: 11)
    addSubview(cursorSegment)

    // Blink switch
    cursorBlinkSwitch.translatesAutoresizingMaskIntoConstraints = false
    cursorBlinkSwitch.state = .on
    cursorBlinkSwitch.controlSize = .mini
    cursorBlinkSwitch.target = self
    cursorBlinkSwitch.action = #selector(settingChanged)
    addSubview(cursorBlinkSwitch)

    NSLayoutConstraint.activate([
      cursorLabel.topAnchor.constraint(equalTo: fontSizeStepper.bottomAnchor, constant: 20),
      cursorLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
      cursorLabel.widthAnchor.constraint(equalToConstant: 70),

      cursorSegment.centerYAnchor.constraint(equalTo: cursorLabel.centerYAnchor),
      cursorSegment.leadingAnchor.constraint(equalTo: cursorLabel.trailingAnchor, constant: 4),
      cursorSegment.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),

      blinkLabel.topAnchor.constraint(equalTo: cursorLabel.bottomAnchor, constant: 16),
      blinkLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
      blinkLabel.widthAnchor.constraint(equalToConstant: 70),

      cursorBlinkSwitch.centerYAnchor.constraint(equalTo: blinkLabel.centerYAnchor),
      cursorBlinkSwitch.leadingAnchor.constraint(equalTo: blinkLabel.trailingAnchor, constant: 4),
    ])
  }

  private func setupScrollbackRow() {
    let scrollLabel = makeLabel("Scrollback")
    addSubview(scrollLabel)

    scrollbackPopup.translatesAutoresizingMaskIntoConstraints = false
    scrollbackPopup.removeAllItems()
    for opt in scrollbackOptions {
      scrollbackPopup.addItem(withTitle: opt.label)
    }
    scrollbackPopup.selectItem(at: scrollbackOptions.count - 1) // Unlimited default
    scrollbackPopup.target = self
    scrollbackPopup.action = #selector(settingChanged)
    (scrollbackPopup.cell as? NSPopUpButtonCell)?.controlSize = .small
    scrollbackPopup.font = NSFont.systemFont(ofSize: 12)
    addSubview(scrollbackPopup)

    NSLayoutConstraint.activate([
      scrollLabel.topAnchor.constraint(equalTo: cursorBlinkSwitch.bottomAnchor, constant: 20),
      scrollLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
      scrollLabel.widthAnchor.constraint(equalToConstant: 70),

      scrollbackPopup.centerYAnchor.constraint(equalTo: scrollLabel.centerYAnchor),
      scrollbackPopup.leadingAnchor.constraint(equalTo: scrollLabel.trailingAnchor, constant: 4),
      scrollbackPopup.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
    ])
  }

  // MARK: - Helpers

  private func makeLabel(_ text: String) -> NSTextField {
    let label = NSTextField()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.stringValue = text
    label.font = NSFont.systemFont(ofSize: 12.5, weight: .regular)
    label.textColor = NSColor(white: 0.85, alpha: 1)
    label.backgroundColor = .clear
    label.isBordered = false
    label.isEditable = false
    label.isSelectable = false
    return label
  }

  // MARK: - Actions

  @objc private func closeTapped() { onClose?() }

  @objc private func fontSizeStepperChanged() {
    fontSizeField.stringValue = "\(fontSizeStepper.integerValue)"
    applyCurrentSettings()
  }

  @objc private func fontSizeFieldChanged() {
    let val = max(8, min(32, fontSizeField.integerValue))
    fontSizeField.stringValue = "\(val)"
    fontSizeStepper.integerValue = val
    applyCurrentSettings()
  }

  @objc private func settingChanged() {
    applyCurrentSettings()
  }

  private func applyCurrentSettings() {
    let selectedFont = fontFamilyPopup.titleOfSelectedItem ?? "System Default"
    let family = selectedFont == "System Default" ? "" : selectedFont

    let size = Double(fontSizeStepper.integerValue)

    let style: CursorStyle
    switch cursorSegment.selectedSegment {
    case 1: style = .bar
    case 2: style = .underline
    default: style = .block
    }

    let blink = cursorBlinkSwitch.state == .on

    let scrollIdx = scrollbackPopup.indexOfSelectedItem
    let scrollback = scrollbackOptions[safe: scrollIdx]?.value ?? 10_000_000

    SettingsManager.shared.applySettings(
      fontFamily: family,
      fontSize: size,
      cursorStyle: style,
      cursorBlink: blink,
      scrollbackLines: scrollback
    )
  }
}

private extension Array {
  subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
