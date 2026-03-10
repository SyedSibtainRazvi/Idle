import AppKit
import UserNotifications

final class PointerButton: NSButton {
  override func resetCursorRects() {
    addCursorRect(bounds, cursor: .pointingHand)
  }
}

final class MainWindowController: NSWindowController, NSWindowDelegate, SidebarDelegate, ClaudeCodeDetectorDelegate, LearningEngineDelegate {
  private static let learningConsentAcceptedKey = "IdleLearningConsentAccepted"

  /// The session ID that the current learning generation was started for.
  /// Used to discard stale callbacks when the user switches tabs.
  private var learningSessionID: UUID?
  private var currentPhase: ClaudeCodePhase = .inactive
  private var pendingQuestions: [LearningQuestion] = []
  private let headerBar = NSView()
  private let headerDivider = NSView()
  private let toggleButton = PointerButton()
  private let learningToggleButton = PointerButton()
  private let titleLabel = NSTextField()
  private let sidebar = SidebarView()
  private let sidebarWrapper = NSView()
  private let sidebarDivider = NSView()
  private let terminalContainer = NSView()
  private var sessions: [SessionItem] = []
  private var activeSessionIndex = 0
  private var sidebarWidthConstraint: NSLayoutConstraint!
  private var toggleLeadingConstraint: NSLayoutConstraint!
  private var isSidebarVisible = true
  private var sessionCounter = 0
  private var isClosingSession = false

  // Search bar (floating overlay)
  private let searchBar = SearchBarView()
  private var isSearchBarVisible = false

  // Theme picker (floating overlay)
  private let themePicker = ThemePickerView()
  private var isThemePickerVisible = false

  // Settings panel (floating overlay)
  private let settingsPanel = SettingsView()
  private var isSettingsPanelVisible = false

  // Closed sessions (for reopen)
  private var closedSessions: [(label: String, workingDirectory: String)] = []
  private let maxClosedSessions = 10

  // Learning panel
  private let learningPanel = LearningPanelView()
  private let learningPanelWrapper = NSView()
  private let learningPanelDivider = NSView()
  private var learningPanelWidthConstraint: NSLayoutConstraint!
  private var isLearningPanelVisible = false
  private let learningPanelWidth: CGFloat = 320
  private let claudeDetector = ClaudeCodeDetector()
  private let learningEngine = LearningEngine()

  private var titleObserver: NSObjectProtocol?
  private var closeObserver: NSObjectProtocol?
  private var pwdObserver: NSObjectProtocol?
  private var searchTotalObserver: NSObjectProtocol?
  private var searchSelectedObserver: NSObjectProtocol?
  private var enterFullScreenObserver: NSObjectProtocol?
  private var exitFullScreenObserver: NSObjectProtocol?

  private let sidebarWidth: CGFloat = 200
  private let headerHeight: CGFloat = 38
  private let trafficLightLeading: CGFloat = 78
  private let fullScreenLeading: CGFloat = 12
  private let shellNames: Set<String> = ["zsh", "bash", "fish", "sh", "dash", "csh", "tcsh", "ksh"]

  private var themeObserver: NSObjectProtocol?
  private var commandFinishedObserver: NSObjectProtocol?
  private var linkHoverObserver: NSObjectProtocol?

  // URL preview (floating label at bottom of terminal)
  private let linkPreviewLabel = NSTextField()

  init() {
    let initialRect = NSRect(x: 0, y: 0, width: 900, height: 600)
    let styleMask: NSWindow.StyleMask = [
      .titled,
      .closable,
      .miniaturizable,
      .resizable,
      .fullSizeContentView,
    ]

    let window = NSWindow(
      contentRect: initialRect,
      styleMask: styleMask,
      backing: .buffered,
      defer: false
    )

    window.title = "Idle"
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isMovableByWindowBackground = true
    window.appearance = NSAppearance(named: .darkAqua)
    window.backgroundColor = .black

    let contentView = NSView(frame: initialRect)
    contentView.wantsLayer = true
    contentView.layer?.backgroundColor = NSColor.black.cgColor

    // ── Header bar (full width, always visible) ──
    headerBar.translatesAutoresizingMaskIntoConstraints = false
    headerBar.wantsLayer = true
    headerBar.layer?.backgroundColor = IdleTheme.bgColor.cgColor
    contentView.addSubview(headerBar)

    // Toggle sidebar button
    toggleButton.translatesAutoresizingMaskIntoConstraints = false
    toggleButton.bezelStyle = .recessed
    toggleButton.isBordered = false
    toggleButton.title = ""
    toggleButton.image = Self.makeSidebarToggleImage()
    toggleButton.imagePosition = .imageOnly
    toggleButton.action = #selector(toggleSidebarAction(_:))
    toggleButton.toolTip = "Toggle Sidebar (⌘B)"
    toggleButton.setAccessibilityLabel("Toggle Sidebar")
    toggleButton.setAccessibilityRole(.button)
    headerBar.addSubview(toggleButton)

    // Title label — right next to toggle
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.stringValue = "Idle"
    titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
    titleLabel.textColor = IdleTheme.headerText
    titleLabel.backgroundColor = .clear
    titleLabel.isBordered = false
    titleLabel.isEditable = false
    titleLabel.isSelectable = false
    headerBar.addSubview(titleLabel)

    // Learning panel toggle button (right side of header)
    learningToggleButton.translatesAutoresizingMaskIntoConstraints = false
    learningToggleButton.bezelStyle = .recessed
    learningToggleButton.isBordered = false
    learningToggleButton.title = ""
    learningToggleButton.image = Self.makeLearningToggleImage()
    learningToggleButton.imagePosition = .imageOnly
    learningToggleButton.action = #selector(toggleLearningPanelAction(_:))
    learningToggleButton.toolTip = "Toggle Learning Panel (\u{21E7}\u{2318}L)"
    learningToggleButton.setAccessibilityLabel("Toggle Learning Panel")
    learningToggleButton.setAccessibilityRole(.button)
    headerBar.addSubview(learningToggleButton)

    // Header divider
    headerDivider.translatesAutoresizingMaskIntoConstraints = false
    headerDivider.wantsLayer = true
    headerDivider.layer?.backgroundColor = IdleTheme.dividerColor.cgColor
    contentView.addSubview(headerDivider)

    // ── Body: sidebar + divider + terminal ──

    // Sidebar wrapper (clips content, animated width)
    sidebarWrapper.translatesAutoresizingMaskIntoConstraints = false
    sidebarWrapper.wantsLayer = true
    sidebarWrapper.layer?.masksToBounds = true
    contentView.addSubview(sidebarWrapper)

    // Sidebar inside wrapper (always 240pt wide)
    sidebar.translatesAutoresizingMaskIntoConstraints = false
    sidebarWrapper.addSubview(sidebar)

    // Divider between sidebar and terminal
    sidebarDivider.translatesAutoresizingMaskIntoConstraints = false
    sidebarDivider.wantsLayer = true
    sidebarDivider.layer?.backgroundColor = IdleTheme.dividerColor.cgColor
    contentView.addSubview(sidebarDivider)

    // Terminal container fills the rest
    terminalContainer.translatesAutoresizingMaskIntoConstraints = false
    terminalContainer.wantsLayer = true
    terminalContainer.layer?.backgroundColor = NSColor.black.cgColor
    contentView.addSubview(terminalContainer)

    // Search bar — floating overlay inside terminal container
    searchBar.translatesAutoresizingMaskIntoConstraints = false
    searchBar.isHidden = true
    terminalContainer.addSubview(searchBar)

    // Theme picker — floating overlay, centered in terminal container
    themePicker.translatesAutoresizingMaskIntoConstraints = false
    themePicker.isHidden = true
    terminalContainer.addSubview(themePicker)

    // Settings panel — floating overlay, centered in terminal container
    settingsPanel.translatesAutoresizingMaskIntoConstraints = false
    settingsPanel.isHidden = true
    terminalContainer.addSubview(settingsPanel)

    // URL preview label — floating at bottom of terminal container
    linkPreviewLabel.translatesAutoresizingMaskIntoConstraints = false
    linkPreviewLabel.wantsLayer = true
    linkPreviewLabel.layer?.cornerRadius = 4
    linkPreviewLabel.layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.9).cgColor
    linkPreviewLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
    linkPreviewLabel.textColor = NSColor(white: 0.75, alpha: 1)
    linkPreviewLabel.backgroundColor = .clear
    linkPreviewLabel.isBordered = false
    linkPreviewLabel.isEditable = false
    linkPreviewLabel.isSelectable = false
    linkPreviewLabel.lineBreakMode = .byTruncatingMiddle
    linkPreviewLabel.isHidden = true
    terminalContainer.addSubview(linkPreviewLabel)

    // ── Learning panel (right side) ──

    // Learning panel divider
    learningPanelDivider.translatesAutoresizingMaskIntoConstraints = false
    learningPanelDivider.wantsLayer = true
    learningPanelDivider.layer?.backgroundColor = IdleTheme.dividerColor.cgColor
    learningPanelDivider.isHidden = true
    contentView.addSubview(learningPanelDivider)

    // Learning panel wrapper (clips content, animated width)
    learningPanelWrapper.translatesAutoresizingMaskIntoConstraints = false
    learningPanelWrapper.wantsLayer = true
    learningPanelWrapper.layer?.masksToBounds = true
    contentView.addSubview(learningPanelWrapper)

    // Learning panel inside wrapper
    learningPanel.translatesAutoresizingMaskIntoConstraints = false
    learningPanelWrapper.addSubview(learningPanel)

    sidebarWidthConstraint = sidebarWrapper.widthAnchor.constraint(equalToConstant: sidebarWidth)
    learningPanelWidthConstraint = learningPanelWrapper.widthAnchor.constraint(equalToConstant: 0)
    toggleLeadingConstraint = toggleButton.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor, constant: trafficLightLeading)

    NSLayoutConstraint.activate([
      // Header bar — full width, top
      headerBar.topAnchor.constraint(equalTo: contentView.topAnchor),
      headerBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      headerBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      headerBar.heightAnchor.constraint(equalToConstant: headerHeight),

      toggleLeadingConstraint,
      toggleButton.topAnchor.constraint(equalTo: headerBar.topAnchor, constant: 3),
      toggleButton.widthAnchor.constraint(equalToConstant: 28),
      toggleButton.heightAnchor.constraint(equalToConstant: 28),

      titleLabel.leadingAnchor.constraint(equalTo: toggleButton.trailingAnchor, constant: 6),
      titleLabel.centerYAnchor.constraint(equalTo: toggleButton.centerYAnchor),

      // Learning panel toggle — right side of header
      learningToggleButton.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor, constant: -12),
      learningToggleButton.topAnchor.constraint(equalTo: headerBar.topAnchor, constant: 3),
      learningToggleButton.widthAnchor.constraint(equalToConstant: 28),
      learningToggleButton.heightAnchor.constraint(equalToConstant: 28),

      // Header divider
      headerDivider.topAnchor.constraint(equalTo: headerBar.bottomAnchor),
      headerDivider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      headerDivider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      headerDivider.heightAnchor.constraint(equalToConstant: 1),

      // Search bar — floating overlay in top-right of terminal container
      searchBar.topAnchor.constraint(equalTo: terminalContainer.topAnchor, constant: 8),
      searchBar.trailingAnchor.constraint(equalTo: terminalContainer.trailingAnchor, constant: -8),

      // Theme picker — floating overlay, centered horizontally, near top
      themePicker.centerXAnchor.constraint(equalTo: terminalContainer.centerXAnchor),
      themePicker.topAnchor.constraint(equalTo: terminalContainer.topAnchor, constant: 20),
      themePicker.widthAnchor.constraint(equalToConstant: 280),
      themePicker.heightAnchor.constraint(equalToConstant: 420),

      // Settings panel — floating overlay, centered horizontally, near top
      settingsPanel.centerXAnchor.constraint(equalTo: terminalContainer.centerXAnchor),
      settingsPanel.topAnchor.constraint(equalTo: terminalContainer.topAnchor, constant: 20),
      settingsPanel.widthAnchor.constraint(equalToConstant: 340),
      settingsPanel.heightAnchor.constraint(equalToConstant: 390),

      // URL preview label — bottom-left of terminal container
      linkPreviewLabel.leadingAnchor.constraint(equalTo: terminalContainer.leadingAnchor, constant: 6),
      linkPreviewLabel.bottomAnchor.constraint(equalTo: terminalContainer.bottomAnchor, constant: -4),
      linkPreviewLabel.trailingAnchor.constraint(lessThanOrEqualTo: terminalContainer.trailingAnchor, constant: -6),

      // Sidebar wrapper — below header
      sidebarWrapper.topAnchor.constraint(equalTo: headerDivider.bottomAnchor),
      sidebarWrapper.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
      sidebarWrapper.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      sidebarWidthConstraint,

      // Sidebar inside wrapper
      sidebar.topAnchor.constraint(equalTo: sidebarWrapper.topAnchor),
      sidebar.bottomAnchor.constraint(equalTo: sidebarWrapper.bottomAnchor),
      sidebar.leadingAnchor.constraint(equalTo: sidebarWrapper.leadingAnchor),
      sidebar.widthAnchor.constraint(equalToConstant: sidebarWidth),

      // Vertical divider (left sidebar)
      sidebarDivider.topAnchor.constraint(equalTo: headerDivider.bottomAnchor),
      sidebarDivider.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
      sidebarDivider.leadingAnchor.constraint(equalTo: sidebarWrapper.trailingAnchor),
      sidebarDivider.widthAnchor.constraint(equalToConstant: 1),

      // Terminal container — directly below header
      terminalContainer.topAnchor.constraint(equalTo: headerDivider.bottomAnchor),
      terminalContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
      terminalContainer.leadingAnchor.constraint(equalTo: sidebarDivider.trailingAnchor),
      terminalContainer.trailingAnchor.constraint(equalTo: learningPanelDivider.leadingAnchor),

      // Learning panel divider (right side)
      learningPanelDivider.topAnchor.constraint(equalTo: headerDivider.bottomAnchor),
      learningPanelDivider.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
      learningPanelDivider.widthAnchor.constraint(equalToConstant: 1),
      learningPanelDivider.trailingAnchor.constraint(equalTo: learningPanelWrapper.leadingAnchor),

      // Learning panel wrapper — right edge
      learningPanelWrapper.topAnchor.constraint(equalTo: headerDivider.bottomAnchor),
      learningPanelWrapper.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
      learningPanelWrapper.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      learningPanelWidthConstraint,

      // Learning panel inside wrapper (always full width)
      learningPanel.topAnchor.constraint(equalTo: learningPanelWrapper.topAnchor),
      learningPanel.bottomAnchor.constraint(equalTo: learningPanelWrapper.bottomAnchor),
      learningPanel.trailingAnchor.constraint(equalTo: learningPanelWrapper.trailingAnchor),
      learningPanel.widthAnchor.constraint(equalToConstant: learningPanelWidth),
    ])

    window.contentView = contentView
    window.minSize = NSSize(width: 400, height: 300)
    window.setFrame(initialRect, display: false)
    window.center()

    super.init(window: window)

    window.delegate = self
    toggleButton.target = self
    learningToggleButton.target = self
    sidebar.delegate = self
    claudeDetector.delegate = self
    learningEngine.delegate = self
    learningPanel.onClose = { [weak self] in self?.toggleLearningPanel() }
    themePicker.onClose = { [weak self] in self?.hideThemePicker() }
    settingsPanel.onClose = { [weak self] in self?.hideSettingsPanel() }
    learningPanel.shouldToggleLearning = { [weak self] enabled in
      guard let self else { return false }
      return !enabled || self.confirmLearningEnableIfNeeded()
    }
    learningPanel.onToggleLearning = { [weak self] enabled in
      guard let self else { return }
      if enabled {
        self.currentPhase = .inactive
        self.learningPanel.setStatus(text: "Waiting for Claude...", isActive: false)
        self.rebindDetectorForActiveSession()
      } else {
        self.currentPhase = .inactive
        self.claudeDetector.stopMonitoring()
        self.learningEngine.stop()
        self.learningPanel.setStatus(text: "Learning is off.", isActive: false)
        self.saveCurrentLearningState()
      }
    }
    // Search bar callbacks
    searchBar.onSearch = { [weak self] query in
      self?.performSearch(query: query)
    }
    searchBar.onNext = { [weak self] in
      self?.searchNext()
    }
    searchBar.onPrev = { [weak self] in
      self?.searchPrev()
    }
    searchBar.onClose = { [weak self] in
      self?.hideSearchBar()
    }

    observeNotifications()
    observeFullScreen()
    observeThemeChanges()

    // Start with one session at home directory
    addSession(workingDirectory: IdleConstants.homeDirectory)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit {
    removeAllObservers()
  }

  private func removeAllObservers() {
    if let titleObserver {
      NotificationCenter.default.removeObserver(titleObserver)
      self.titleObserver = nil
    }
    if let closeObserver {
      NotificationCenter.default.removeObserver(closeObserver)
      self.closeObserver = nil
    }
    if let pwdObserver {
      NotificationCenter.default.removeObserver(pwdObserver)
      self.pwdObserver = nil
    }
    if let searchTotalObserver {
      NotificationCenter.default.removeObserver(searchTotalObserver)
      self.searchTotalObserver = nil
    }
    if let searchSelectedObserver {
      NotificationCenter.default.removeObserver(searchSelectedObserver)
      self.searchSelectedObserver = nil
    }
    if let enterFullScreenObserver {
      NotificationCenter.default.removeObserver(enterFullScreenObserver)
      self.enterFullScreenObserver = nil
    }
    if let exitFullScreenObserver {
      NotificationCenter.default.removeObserver(exitFullScreenObserver)
      self.exitFullScreenObserver = nil
    }
    if let themeObserver {
      NotificationCenter.default.removeObserver(themeObserver)
      self.themeObserver = nil
    }
    if let commandFinishedObserver {
      NotificationCenter.default.removeObserver(commandFinishedObserver)
      self.commandFinishedObserver = nil
    }
    if let linkHoverObserver {
      NotificationCenter.default.removeObserver(linkHoverObserver)
      self.linkHoverObserver = nil
    }
  }

  override func showWindow(_ sender: Any?) {
    super.showWindow(sender)
    if let view = sessions[safe: activeSessionIndex]?.terminalView {
      window?.makeFirstResponder(view)
    }
    // Request notification permission for command-finished alerts
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
  }

  // MARK: - Header actions

  @objc private func toggleSidebarAction(_ sender: Any?) {
    toggleSidebar()
  }

  @objc private func toggleLearningPanelAction(_ sender: Any?) {
    toggleLearningPanel()
  }

  // MARK: - Header icon builders

  private static func makeSidebarToggleImage() -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
    if let symbol = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Toggle Sidebar") {
      return symbol.withSymbolConfiguration(config) ?? symbol
    }
    // Fallback for older systems
    let size = NSSize(width: 16, height: 14)
    let image = NSImage(size: size, flipped: true) { rect in
      NSColor(white: 0.55, alpha: 1).setStroke()
      let path = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 2, yRadius: 2)
      path.lineWidth = 1.2
      path.stroke()
      let divider = NSBezierPath()
      divider.move(to: NSPoint(x: 5.5, y: 1))
      divider.line(to: NSPoint(x: 5.5, y: rect.height - 1))
      divider.lineWidth = 1.2
      divider.stroke()
      return true
    }
    image.isTemplate = true
    return image
  }

  private static func makeLearningToggleImage() -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
    if let symbol = NSImage(systemSymbolName: "lightbulb", accessibilityDescription: "Toggle Learning Panel") {
      return symbol.withSymbolConfiguration(config) ?? symbol
    }
    // Fallback
    let size = NSSize(width: 16, height: 16)
    let image = NSImage(size: size, flipped: true) { rect in
      NSColor(white: 0.55, alpha: 1).setStroke()
      let path = NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2))
      path.lineWidth = 1.2
      path.stroke()
      return true
    }
    image.isTemplate = true
    return image
  }

  // MARK: - Sidebar toggle

  func toggleSidebar() {
    isSidebarVisible.toggle()
    let targetWidth: CGFloat = isSidebarVisible ? sidebarWidth : 0

    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.22
      context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      sidebarWidthConstraint.animator().constant = targetWidth
      sidebarDivider.animator().isHidden = !isSidebarVisible
    }
  }

  // MARK: - Learning panel toggle

  func toggleLearningPanel() {
    isLearningPanelVisible.toggle()
    let targetWidth: CGFloat = isLearningPanelVisible ? learningPanelWidth : 0

    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.22
      context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      learningPanelWidthConstraint.animator().constant = targetWidth
      learningPanelDivider.animator().isHidden = !isLearningPanelVisible
    }
  }

  private func showLearningPanelIfNeeded() {
    guard !isLearningPanelVisible else { return }
    toggleLearningPanel()
  }

  private func confirmLearningEnableIfNeeded() -> Bool {
    if UserDefaults.standard.bool(forKey: Self.learningConsentAcceptedKey) {
      return true
    }

    let alert = NSAlert()
    alert.messageText = "Enable Idle Learning?"
    alert.informativeText = "Idle will use your local Claude CLI/account to generate learning insights. Recent terminal context from this session may be sent to Claude, which may consume Claude tokens. Token usage is shown in the learning panel."
    alert.alertStyle = .informational
    alert.addButton(withTitle: "Enable")
    alert.addButton(withTitle: "Cancel")

    let confirmed = alert.runModal() == .alertFirstButtonReturn
    if confirmed {
      UserDefaults.standard.set(true, forKey: Self.learningConsentAcceptedKey)
    }
    return confirmed
  }

  /// Re-evaluate the active session's terminal title and rebind the detector if Claude is running.
  /// Uses processTitle (the raw Ghostty title) instead of the display title, which may have been
  /// overwritten by a PWD update.
  private func rebindDetectorForActiveSession() {
    guard learningPanel.isLearningEnabled,
          sessions.indices.contains(activeSessionIndex) else { return }
    let session = sessions[activeSessionIndex]
    let processTitle = session.processTitle
    let workingDir = session.workingDirectory
    let view = session.terminalView
    claudeDetector.titleDidChange(processTitle, workingDirectory: workingDir) { [weak view] in
      return view?.readViewportText()
    }
  }

  // MARK: - ClaudeCodeDetectorDelegate

  func claudeCodePhaseDidChange(_ phase: ClaudeCodePhase, context: ClaudeCodeContext) {
    guard learningPanel.isLearningEnabled else { return }
    currentPhase = phase

    // Tag the generation with the current session so stale callbacks are discarded
    let sessionID = sessions[safe: activeSessionIndex]?.id

    switch phase {
    case .thinking:
      showLearningPanelIfNeeded()
      learningPanel.setStatus(text: "Claude is thinking...", isActive: true)
      if let sessionID {
        learningSessionID = sessionID
        learningEngine.generate(context: context, requestID: sessionID)
      }

    case .executing:
      learningPanel.setStatus(text: "Test your knowledge!", isActive: false)
      // Start quiz if we have pending questions and no quiz in progress
      if !pendingQuestions.isEmpty && !learningPanel.isQuizInProgress {
        learningPanel.startQuiz(pendingQuestions)
        pendingQuestions = []
        saveCurrentLearningState()
      }

    case .inactive:
      learningPanel.dimPanel()
      learningPanel.setStatus(text: "Waiting for Claude...", isActive: false)
    }
  }

  // MARK: - LearningEngineDelegate

  func learningEngineDidGenerate(insights: [LearningInsight], questions: [LearningQuestion], requestID: UUID) {
    // Discard results from a session that is no longer active or if learning was disabled
    guard learningPanel.isLearningEnabled,
          requestID == learningSessionID,
          requestID == sessions[safe: activeSessionIndex]?.id else { return }

    // Show insights if no quiz is active
    if !learningPanel.isQuizInProgress {
      learningPanel.showInsights(insights)
    }

    // Queue questions for execution phase
    pendingQuestions = questions

    // If already in execution phase and no quiz running, start immediately
    if currentPhase == .executing && !learningPanel.isQuizInProgress && !questions.isEmpty {
      learningPanel.startQuiz(questions)
      pendingQuestions = []
    }

    saveCurrentLearningState()
  }

  func learningEngineDidEncounterError(_ error: String, requestID: UUID) {
    // Discard errors from a session that is no longer active
    guard requestID == learningSessionID,
          requestID == sessions[safe: activeSessionIndex]?.id else { return }
    // Don't override "Learning is off." when learning was disabled mid-flight
    guard learningPanel.isLearningEnabled else { return }
    // Show the actual error so the user knows what went wrong
    learningPanel.setStatus(text: error, isActive: false)
  }

  func learningEngineDidUpdateTokenUsage(_ usage: TokenUsage, requestID: UUID) {
    // Discard if learning was disabled or session changed
    guard learningPanel.isLearningEnabled,
          requestID == learningSessionID,
          requestID == sessions[safe: activeSessionIndex]?.id else { return }
    // Accumulate per-session (engine sends per-request deltas)
    sessions[activeSessionIndex].learningState.tokenInputs += usage.inputTokens
    sessions[activeSessionIndex].learningState.tokenOutputs += usage.outputTokens
    sessions[activeSessionIndex].learningState.tokenRequests += usage.requestCount
    let state = sessions[activeSessionIndex].learningState
    learningPanel.updateTokenUsage(input: state.tokenInputs, output: state.tokenOutputs, requests: state.tokenRequests)
  }

  private func saveCurrentLearningState() {
    guard sessions.indices.contains(activeSessionIndex) else { return }
    var state = learningPanel.currentLearningState()
    state.pendingQuestions = pendingQuestions
    sessions[activeSessionIndex].learningState = state
  }

  // MARK: - Session management

  private func addSession(workingDirectory: String) {
    let terminalView = GhosttyTerminalView(workingDirectory: workingDirectory)
    terminalView.translatesAutoresizingMaskIntoConstraints = false
    terminalView.isHidden = true
    terminalContainer.addSubview(terminalView, positioned: .below, relativeTo: searchBar)

    NSLayoutConstraint.activate([
      terminalView.topAnchor.constraint(equalTo: terminalContainer.topAnchor),
      terminalView.bottomAnchor.constraint(equalTo: terminalContainer.bottomAnchor),
      terminalView.leadingAnchor.constraint(equalTo: terminalContainer.leadingAnchor),
      terminalView.trailingAnchor.constraint(equalTo: terminalContainer.trailingAnchor),
    ])

    sessionCounter += 1
    let label = "Session \(sessionCounter)"
    let title = titleForDirectory(workingDirectory)
    let session = SessionItem(
      label: label,
      title: title,
      workingDirectory: workingDirectory,
      terminalView: terminalView
    )
    sessions.append(session)

    selectSession(at: sessions.count - 1)
    refreshGitBranch(for: sessions.count - 1)
  }

  private func selectSession(at index: Int, saveCurrentState: Bool = true, previousSessionID: UUID? = nil) {
    dispatchPrecondition(condition: .onQueue(.main))
    guard sessions.indices.contains(index) else { return }

    // Save learning state + pending questions from current session.
    // Use previousSessionID to find the session by identity when the array
    // has already been mutated and activeSessionIndex may be out of bounds.
    if saveCurrentState {
      if let prevID = previousSessionID,
         let prevIndex = sessions.firstIndex(where: { $0.id == prevID }) {
        var state = learningPanel.currentLearningState()
        state.pendingQuestions = pendingQuestions
        sessions[prevIndex].learningState = state
      } else if sessions.indices.contains(activeSessionIndex) {
        saveCurrentLearningState()
      }
    }

    let oldSessionID = previousSessionID ?? sessions[safe: activeSessionIndex]?.id
    let newSessionID = sessions[safe: index]?.id
    let sessionChanged = oldSessionID != newSessionID

    // Only stop detector/engine and dismiss search when the visible session actually changes
    if sessionChanged {
      claudeDetector.stopMonitoring()
      learningEngine.stop()

      if isSearchBarVisible {
        hideSearchBar()
      }
    }

    // Hide current (find by identity if activeSessionIndex is stale)
    let oldView: GhosttyTerminalView?
    if let prevID = previousSessionID {
      oldView = sessions.first(where: { $0.id == prevID })?.terminalView
    } else if sessions.indices.contains(activeSessionIndex) {
      oldView = sessions[activeSessionIndex].terminalView
    } else {
      oldView = nil
    }
    if sessionChanged { oldView?.isHidden = true }

    activeSessionIndex = index

    // Show new
    if let newView = sessions[index].terminalView {
      newView.isHidden = false
      window?.makeFirstResponder(newView)
    }

    // Restore learning state + pending questions for new session
    let state = sessions[index].learningState
    pendingQuestions = state.pendingQuestions
    learningSessionID = sessions[index].id
    learningPanel.restoreLearningState(state)
    if !learningPanel.isLearningEnabled {
      learningPanel.setStatus(text: "Learning is off.", isActive: false)
    }

    // Rebind detector immediately so learning picks up if Claude is already running
    rebindDetectorForActiveSession()

    sidebar.sessions = sessions
    sidebar.selectedIndex = activeSessionIndex
  }

  private func closeSession(at index: Int, skipConfirmation: Bool = false) {
    dispatchPrecondition(condition: .onQueue(.main))
    // Guard against double-close and invalid index
    guard !isClosingSession, sessions.indices.contains(index) else { return }

    // Check for running processes (unless already confirmed)
    if !skipConfirmation,
       let surface = sessions[index].terminalView?.surface,
       ghostty_surface_needs_confirm_quit(surface) {
      isClosingSession = true
      let confirmed = showCloseConfirmation()
      isClosingSession = false
      guard confirmed else { return }
    }

    isClosingSession = true
    defer { isClosingSession = false }

    // Save session info for reopen before destroying
    let session = sessions[index]
    let closedInfo = (label: session.label, workingDirectory: session.workingDirectory)
    closedSessions.append(closedInfo)
    if closedSessions.count > maxClosedSessions {
      closedSessions.removeFirst()
    }

    // Last session — tear down and close window
    if sessions.count == 1 {
      removeAllObservers()
      claudeDetector.stopMonitoring()
      learningEngine.stop()
      sessions[0].terminalView?.destroySurface()
      sessions[0].terminalView?.removeFromSuperview()
      sessions.removeAll()
      activeSessionIndex = 0
      window?.close()
      return
    }

    // Capture the active session ID before mutating the array so selectSession
    // can correctly determine whether the visible session actually changed.
    let activeIDBeforeClose = sessions[safe: activeSessionIndex]?.id

    session.terminalView?.destroySurface()
    session.terminalView?.removeFromSuperview()
    sessions.remove(at: index)

    // Adjust active index
    let newIndex: Int
    if activeSessionIndex >= sessions.count {
      newIndex = sessions.count - 1
    } else if activeSessionIndex > index {
      newIndex = activeSessionIndex - 1
    } else if activeSessionIndex == index {
      newIndex = min(index, sessions.count - 1)
    } else {
      newIndex = activeSessionIndex
    }

    selectSession(at: newIndex, saveCurrentState: activeSessionIndex != index, previousSessionID: activeIDBeforeClose)
  }

  // MARK: - Public API (AppDelegate compat)

  func addNewTab() {
    let cwd = currentSessionWorkingDirectory()
    addSession(workingDirectory: cwd)
  }

  func closeActiveTab() {
    closeSession(at: activeSessionIndex)
  }

  func selectNextTab() {
    guard !sessions.isEmpty else { return }
    selectSession(at: (activeSessionIndex + 1) % sessions.count)
  }

  func selectPreviousTab() {
    guard !sessions.isEmpty else { return }
    selectSession(at: (activeSessionIndex - 1 + sessions.count) % sessions.count)
  }

  // MARK: - SidebarDelegate

  func sidebarDidSelectSession(at index: Int) {
    selectSession(at: index)
  }

  func sidebarDidCloseSession(at index: Int) {
    closeSession(at: index)
  }

  func sidebarDidRenameSession(at index: Int, to newLabel: String) {
    guard sessions.indices.contains(index) else { return }
    sessions[index].label = newLabel
    sidebar.updateSession(at: index, with: sessions[index])
  }

  func sidebarDidClickNewSession() {
    addNewTab()
  }

  // MARK: - Git branch

  private func refreshGitBranch(for index: Int) {
    guard sessions.indices.contains(index) else { return }
    let directory = sessions[index].workingDirectory
    let sessionId = sessions[index].id

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let branch = Self.fetchGitBranch(directory: directory)
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        // Match by session ID, not index — index may have shifted
        guard let currentIndex = self.sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        self.sessions[currentIndex].gitBranch = branch
        self.sidebar.updateSession(at: currentIndex, with: self.sessions[currentIndex])
      }
    }
  }

  private static func fetchGitBranch(directory: String) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["-C", directory, "rev-parse", "--abbrev-ref", "HEAD"]
    process.standardError = FileHandle.nullDevice

    let pipe = Pipe()
    process.standardOutput = pipe

    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      return nil
    }

    guard process.terminationStatus == 0 else { return nil }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let branch = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    return branch?.isEmpty == true ? nil : branch
  }

  // MARK: - Search

  func toggleSearchBar() {
    if isSearchBarVisible {
      hideSearchBar()
    } else {
      showSearchBar()
    }
  }

  private func showSearchBar() {
    guard !isSearchBarVisible else {
      searchBar.focusSearchField()
      return
    }
    isSearchBarVisible = true
    searchBar.isHidden = false
    searchBar.alphaValue = 0
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.15
      searchBar.animator().alphaValue = 1
    }
    searchBar.focusSearchField()
  }

  private func hideSearchBar() {
    guard isSearchBarVisible else { return }
    isSearchBarVisible = false
    NSAnimationContext.runAnimationGroup({ context in
      context.duration = 0.15
      searchBar.animator().alphaValue = 0
    }, completionHandler: { [weak self] in
      self?.searchBar.isHidden = true
    })
    searchBar.clear()

    // Clear search highlighting in Ghostty
    if let surface = sessions[safe: activeSessionIndex]?.terminalView?.surface {
      let cmd = "search:"
      _ = ghostty_surface_binding_action(surface, cmd, UInt(cmd.utf8.count))
    }

    // Return focus to terminal
    if let view = sessions[safe: activeSessionIndex]?.terminalView {
      window?.makeFirstResponder(view)
    }
  }

  private func performSearch(query: String) {
    guard let surface = sessions[safe: activeSessionIndex]?.terminalView?.surface else { return }
    let cmd = "search:\(query)"
    _ = ghostty_surface_binding_action(surface, cmd, UInt(cmd.utf8.count))
  }

  private func searchNext() {
    guard let surface = sessions[safe: activeSessionIndex]?.terminalView?.surface else { return }
    let cmd = "search:next"
    _ = ghostty_surface_binding_action(surface, cmd, UInt(cmd.utf8.count))
  }

  private func searchPrev() {
    guard let surface = sessions[safe: activeSessionIndex]?.terminalView?.surface else { return }
    let cmd = "search:previous"
    _ = ghostty_surface_binding_action(surface, cmd, UInt(cmd.utf8.count))
  }

  // MARK: - Theme picker

  func toggleThemePicker() {
    if isThemePickerVisible {
      hideThemePicker()
    } else {
      showThemePicker()
    }
  }

  private func showThemePicker() {
    guard !isThemePickerVisible else { return }
    if isSettingsPanelVisible { hideSettingsPanel() }
    isThemePickerVisible = true
    themePicker.refreshSelection()
    themePicker.isHidden = false
    themePicker.alphaValue = 0
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.15
      themePicker.animator().alphaValue = 1
    }
  }

  private func hideThemePicker() {
    guard isThemePickerVisible else { return }
    isThemePickerVisible = false
    NSAnimationContext.runAnimationGroup({ context in
      context.duration = 0.15
      themePicker.animator().alphaValue = 0
    }, completionHandler: { [weak self] in
      self?.themePicker.isHidden = true
    })

    if let view = sessions[safe: activeSessionIndex]?.terminalView {
      window?.makeFirstResponder(view)
    }
  }

  // MARK: - Settings panel

  func toggleSettingsPanel() {
    if isSettingsPanelVisible {
      hideSettingsPanel()
    } else {
      showSettingsPanel()
    }
  }

  private func showSettingsPanel() {
    guard !isSettingsPanelVisible else { return }
    if isThemePickerVisible { hideThemePicker() }
    isSettingsPanelVisible = true
    settingsPanel.refreshValues()
    settingsPanel.isHidden = false
    settingsPanel.alphaValue = 0
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.15
      settingsPanel.animator().alphaValue = 1
    }
  }

  private func hideSettingsPanel() {
    guard isSettingsPanelVisible else { return }
    isSettingsPanelVisible = false
    NSAnimationContext.runAnimationGroup({ context in
      context.duration = 0.15
      settingsPanel.animator().alphaValue = 0
    }, completionHandler: { [weak self] in
      self?.settingsPanel.isHidden = true
    })

    if let view = sessions[safe: activeSessionIndex]?.terminalView {
      window?.makeFirstResponder(view)
    }
  }

  // MARK: - Reopen closed session

  func reopenClosedSession() {
    guard let closed = closedSessions.popLast() else { return }
    addSession(workingDirectory: closed.workingDirectory)
    // Restore the label
    if sessions.indices.contains(activeSessionIndex) {
      sessions[activeSessionIndex].label = closed.label
      sidebar.updateSession(at: activeSessionIndex, with: sessions[activeSessionIndex])
    }
  }

  // MARK: - Running status

  private func updateRunningStatus(for index: Int, title: String) {
    guard sessions.indices.contains(index) else { return }
    let processName = (title as NSString).lastPathComponent
    let isRunning = !shellNames.contains(processName.lowercased()) && !title.isEmpty
    sessions[index].isRunning = isRunning
    sidebar.updateSession(at: index, with: sessions[index])
  }

  // MARK: - Notifications

  private func observeNotifications() {
    titleObserver = NotificationCenter.default.addObserver(
      forName: .ghosttySetTitle,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard let self, !self.sessions.isEmpty else { return }
      guard let view = notification.object as? GhosttyTerminalView,
            let title = notification.userInfo?["title"] as? String else { return }

      if let index = self.sessions.firstIndex(where: { $0.terminalView === view }) {
        // Store the raw process title separately — not overwritten by PWD updates
        self.sessions[index].processTitle = title
        self.sessions[index].title = title
        self.updateRunningStatus(for: index, title: title)

        // Only feed active session's title changes to detector (using processTitle)
        if index == self.activeSessionIndex {
          let workingDir = self.sessions[index].workingDirectory
          self.claudeDetector.titleDidChange(title, workingDirectory: workingDir) { [weak view] in
            return view?.readViewportText()
          }
        }
      }

      self.window?.title = "Idle"
    }

    closeObserver = NotificationCenter.default.addObserver(
      forName: .ghosttyCloseSurface,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard let self, !self.sessions.isEmpty, !self.isClosingSession else { return }
      let view = notification.object as? GhosttyTerminalView
      let index = self.sessions.firstIndex(where: { $0.terminalView === view }) ?? self.activeSessionIndex
      // closeSession handles process confirmation internally
      self.closeSession(at: index)
    }

    pwdObserver = NotificationCenter.default.addObserver(
      forName: .ghosttyPWD,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard let self, !self.sessions.isEmpty else { return }
      guard let view = notification.object as? GhosttyTerminalView,
            let pwd = notification.userInfo?["pwd"] as? String else { return }

      if let index = self.sessions.firstIndex(where: { $0.terminalView === view }) {
        self.sessions[index].workingDirectory = pwd
        self.sessions[index].title = self.titleForDirectory(pwd)
        self.sidebar.updateSession(at: index, with: self.sessions[index])
        self.refreshGitBranch(for: index)

        // Keep detector's working directory in sync for the active session
        if index == self.activeSessionIndex {
          self.claudeDetector.updateWorkingDirectory(pwd)
        }
      }
    }

    searchTotalObserver = NotificationCenter.default.addObserver(
      forName: .ghosttySearchTotal,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard let self, self.isSearchBarVisible else { return }
      guard let view = notification.object as? GhosttyTerminalView,
            view === self.sessions[safe: self.activeSessionIndex]?.terminalView else { return }
      guard let total = notification.userInfo?["total"] as? Int else { return }
      self.searchBar.updateMatchCount(total: total, selected: 0)
    }

    searchSelectedObserver = NotificationCenter.default.addObserver(
      forName: .ghosttySearchSelected,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard let self, self.isSearchBarVisible else { return }
      guard let view = notification.object as? GhosttyTerminalView,
            view === self.sessions[safe: self.activeSessionIndex]?.terminalView else { return }
      guard let selected = notification.userInfo?["selected"] as? Int else { return }
      self.searchBar.updateMatchCount(total: self.searchBar.totalMatches, selected: selected)
    }

    linkHoverObserver = NotificationCenter.default.addObserver(
      forName: .ghosttyMouseOverLink,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard let self else { return }
      guard let view = notification.object as? GhosttyTerminalView,
            view === self.sessions[safe: self.activeSessionIndex]?.terminalView else { return }
      if let url = notification.userInfo?["url"] as? String {
        self.linkPreviewLabel.stringValue = "  \(url)  "
        self.linkPreviewLabel.isHidden = false
      } else {
        self.linkPreviewLabel.isHidden = true
      }
    }

    commandFinishedObserver = NotificationCenter.default.addObserver(
      forName: .ghosttyCommandFinished,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard let self else { return }
      guard let view = notification.object as? GhosttyTerminalView,
            let exitCode = notification.userInfo?["exitCode"] as? Int,
            let duration = notification.userInfo?["duration"] as? Double else { return }
      guard let index = self.sessions.firstIndex(where: { $0.terminalView === view }) else { return }

      self.sessions[index].isRunning = false
      self.sidebar.updateSession(at: index, with: self.sessions[index])

      // Only notify if app is not focused and command ran for > 5 seconds
      guard !NSApp.isActive, duration > 5.0 else { return }
      let content = UNMutableNotificationContent()
      content.title = self.sessions[index].label
      content.body = exitCode == 0
        ? "Command finished successfully (\(Self.formatDuration(duration)))"
        : "Command failed with exit code \(exitCode) (\(Self.formatDuration(duration)))"
      content.sound = .default
      let request = UNNotificationRequest(
        identifier: UUID().uuidString,
        content: content,
        trigger: nil
      )
      UNUserNotificationCenter.current().add(request)
    }
  }

  // MARK: - Full screen

  private func observeFullScreen() {
    enterFullScreenObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.willEnterFullScreenNotification,
      object: window,
      queue: .main
    ) { [weak self] _ in
      guard let self else { return }
      self.toggleLeadingConstraint.constant = self.fullScreenLeading
    }

    exitFullScreenObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.willExitFullScreenNotification,
      object: window,
      queue: .main
    ) { [weak self] _ in
      guard let self else { return }
      self.toggleLeadingConstraint.constant = self.trafficLightLeading
    }
  }

  // MARK: - Theme changes

  private func observeThemeChanges() {
    themeObserver = NotificationCenter.default.addObserver(
      forName: .idleThemeDidChange,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.refreshThemeColors()
    }
  }

  private func refreshThemeColors() {
    headerBar.layer?.backgroundColor = IdleTheme.bgColor.cgColor
    headerDivider.layer?.backgroundColor = IdleTheme.dividerColor.cgColor
    sidebarDivider.layer?.backgroundColor = IdleTheme.dividerColor.cgColor
    learningPanelDivider.layer?.backgroundColor = IdleTheme.dividerColor.cgColor
    titleLabel.textColor = IdleTheme.headerText
    window?.backgroundColor = IdleTheme.bgColor
    terminalContainer.layer?.backgroundColor = IdleTheme.bgColor.cgColor
    sidebar.refreshColors()
    learningPanel.refreshColors()
  }

  // MARK: - Helpers

  private static func formatDuration(_ seconds: Double) -> String {
    if seconds < 60 {
      return "\(Int(seconds))s"
    } else if seconds < 3600 {
      let m = Int(seconds) / 60
      let s = Int(seconds) % 60
      return "\(m)m \(s)s"
    } else {
      let h = Int(seconds) / 3600
      let m = (Int(seconds) % 3600) / 60
      return "\(h)h \(m)m"
    }
  }

  // MARK: - NSWindowDelegate

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    if hasRunningProcesses() {
      let alert = NSAlert()
      alert.messageText = "Close Window?"
      alert.informativeText = "One or more terminal sessions have running processes. Closing will terminate them."
      alert.alertStyle = .warning
      alert.addButton(withTitle: "Close")
      alert.addButton(withTitle: "Cancel")
      return alert.runModal() == .alertFirstButtonReturn
    }
    return true
  }

  // MARK: - Helpers

  /// Returns true if any session has a process that would be killed on close.
  func hasRunningProcesses() -> Bool {
    for session in sessions {
      if let surface = session.terminalView?.surface,
         ghostty_surface_needs_confirm_quit(surface) {
        return true
      }
    }
    return false
  }

  private func titleForDirectory(_ path: String) -> String {
    if path == IdleConstants.homeDirectory { return "~" }
    return (path as NSString).lastPathComponent
  }

  private func currentSessionWorkingDirectory() -> String {
    if sessions.indices.contains(activeSessionIndex) {
      return sessions[activeSessionIndex].workingDirectory
    }
    return IdleConstants.homeDirectory
  }

  private func showCloseConfirmation() -> Bool {
    let alert = NSAlert()
    alert.messageText = "Close Terminal?"
    alert.informativeText = "A process is still running. Are you sure you want to close?"
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Close")
    alert.addButton(withTitle: "Cancel")
    return alert.runModal() == .alertFirstButtonReturn
  }
}

private extension Array {
  subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
