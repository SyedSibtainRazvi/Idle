import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
  private var mainWindowController: MainWindowController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
    setupTerminalEnvironment()

    // Initialize the Ghostty runtime singleton.
    _ = GhosttyRuntime.shared

    installApplicationMenus()

    let controller = MainWindowController()
    mainWindowController = controller
    controller.showWindow(nil)

    // Apply saved theme and settings (deferred so surfaces are initialized first)
    DispatchQueue.main.async {
      ThemeManager.shared.applyPersistedTheme()
      SettingsManager.shared.applyPersistedSettings()
    }

    notifyFocusChange(focused: true)

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(applicationActivated),
      name: NSApplication.didBecomeActiveNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(applicationDeactivated),
      name: NSApplication.didResignActiveNotification,
      object: nil
    )

    NSApp.activate(ignoringOtherApps: true)
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard let controller = mainWindowController, controller.hasRunningProcesses() else {
      return .terminateNow
    }
    let alert = NSAlert()
    alert.messageText = "Quit Idle?"
    alert.informativeText = "One or more terminal sessions have running processes. Quitting will terminate them."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Quit")
    alert.addButton(withTitle: "Cancel")
    return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
  }

  // MARK: - Focus Tracking

  @objc private func applicationActivated(_: Notification) {
    notifyFocusChange(focused: true)
  }

  @objc private func applicationDeactivated(_: Notification) {
    notifyFocusChange(focused: false)
  }

  private func notifyFocusChange(focused: Bool) {
    Task { @MainActor in
      GhosttyRuntime.shared.setAppFocus(focused)
    }
  }

  // MARK: - Environment

  private func setupTerminalEnvironment() {
    guard let resourcesDir = Bundle.main.resourcePath else { return }
    setenv("GHOSTTY_RESOURCES_DIR", "\(resourcesDir)/ghostty", 1)
    setenv("TERMINFO_DIRS", "\(resourcesDir)/terminfo", 1)
    setenv("TERM", "xterm-ghostty", 0)
  }

  // MARK: - Menu Bar

  private func installApplicationMenus() {
    let mainMenu = NSMenu()

    // App menu
    let appItem = NSMenuItem()
    let appMenu = NSMenu()
    appMenu.addItem(withTitle: "About Idle", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
    appMenu.addItem(.separator())
    appMenu.addItem(withTitle: "Settings…", action: #selector(handleSettings), keyEquivalent: ",")
    appMenu.addItem(.separator())
    appMenu.addItem(withTitle: "Hide Idle", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
    let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
    hideOthers.keyEquivalentModifierMask = [.command, .option]
    appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
    appMenu.addItem(.separator())
    appMenu.addItem(withTitle: "Quit Idle", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appItem.submenu = appMenu
    mainMenu.addItem(appItem)

    // File menu
    let fileItem = NSMenuItem()
    let fileMenu = NSMenu(title: "File")
    fileMenu.addItem(withTitle: "New Session", action: #selector(handleNewSession), keyEquivalent: "t")
    fileMenu.addItem(withTitle: "Close Session", action: #selector(handleCloseSession), keyEquivalent: "w")
    let reopenItem = fileMenu.addItem(withTitle: "Reopen Closed Session", action: #selector(handleReopenClosedSession), keyEquivalent: "t")
    reopenItem.keyEquivalentModifierMask = [.command, .shift]
    fileItem.submenu = fileMenu
    mainMenu.addItem(fileItem)

    // Edit menu
    let editItem = NSMenuItem()
    let editMenu = NSMenu(title: "Edit")
    editMenu.addItem(withTitle: "Copy", action: #selector(handleCopy), keyEquivalent: "c")
    editMenu.addItem(withTitle: "Paste", action: #selector(handlePaste), keyEquivalent: "v")
    editMenu.addItem(withTitle: "Select All", action: #selector(handleSelectAll), keyEquivalent: "a")
    editMenu.addItem(.separator())
    editMenu.addItem(withTitle: "Find…", action: #selector(handleFind), keyEquivalent: "f")
    editItem.submenu = editMenu
    mainMenu.addItem(editItem)

    // View menu
    let viewItem = NSMenuItem()
    let viewMenu = NSMenu(title: "View")
    let increaseItem = viewMenu.addItem(withTitle: "Increase Font Size", action: #selector(handleIncreaseFontSize), keyEquivalent: "+")
    increaseItem.keyEquivalentModifierMask = [.command]
    let decreaseItem = viewMenu.addItem(withTitle: "Decrease Font Size", action: #selector(handleDecreaseFontSize), keyEquivalent: "-")
    decreaseItem.keyEquivalentModifierMask = [.command]
    let resetItem = viewMenu.addItem(withTitle: "Reset Font Size", action: #selector(handleResetFontSize), keyEquivalent: "0")
    resetItem.keyEquivalentModifierMask = [.command]
    viewMenu.addItem(.separator())
    let themeItem = viewMenu.addItem(withTitle: "Theme…", action: #selector(handleThemePicker), keyEquivalent: "k")
    themeItem.keyEquivalentModifierMask = [.command]
    viewItem.submenu = viewMenu
    mainMenu.addItem(viewItem)

    // Window menu
    let windowItem = NSMenuItem()
    let windowMenu = NSMenu(title: "Window")
    windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
    windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.zoom(_:)), keyEquivalent: "")
    windowMenu.addItem(.separator())
    windowMenu.addItem(withTitle: "Toggle Sidebar", action: #selector(handleToggleSidebar), keyEquivalent: "b")
    let learningItem = windowMenu.addItem(withTitle: "Toggle Learning Panel", action: #selector(handleToggleLearningPanel), keyEquivalent: "l")
    learningItem.keyEquivalentModifierMask = [.command, .shift]
    windowMenu.addItem(.separator())
    windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
    windowMenu.addItem(.separator())
    let nextItem = windowMenu.addItem(withTitle: "Next Session", action: #selector(handleNextSession), keyEquivalent: "]")
    nextItem.keyEquivalentModifierMask = [.command, .shift]
    let prevItem = windowMenu.addItem(withTitle: "Previous Session", action: #selector(handlePreviousSession), keyEquivalent: "[")
    prevItem.keyEquivalentModifierMask = [.command, .shift]
    windowItem.submenu = windowMenu
    mainMenu.addItem(windowItem)

    // Help menu
    let helpItem = NSMenuItem()
    let helpMenu = NSMenu(title: "Help")
    helpItem.submenu = helpMenu
    mainMenu.addItem(helpItem)

    NSApp.mainMenu = mainMenu
    NSApp.windowsMenu = windowMenu
    NSApp.helpMenu = helpMenu
  }

  // MARK: - Menu Actions

  @objc private func handleNewSession(_ sender: Any?) {
    activeMainWindowController?.addNewTab()
  }

  @objc private func handleCloseSession(_ sender: Any?) {
    activeMainWindowController?.closeActiveTab()
  }

  @objc private func handleToggleSidebar(_ sender: Any?) {
    activeMainWindowController?.toggleSidebar()
  }

  @objc private func handleToggleLearningPanel(_ sender: Any?) {
    activeMainWindowController?.toggleLearningPanel()
  }

  @objc private func handleNextSession(_ sender: Any?) {
    activeMainWindowController?.selectNextTab()
  }

  @objc private func handlePreviousSession(_ sender: Any?) {
    activeMainWindowController?.selectPreviousTab()
  }

  @objc private func handleCopy(_ sender: Any?) {
    guard let terminal = locateActiveTerminal() else { return }
    guard let surface = terminal.surface else { return }

    var textResult = ghostty_text_s()
    guard ghostty_surface_read_selection(surface, &textResult) else { return }
    defer { ghostty_surface_free_text(surface, &textResult) }

    // Null-safe: text pointer may be nil if selection is empty.
    guard let textPtr = textResult.text else { return }
    let copied = String(cString: textPtr)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(copied, forType: .string)
  }

  @objc private func handlePaste(_ sender: Any?) {
    locateActiveTerminal()?.paste(sender)
  }

  @objc private func handleSelectAll(_ sender: Any?) {
    guard let surface = locateActiveTerminal()?.surface else { return }
    let cmd = "select_all"
    _ = ghostty_surface_binding_action(surface, cmd, UInt(cmd.utf8.count))
  }

  @objc private func handleFind(_ sender: Any?) {
    activeMainWindowController?.toggleSearchBar()
  }

  @objc private func handleIncreaseFontSize(_ sender: Any?) {
    guard let surface = locateActiveTerminal()?.surface else { return }
    let cmd = "increase_font_size:1"
    _ = ghostty_surface_binding_action(surface, cmd, UInt(cmd.utf8.count))
  }

  @objc private func handleDecreaseFontSize(_ sender: Any?) {
    guard let surface = locateActiveTerminal()?.surface else { return }
    let cmd = "decrease_font_size:1"
    _ = ghostty_surface_binding_action(surface, cmd, UInt(cmd.utf8.count))
  }

  @objc private func handleResetFontSize(_ sender: Any?) {
    guard let surface = locateActiveTerminal()?.surface else { return }
    let cmd = "reset_font_size"
    _ = ghostty_surface_binding_action(surface, cmd, UInt(cmd.utf8.count))
  }

  @objc private func handleReopenClosedSession(_ sender: Any?) {
    activeMainWindowController?.reopenClosedSession()
  }

  @objc private func handleThemePicker(_ sender: Any?) {
    activeMainWindowController?.toggleThemePicker()
  }

  @objc private func handleSettings(_ sender: Any?) {
    activeMainWindowController?.toggleSettingsPanel()
  }

  // MARK: - Helpers

  private var activeMainWindowController: MainWindowController? {
    NSApp.keyWindow?.windowController as? MainWindowController
  }

  private func locateActiveTerminal() -> GhosttyTerminalView? {
    guard let contentView = NSApp.keyWindow?.contentView else { return nil }
    return locateTerminalView(in: contentView)
  }

  private func locateTerminalView(in view: NSView) -> GhosttyTerminalView? {
    if view.isHidden { return nil }
    if let terminal = view as? GhosttyTerminalView { return terminal }
    for child in view.subviews {
      if let found = locateTerminalView(in: child) { return found }
    }
    return nil
  }
}
