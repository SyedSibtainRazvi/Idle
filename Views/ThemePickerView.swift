import AppKit

final class ThemePickerView: NSView {
  var onClose: (() -> Void)?

  private let scrollView = NSScrollView()
  private let stackView = NSStackView()
  private let headerLabel = NSTextField()
  private let closeButton = NSButton()
  private var themeRows: [ThemeRowView] = []

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setup()
    buildThemeRows()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func refreshSelection() {
    let selected = ThemeManager.shared.selectedThemeName
    for row in themeRows {
      row.setSelected(row.theme.name == selected)
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

    // Header
    headerLabel.translatesAutoresizingMaskIntoConstraints = false
    headerLabel.stringValue = "Themes"
    headerLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
    headerLabel.textColor = NSColor(white: 0.9, alpha: 1)
    headerLabel.backgroundColor = .clear
    headerLabel.isBordered = false
    headerLabel.isEditable = false
    headerLabel.isSelectable = false
    addSubview(headerLabel)

    // Close button
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

    // Scroll view
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.drawsBackground = false
    scrollView.automaticallyAdjustsContentInsets = false
    scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 8, right: 0)
    addSubview(scrollView)

    stackView.translatesAutoresizingMaskIntoConstraints = false
    stackView.orientation = .vertical
    stackView.spacing = 2
    stackView.alignment = .leading

    let clipView = NSClipView()
    clipView.translatesAutoresizingMaskIntoConstraints = false
    clipView.drawsBackground = false
    clipView.documentView = stackView
    scrollView.contentView = clipView

    NSLayoutConstraint.activate([
      headerLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
      headerLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),

      closeButton.centerYAnchor.constraint(equalTo: headerLabel.centerYAnchor),
      closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
      closeButton.widthAnchor.constraint(equalToConstant: 22),
      closeButton.heightAnchor.constraint(equalToConstant: 22),

      scrollView.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 10),
      scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

      clipView.topAnchor.constraint(equalTo: scrollView.topAnchor),
      clipView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
      clipView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
      clipView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),

      stackView.topAnchor.constraint(equalTo: clipView.topAnchor),
      stackView.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
      stackView.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
    ])
  }

  private func buildThemeRows() {
    let selected = ThemeManager.shared.selectedThemeName
    for theme in ThemeManager.shared.themes {
      let row = ThemeRowView(theme: theme)
      row.setSelected(theme.name == selected)
      row.onSelect = { [weak self] selectedTheme in
        ThemeManager.shared.applyTheme(selectedTheme)
        self?.refreshSelection()
      }
      stackView.addArrangedSubview(row)
      row.translatesAutoresizingMaskIntoConstraints = false
      row.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
      themeRows.append(row)
    }
  }

  @objc private func closeTapped() { onClose?() }
}

// MARK: - Theme Row

private final class ThemeRowView: NSView {
  let theme: TerminalTheme
  var onSelect: ((TerminalTheme) -> Void)?

  private let nameLabel = NSTextField()
  private let previewContainer = NSView()
  private let checkmark = NSTextField()
  private var trackingArea: NSTrackingArea?
  private var isHighlighted = false

  init(theme: TerminalTheme) {
    self.theme = theme
    super.init(frame: .zero)
    setup()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func setSelected(_ selected: Bool) {
    checkmark.isHidden = !selected
    nameLabel.font = selected
      ? NSFont.systemFont(ofSize: 12.5, weight: .semibold)
      : NSFont.systemFont(ofSize: 12.5, weight: .regular)
  }

  override func mouseDown(with event: NSEvent) {
    onSelect?(theme)
  }

  override func mouseEntered(with event: NSEvent) {
    isHighlighted = true
    layer?.backgroundColor = NSColor(white: 0.2, alpha: 1).cgColor
  }

  override func mouseExited(with event: NSEvent) {
    isHighlighted = false
    layer?.backgroundColor = NSColor.clear.cgColor
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let ta = trackingArea { removeTrackingArea(ta) }
    trackingArea = NSTrackingArea(
      rect: bounds,
      options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(trackingArea!)
  }

  private func setup() {
    wantsLayer = true
    layer?.cornerRadius = 6

    // Color preview dots
    previewContainer.translatesAutoresizingMaskIntoConstraints = false
    previewContainer.wantsLayer = true
    addSubview(previewContainer)

    let bgDot = makeDot(hex: theme.background)
    let fgDot = makeDot(hex: theme.foreground)
    // Show 4 key palette colors (red, green, blue, magenta)
    let redDot = makeDot(hex: theme.palette[1])
    let greenDot = makeDot(hex: theme.palette[2])
    let blueDot = makeDot(hex: theme.palette[4])
    let magentaDot = makeDot(hex: theme.palette[5])
    let dots = [bgDot, fgDot, redDot, greenDot, blueDot, magentaDot]
    for dot in dots { previewContainer.addSubview(dot) }

    // Name
    nameLabel.translatesAutoresizingMaskIntoConstraints = false
    nameLabel.stringValue = theme.name
    nameLabel.font = NSFont.systemFont(ofSize: 12.5, weight: .regular)
    nameLabel.textColor = NSColor(white: 0.85, alpha: 1)
    nameLabel.backgroundColor = .clear
    nameLabel.isBordered = false
    nameLabel.isEditable = false
    nameLabel.isSelectable = false
    addSubview(nameLabel)

    // Checkmark
    checkmark.translatesAutoresizingMaskIntoConstraints = false
    checkmark.stringValue = "✓"
    checkmark.font = NSFont.systemFont(ofSize: 13, weight: .bold)
    checkmark.textColor = NSColor(srgbRed: 0.40, green: 0.56, blue: 1.0, alpha: 1)
    checkmark.backgroundColor = .clear
    checkmark.isBordered = false
    checkmark.isEditable = false
    checkmark.isSelectable = false
    checkmark.isHidden = true
    addSubview(checkmark)

    NSLayoutConstraint.activate([
      heightAnchor.constraint(equalToConstant: 38),

      previewContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
      previewContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
      previewContainer.heightAnchor.constraint(equalToConstant: 14),
      previewContainer.widthAnchor.constraint(equalToConstant: CGFloat(dots.count) * 16),

      nameLabel.leadingAnchor.constraint(equalTo: previewContainer.trailingAnchor, constant: 8),
      nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

      checkmark.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
      checkmark.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])

    // Position dots
    for (i, dot) in dots.enumerated() {
      NSLayoutConstraint.activate([
        dot.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor, constant: CGFloat(i) * 16),
        dot.centerYAnchor.constraint(equalTo: previewContainer.centerYAnchor),
        dot.widthAnchor.constraint(equalToConstant: 14),
        dot.heightAnchor.constraint(equalToConstant: 14),
      ])
    }
  }

  private func makeDot(hex: String) -> NSView {
    let dot = NSView()
    dot.translatesAutoresizingMaskIntoConstraints = false
    dot.wantsLayer = true
    dot.layer?.cornerRadius = 7
    dot.layer?.backgroundColor = NSColor(hex: hex).cgColor
    dot.layer?.borderColor = NSColor(white: 0.3, alpha: 0.5).cgColor
    dot.layer?.borderWidth = 0.5
    return dot
  }
}

// MARK: - NSColor hex helper

private extension NSColor {
  convenience init(hex: String) {
    let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    var rgb: UInt64 = 0
    Scanner(string: hex).scanHexInt64(&rgb)
    let r = CGFloat((rgb >> 16) & 0xFF) / 255
    let g = CGFloat((rgb >> 8) & 0xFF) / 255
    let b = CGFloat(rgb & 0xFF) / 255
    self.init(srgbRed: r, green: g, blue: b, alpha: 1)
  }
}
