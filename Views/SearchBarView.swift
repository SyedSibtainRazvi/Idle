import AppKit

final class SearchBarView: NSView, NSTextFieldDelegate {
  private let searchField = NSTextField()
  private let matchLabel = NSTextField()
  private let prevButton = NSButton()
  private let nextButton = NSButton()
  private let closeButton = NSButton()

  var onSearch: ((String) -> Void)?
  var onNext: (() -> Void)?
  var onPrev: (() -> Void)?
  var onClose: (() -> Void)?

  private(set) var totalMatches = 0
  private var selectedMatch = 0

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setup()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func focusSearchField() {
    window?.makeFirstResponder(searchField)
  }

  func updateMatchCount(total: Int, selected: Int) {
    totalMatches = total
    selectedMatch = selected
    if searchField.stringValue.isEmpty {
      matchLabel.stringValue = ""
    } else if total == 0 {
      matchLabel.stringValue = "No matches"
      matchLabel.textColor = NSColor(srgbRed: 0.95, green: 0.40, blue: 0.40, alpha: 1)
    } else {
      matchLabel.stringValue = "\(selected + 1) of \(total)"
      matchLabel.textColor = IdleTheme.secondaryText
    }
  }

  func clear() {
    searchField.stringValue = ""
    matchLabel.stringValue = ""
    totalMatches = 0
    selectedMatch = 0
  }

  // MARK: - NSTextFieldDelegate

  func controlTextDidChange(_ obj: Notification) {
    let query = searchField.stringValue
    if query.isEmpty {
      matchLabel.stringValue = ""
    }
    onSearch?(query)
  }

  func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
    if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
      onClose?()
      return true
    }
    if commandSelector == #selector(NSResponder.insertNewline(_:)) {
      let mods = NSApp.currentEvent?.modifierFlags ?? []
      if mods.contains(.shift) {
        onPrev?()
      } else {
        onNext?()
      }
      return true
    }
    return false
  }

  // MARK: - Setup

  private func setup() {
    wantsLayer = true
    layer?.cornerRadius = 8
    layer?.backgroundColor = NSColor(white: 0.15, alpha: 0.95).cgColor
    layer?.borderColor = NSColor(white: 0.3, alpha: 0.5).cgColor
    layer?.borderWidth = 0.5

    // Drop shadow
    shadow = NSShadow()
    layer?.shadowColor = NSColor.black.cgColor
    layer?.shadowOpacity = 0.4
    layer?.shadowOffset = CGSize(width: 0, height: -2)
    layer?.shadowRadius = 8

    searchField.translatesAutoresizingMaskIntoConstraints = false
    searchField.placeholderString = "Search…"
    searchField.font = NSFont.systemFont(ofSize: 13)
    searchField.textColor = IdleTheme.primaryText
    searchField.backgroundColor = NSColor(white: 0.1, alpha: 1)
    searchField.isBordered = true
    searchField.bezelStyle = .roundedBezel
    searchField.focusRingType = .none
    searchField.delegate = self
    addSubview(searchField)

    matchLabel.translatesAutoresizingMaskIntoConstraints = false
    matchLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    matchLabel.textColor = IdleTheme.secondaryText
    matchLabel.backgroundColor = .clear
    matchLabel.isBordered = false
    matchLabel.isEditable = false
    matchLabel.isSelectable = false
    matchLabel.alignment = .center
    matchLabel.stringValue = ""
    addSubview(matchLabel)

    let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)

    configureButton(prevButton, symbolName: "chevron.up", fallback: "▲", config: config,
                    action: #selector(prevTapped), toolTip: "Previous (⇧Enter)")
    configureButton(nextButton, symbolName: "chevron.down", fallback: "▼", config: config,
                    action: #selector(nextTapped), toolTip: "Next (Enter)")
    configureButton(closeButton, symbolName: "xmark", fallback: "✕", config: config,
                    action: #selector(closeTapped), toolTip: "Close (Esc)")

    NSLayoutConstraint.activate([
      heightAnchor.constraint(equalToConstant: 36),

      searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
      searchField.centerYAnchor.constraint(equalTo: centerYAnchor),
      searchField.widthAnchor.constraint(equalToConstant: 180),

      matchLabel.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 6),
      matchLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
      matchLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 55),

      prevButton.leadingAnchor.constraint(equalTo: matchLabel.trailingAnchor, constant: 2),
      prevButton.centerYAnchor.constraint(equalTo: centerYAnchor),
      prevButton.widthAnchor.constraint(equalToConstant: 22),
      prevButton.heightAnchor.constraint(equalToConstant: 22),

      nextButton.leadingAnchor.constraint(equalTo: prevButton.trailingAnchor),
      nextButton.centerYAnchor.constraint(equalTo: centerYAnchor),
      nextButton.widthAnchor.constraint(equalToConstant: 22),
      nextButton.heightAnchor.constraint(equalToConstant: 22),

      closeButton.leadingAnchor.constraint(equalTo: nextButton.trailingAnchor, constant: 4),
      closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
      closeButton.widthAnchor.constraint(equalToConstant: 22),
      closeButton.heightAnchor.constraint(equalToConstant: 22),
      closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
    ])
  }

  private func configureButton(_ button: NSButton, symbolName: String, fallback: String,
                                config: NSImage.SymbolConfiguration, action: Selector, toolTip: String) {
    button.translatesAutoresizingMaskIntoConstraints = false
    button.bezelStyle = .recessed
    button.isBordered = false
    button.title = ""
    if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: toolTip) {
      button.image = img.withSymbolConfiguration(config) ?? img
    } else {
      button.title = fallback
    }
    button.imagePosition = .imageOnly
    button.target = self
    button.action = action
    button.toolTip = toolTip
    addSubview(button)
  }

  @objc private func prevTapped() { onPrev?() }
  @objc private func nextTapped() { onNext?() }
  @objc private func closeTapped() { onClose?() }
}
