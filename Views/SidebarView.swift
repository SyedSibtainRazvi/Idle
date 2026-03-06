import AppKit

private final class SidebarPointerButton: NSButton {
  override func resetCursorRects() {
    addCursorRect(bounds, cursor: .pointingHand)
  }
}

final class SidebarView: NSView {
  weak var delegate: SidebarDelegate?

  var sessions: [SessionItem] = [] {
    didSet { tableView.reloadData() }
  }
  var selectedIndex: Int = 0 {
    didSet {
      if tableView.numberOfRows > selectedIndex {
        tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
      }
    }
  }

  private let scrollView = NSScrollView()
  private let tableView = NSTableView()
  private let bottomBar = NSView()
  private let newSessionButton = SidebarPointerButton()
  private let dividerLine = NSView()

  private static let cellIdentifier = NSUserInterfaceItemIdentifier("SessionCell")
  private static let rowIdentifier = NSUserInterfaceItemIdentifier("SessionRow")

  // Colors (from shared theme)
  private let bgColor = IdleTheme.bgColor
  private let activeRowBg = IdleTheme.activeRowBg
  private let hoverRowBg = IdleTheme.hoverRowBg
  private let inactiveRowBg = IdleTheme.inactiveRowBg
  private let accentColor = IdleTheme.accentColor
  private let secondaryText = IdleTheme.secondaryText
  private let dividerColor = IdleTheme.dividerColor
  private let bottomBarBg = IdleTheme.bgColor

  // Dimensions
  private let rowHeight: CGFloat = 62
  private let bottomBarHeight: CGFloat = 44

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setupViews()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupViews() {
    wantsLayer = true
    layer?.backgroundColor = bgColor.cgColor

    // Table view
    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("SessionColumn"))
    column.resizingMask = .autoresizingMask
    tableView.addTableColumn(column)
    tableView.headerView = nil
    tableView.backgroundColor = .clear
    tableView.rowHeight = rowHeight
    tableView.intercellSpacing = NSSize(width: 0, height: 0)
    tableView.selectionHighlightStyle = .none
    tableView.style = .plain
    tableView.dataSource = self
    tableView.delegate = self
    tableView.doubleAction = #selector(tableViewDoubleClick(_:))
    tableView.target = self
    tableView.setAccessibilityLabel("Sessions")
    tableView.setAccessibilityRole(.list)

    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.documentView = tableView
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.drawsBackground = false
    scrollView.borderType = .noBorder
    scrollView.automaticallyAdjustsContentInsets = false
    scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    scrollView.scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    scrollView.contentView.automaticallyAdjustsContentInsets = false
    scrollView.contentView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    addSubview(scrollView)

    // Divider line between table and bottom bar
    dividerLine.translatesAutoresizingMaskIntoConstraints = false
    dividerLine.wantsLayer = true
    dividerLine.layer?.backgroundColor = dividerColor.cgColor
    addSubview(dividerLine)

    // Bottom bar with new session button
    bottomBar.translatesAutoresizingMaskIntoConstraints = false
    bottomBar.wantsLayer = true
    bottomBar.layer?.backgroundColor = bottomBarBg.cgColor
    addSubview(bottomBar)

    newSessionButton.translatesAutoresizingMaskIntoConstraints = false
    newSessionButton.title = "+  New Session"
    newSessionButton.bezelStyle = .recessed
    newSessionButton.isBordered = false
    newSessionButton.wantsLayer = true
    newSessionButton.layer?.cornerRadius = 6
    newSessionButton.layer?.backgroundColor = NSColor(white: 1, alpha: 0.06).cgColor
    newSessionButton.layer?.borderWidth = 0.5
    newSessionButton.layer?.borderColor = NSColor(white: 1, alpha: 0.08).cgColor
    newSessionButton.font = NSFont.systemFont(ofSize: 12, weight: .medium)
    newSessionButton.contentTintColor = secondaryText
    newSessionButton.target = self
    newSessionButton.action = #selector(newSessionClicked(_:))
    newSessionButton.setAccessibilityLabel("New Session")
    newSessionButton.setAccessibilityRole(.button)
    bottomBar.addSubview(newSessionButton)

    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: topAnchor),
      scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: dividerLine.topAnchor),

      dividerLine.leadingAnchor.constraint(equalTo: leadingAnchor),
      dividerLine.trailingAnchor.constraint(equalTo: trailingAnchor),
      dividerLine.heightAnchor.constraint(equalToConstant: 1),
      dividerLine.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),

      bottomBar.leadingAnchor.constraint(equalTo: leadingAnchor),
      bottomBar.trailingAnchor.constraint(equalTo: trailingAnchor),
      bottomBar.bottomAnchor.constraint(equalTo: bottomAnchor),
      bottomBar.heightAnchor.constraint(equalToConstant: bottomBarHeight),

      newSessionButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
      newSessionButton.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 10),
      newSessionButton.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -10),
      newSessionButton.heightAnchor.constraint(equalToConstant: 30),
    ])
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    // Force zero insets after being placed in window (safe area can override)
    scrollView.automaticallyAdjustsContentInsets = false
    scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    scrollView.contentView.setBoundsOrigin(.zero)
  }

  @objc private func newSessionClicked(_ sender: Any?) {
    delegate?.sidebarDidClickNewSession()
  }

  @objc private func tableViewDoubleClick(_ sender: Any?) {
    let row = tableView.clickedRow
    guard row >= 0, row < sessions.count else { return }

    guard let cellView = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? SessionRowView else { return }
    cellView.beginEditingLabel()
  }

  func reloadRow(at index: Int) {
    guard sessions.indices.contains(index) else { return }
    tableView.reloadData(forRowIndexes: IndexSet(integer: index), columnIndexes: IndexSet(integer: 0))
  }

  /// Update a single session's data and reload only that row (avoids full table reload).
  func updateSession(at index: Int, with session: SessionItem) {
    guard sessions.indices.contains(index) else { return }
    sessions[index] = session
    tableView.reloadData(forRowIndexes: IndexSet(integer: index), columnIndexes: IndexSet(integer: 0))
  }
}

// MARK: - NSTableViewDataSource

extension SidebarView: NSTableViewDataSource {
  func numberOfRows(in tableView: NSTableView) -> Int {
    sessions.count
  }
}

// MARK: - NSTableViewDelegate

extension SidebarView: NSTableViewDelegate {
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    guard row < sessions.count else { return nil }
    let session = sessions[row]
    let isActive = row == selectedIndex

    // Reuse or create cell
    let cellView: SessionRowView
    if let reused = tableView.makeView(withIdentifier: Self.cellIdentifier, owner: nil) as? SessionRowView {
      reused.configure(session: session, isActive: isActive)
      cellView = reused
    } else {
      cellView = SessionRowView(session: session, isActive: isActive)
      cellView.identifier = Self.cellIdentifier
    }

    let sessionId = session.id
    cellView.onRename = { [weak self] newLabel in
      guard let self, let currentIndex = self.sessions.firstIndex(where: { $0.id == sessionId }) else { return }
      self.delegate?.sidebarDidRenameSession(at: currentIndex, to: newLabel)
    }
    cellView.onClose = { [weak self] in
      guard let self, let currentIndex = self.sessions.firstIndex(where: { $0.id == sessionId }) else { return }
      self.delegate?.sidebarDidCloseSession(at: currentIndex)
    }
    return cellView
  }

  func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
    rowHeight
  }

  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    let isActive = row == selectedIndex
    if let reused = tableView.rowView(atRow: row, makeIfNecessary: false) as? SessionTableRowView {
      reused.updateActive(isActive)
      return reused
    }
    return SessionTableRowView(isActive: isActive, activeColor: activeRowBg, inactiveColor: inactiveRowBg, hoverColor: hoverRowBg, accentColor: accentColor)
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    let row = tableView.selectedRow
    guard row >= 0, row != selectedIndex else { return }
    delegate?.sidebarDidSelectSession(at: row)
  }
}

// MARK: - SessionTableRowView (custom row with accent stripe)

final class SessionTableRowView: NSTableRowView {
  private var isActiveRow: Bool
  private let activeColor: NSColor
  private let inactiveColor: NSColor
  private let hoverColor: NSColor
  private let rowAccentColor: NSColor
  private var isHovered = false
  private var trackingArea: NSTrackingArea?

  init(isActive: Bool, activeColor: NSColor, inactiveColor: NSColor, hoverColor: NSColor, accentColor: NSColor) {
    self.isActiveRow = isActive
    self.activeColor = activeColor
    self.inactiveColor = inactiveColor
    self.hoverColor = hoverColor
    self.rowAccentColor = accentColor
    super.init(frame: .zero)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func updateActive(_ active: Bool) {
    isActiveRow = active
    setAccessibilityLabel(isActiveRow ? "Active session row" : "Session row")
    needsDisplay = true
  }

  override func drawBackground(in dirtyRect: NSRect) {
    let bg: NSColor
    if isActiveRow {
      bg = activeColor
    } else if isHovered {
      bg = hoverColor
    } else {
      bg = inactiveColor
    }
    bg.setFill()
    bounds.fill()

    if isActiveRow {
      rowAccentColor.setFill()
      NSRect(x: 0, y: 0, width: 2, height: bounds.height).fill()
    }
  }

  override func drawSelection(in dirtyRect: NSRect) {
    // Handled by drawBackground
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingArea { removeTrackingArea(trackingArea) }
    let area = NSTrackingArea(
      rect: bounds,
      options: [.mouseEnteredAndExited, .activeAlways],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(area)
    trackingArea = area
  }

  override func mouseEntered(with event: NSEvent) {
    isHovered = true
    needsDisplay = true
  }

  override func mouseExited(with event: NSEvent) {
    isHovered = false
    needsDisplay = true
  }
}

// MARK: - SessionRowView (cell content)

final class SessionRowView: NSTableCellView, NSTextFieldDelegate {
  var onRename: ((String) -> Void)?
  var onClose: (() -> Void)?

  private let statusDot = NSView()
  private let labelField = NSTextField()
  private let directoryLabel = NSTextField()
  private let branchLabel = NSTextField()
  private let closeButton = NSButton()
  private var originalLabel = ""
  private var isActiveRow = false
  private var trackingArea: NSTrackingArea?

  private let primaryText = IdleTheme.primaryText
  private let secondaryText = IdleTheme.secondaryText
  private let runningDotColor = NSColor(srgbRed: 0.24, green: 0.80, blue: 0.44, alpha: 1)
  private let idleDotColor = NSColor(white: 1.0, alpha: 0.30)

  init(session: SessionItem, isActive: Bool) {
    super.init(frame: .zero)
    setupViews()
    configure(session: session, isActive: isActive)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupViews() {
    // Status dot
    statusDot.translatesAutoresizingMaskIntoConstraints = false
    statusDot.wantsLayer = true
    statusDot.layer?.cornerRadius = 4
    addSubview(statusDot)

    // Label (editable on double-click)
    labelField.translatesAutoresizingMaskIntoConstraints = false
    labelField.backgroundColor = .clear
    labelField.isBordered = false
    labelField.isEditable = false
    labelField.isSelectable = false
    labelField.focusRingType = .none
    labelField.lineBreakMode = .byTruncatingTail
    labelField.cell?.truncatesLastVisibleLine = true
    labelField.delegate = self
    addSubview(labelField)

    // Directory
    directoryLabel.translatesAutoresizingMaskIntoConstraints = false
    directoryLabel.font = NSFont.systemFont(ofSize: 11)
    directoryLabel.textColor = secondaryText
    directoryLabel.backgroundColor = .clear
    directoryLabel.isBordered = false
    directoryLabel.isEditable = false
    directoryLabel.isSelectable = false
    directoryLabel.lineBreakMode = .byTruncatingMiddle
    addSubview(directoryLabel)

    // Branch
    branchLabel.translatesAutoresizingMaskIntoConstraints = false
    branchLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    branchLabel.textColor = secondaryText
    branchLabel.backgroundColor = .clear
    branchLabel.isBordered = false
    branchLabel.isEditable = false
    branchLabel.isSelectable = false
    branchLabel.lineBreakMode = .byTruncatingTail
    addSubview(branchLabel)

    // Close button
    closeButton.translatesAutoresizingMaskIntoConstraints = false
    closeButton.bezelStyle = .recessed
    closeButton.isBordered = false
    closeButton.title = ""
    closeButton.image = Self.makeCloseImage()
    closeButton.imagePosition = .imageOnly
    closeButton.target = self
    closeButton.action = #selector(closeClicked(_:))
    closeButton.isHidden = true
    closeButton.setAccessibilityLabel("Close Session")
    closeButton.setAccessibilityRole(.button)
    addSubview(closeButton)

    NSLayoutConstraint.activate([
      statusDot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
      statusDot.topAnchor.constraint(equalTo: topAnchor, constant: 11),
      statusDot.widthAnchor.constraint(equalToConstant: 8),
      statusDot.heightAnchor.constraint(equalToConstant: 8),

      closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
      closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 2),
      closeButton.widthAnchor.constraint(equalToConstant: 22),
      closeButton.heightAnchor.constraint(equalToConstant: 22),

      labelField.leadingAnchor.constraint(equalTo: statusDot.trailingAnchor, constant: 8),
      labelField.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -2),
      labelField.centerYAnchor.constraint(equalTo: statusDot.centerYAnchor),

      directoryLabel.leadingAnchor.constraint(equalTo: labelField.leadingAnchor),
      directoryLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
      directoryLabel.topAnchor.constraint(equalTo: labelField.bottomAnchor, constant: 2),

      branchLabel.leadingAnchor.constraint(equalTo: labelField.leadingAnchor),
      branchLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
      branchLabel.topAnchor.constraint(equalTo: directoryLabel.bottomAnchor, constant: 1),
    ])
  }

  func configure(session: SessionItem, isActive: Bool) {
    isActiveRow = isActive
    statusDot.layer?.backgroundColor = session.isRunning ? runningDotColor.cgColor : idleDotColor.cgColor
    labelField.stringValue = session.label
    labelField.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
    labelField.textColor = isActive ? primaryText : primaryText.withAlphaComponent(0.65)
    directoryLabel.stringValue = Self.displayDirectory(session.workingDirectory)

    if let branch = session.gitBranch {
      branchLabel.stringValue = "\u{2387} \(branch)"
    } else {
      branchLabel.stringValue = ""
    }

    closeButton.isHidden = !isActive
    originalLabel = session.label

    setAccessibilityLabel("Session: \(session.label)")
    setAccessibilityRole(.cell)
  }

  private static func displayDirectory(_ path: String) -> String {
    let home = IdleConstants.homeDirectory
    if path == home { return "~" }
    if path.hasPrefix(home + "/") {
      return "~/" + String(path.dropFirst(home.count + 1))
    }
    return path
  }

  private static func makeCloseImage() -> NSImage {
    let size = NSSize(width: 12, height: 12)
    let image = NSImage(size: size, flipped: false) { rect in
      let path = NSBezierPath()
      let inset: CGFloat = 1.5
      path.move(to: NSPoint(x: inset, y: inset))
      path.line(to: NSPoint(x: rect.width - inset, y: rect.height - inset))
      path.move(to: NSPoint(x: rect.width - inset, y: inset))
      path.line(to: NSPoint(x: inset, y: rect.height - inset))
      path.lineWidth = 1.4
      path.lineCapStyle = .round
      NSColor(white: 0.50, alpha: 1).setStroke()
      path.stroke()
      return true
    }
    image.isTemplate = true
    return image
  }

  @objc private func closeClicked(_ sender: Any?) {
    onClose?()
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingArea { removeTrackingArea(trackingArea) }
    let area = NSTrackingArea(
      rect: bounds,
      options: [.mouseEnteredAndExited, .activeAlways],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(area)
    trackingArea = area
  }

  override func mouseEntered(with event: NSEvent) {
    closeButton.isHidden = false
  }

  override func mouseExited(with event: NSEvent) {
    closeButton.isHidden = !isActiveRow
  }

  func beginEditingLabel() {
    originalLabel = labelField.stringValue
    labelField.isEditable = true
    labelField.isSelectable = true
    labelField.becomeFirstResponder()
    labelField.selectText(nil)
  }

  // NSTextFieldDelegate
  func control(_ control: NSControl, textShouldEndEditing fieldEditor: NSText) -> Bool {
    let newLabel = fieldEditor.string.trimmingCharacters(in: .whitespacesAndNewlines)
    if !newLabel.isEmpty && newLabel != originalLabel {
      onRename?(newLabel)
    } else {
      labelField.stringValue = originalLabel
    }
    labelField.isEditable = false
    labelField.isSelectable = false
    return true
  }

  func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
    if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
      labelField.stringValue = originalLabel
      labelField.isEditable = false
      labelField.isSelectable = false
      window?.makeFirstResponder(nil)
      return true
    }
    return false
  }
}
