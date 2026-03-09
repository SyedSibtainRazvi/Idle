import AppKit

// MARK: - Notification Names

extension Notification.Name {
  static let ghosttySetTitle = Notification.Name("GhosttySetTitle")
  static let ghosttyPWD = Notification.Name("GhosttyPWD")
  static let ghosttyCloseSurface = Notification.Name("GhosttyCloseSurface")
  static let ghosttySearchTotal = Notification.Name("GhosttySearchTotal")
  static let ghosttySearchSelected = Notification.Name("GhosttySearchSelected")
}

// MARK: - Runtime

final class GhosttyRuntime {
  static let shared = GhosttyRuntime()

  private(set) var app: ghostty_app_t?
  private var cfg: ghostty_config_t?

  private init() {
    guard let loadedCfg = ghostty_config_new() else {
      Self.fatalDialog("Terminal configuration could not be created.")
    }
    // Idle is a standalone product, so it does not inherit the user's external
    // Ghostty configuration files. Themes and other preferences should come
    // from Idle-owned settings instead of machine-local Ghostty config.
    if let confPath = Bundle.main.path(forResource: "terminal", ofType: "conf") {
      confPath.withCString { ghostty_config_load_file(loadedCfg, $0) }
    }
    ghostty_config_finalize(loadedCfg)
    cfg = loadedCfg

    var rt = ghostty_runtime_config_s()
    rt.userdata = Unmanaged.passUnretained(self).toOpaque()
    rt.supports_selection_clipboard = true
    rt.wakeup_cb = onWakeup
    rt.action_cb = onAction
    rt.read_clipboard_cb = onReadClipboard
    rt.confirm_read_clipboard_cb = onConfirmReadClipboard
    rt.write_clipboard_cb = onWriteClipboard
    rt.close_surface_cb = onCloseSurface

    guard let instance = ghostty_app_new(&rt, loadedCfg) else {
      Self.fatalDialog("Terminal engine failed to start.")
    }
    app = instance
  }

  deinit {
    if let app { ghostty_app_free(app) }
    if let cfg { ghostty_config_free(cfg) }
  }

  @MainActor
  func setAppFocus(_ focused: Bool) {
    guard let app else { return }
    ghostty_app_set_focus(app, focused)
  }

  @MainActor
  func performTick() {
    guard let app else { return }
    ghostty_app_tick(app)
  }

  private static func fatalDialog(_ message: String) -> Never {
    let alert = NSAlert()
    alert.messageText = "Idle — Fatal Error"
    alert.informativeText = message
    alert.alertStyle = .critical
    alert.addButton(withTitle: "Quit")
    alert.runModal()
    exit(1)
  }
}

// MARK: - C Callback Functions

/// Called by the Ghostty engine when it needs the main thread to process events.
private func onWakeup(_ userdata: UnsafeMutableRawPointer?) {
  Task { @MainActor in
    GhosttyRuntime.shared.performTick()
  }
}

/// Routes Ghostty actions to the appropriate macOS behavior.
private func onAction(
  _ app: ghostty_app_t?,
  _ target: ghostty_target_s,
  _ action: ghostty_action_s
) -> Bool {
  switch action.tag {
  case GHOSTTY_ACTION_QUIT:
    DispatchQueue.main.async { NSApp.terminate(nil) }
    return true

  case GHOSTTY_ACTION_SET_TITLE:
    guard target.tag == GHOSTTY_TARGET_SURFACE,
          let titlePtr = action.action.set_title.title else { return false }
    let title = String(cString: titlePtr)
    let view = terminalViewFromTarget(target)
    DispatchQueue.main.async {
      NotificationCenter.default.post(
        name: .ghosttySetTitle,
        object: view,
        userInfo: ["title": title]
      )
    }
    return true

  case GHOSTTY_ACTION_PWD:
    guard let pwdPtr = action.action.pwd.pwd else { return true }
    let directory = String(cString: pwdPtr)
    let view = terminalViewFromTarget(target)
    DispatchQueue.main.async {
      NotificationCenter.default.post(
        name: .ghosttyPWD,
        object: view,
        userInfo: ["pwd": directory]
      )
    }
    return true

  case GHOSTTY_ACTION_MOUSE_SHAPE:
    let shape = action.action.mouse_shape
    DispatchQueue.main.async { setCursorForShape(shape) }
    return true

  case GHOSTTY_ACTION_SEARCH_TOTAL:
    let total = action.action.search_total.total
    let view = terminalViewFromTarget(target)
    DispatchQueue.main.async {
      NotificationCenter.default.post(
        name: .ghosttySearchTotal,
        object: view,
        userInfo: ["total": Int(total)]
      )
    }
    return true

  case GHOSTTY_ACTION_SEARCH_SELECTED:
    let selected = action.action.search_selected.selected
    let view = terminalViewFromTarget(target)
    DispatchQueue.main.async {
      NotificationCenter.default.post(
        name: .ghosttySearchSelected,
        object: view,
        userInfo: ["selected": Int(selected)]
      )
    }
    return true

  case GHOSTTY_ACTION_OPEN_URL:
    guard let urlPtr = action.action.open_url.url else { return false }
    let urlString = String(cString: urlPtr)
    DispatchQueue.main.async {
      // If it looks like a file path, convert to file URL
      let url: URL?
      if let candidate = URL(string: urlString), candidate.scheme != nil {
        url = candidate
      } else {
        url = URL(fileURLWithPath: urlString)
      }
      if let url { NSWorkspace.shared.open(url) }
    }
    return true

  case GHOSTTY_ACTION_RENDER:
    return true

  default:
    return false
  }
}

/// Provides clipboard content to a surface that requested a paste.
private func onReadClipboard(
  _ surfaceUserdata: UnsafeMutableRawPointer?,
  _ location: ghostty_clipboard_e,
  _ state: UnsafeMutableRawPointer?
) {
  guard let surfaceUserdata else { return }
  // Resolve the view synchronously so Swift ARC retains it before the async
  // dispatch. Deferring takeUnretainedValue() into the async block risks a
  // use-after-free if destroySurface() runs on main thread before execution.
  let view = Unmanaged<GhosttyTerminalView>.fromOpaque(surfaceUserdata).takeUnretainedValue()
  DispatchQueue.main.async {
    guard let surface = view.surface else { return }
    let content = NSPasteboard.general.string(forType: .string) ?? ""
    content.withCString { ptr in
      ghostty_surface_complete_clipboard_request(surface, ptr, state, false)
    }
  }
}

/// Shows a confirmation dialog before providing clipboard content to a surface.
private func onConfirmReadClipboard(
  _ surfaceUserdata: UnsafeMutableRawPointer?,
  _ value: UnsafePointer<CChar>?,
  _ state: UnsafeMutableRawPointer?,
  _ request: ghostty_clipboard_request_e
) {
  guard let surfaceUserdata else { return }
  // Capture C data synchronously before pointers can be freed.
  let captured = value.map { String(cString: $0) }
  let view = Unmanaged<GhosttyTerminalView>.fromOpaque(surfaceUserdata).takeUnretainedValue()

  DispatchQueue.main.async {
    guard let surface = view.surface else { return }

    let text = captured ?? NSPasteboard.general.string(forType: .string) ?? ""
    let snippet = text.count > 80 ? String(text.prefix(80)) + "..." : text

    let dialog = NSAlert()
    dialog.messageText = "Clipboard Access"
    dialog.informativeText = "A terminal program wants to read your clipboard:\n\n\"\(snippet)\"\n\nAllow?"
    dialog.alertStyle = .warning
    dialog.addButton(withTitle: "Allow")
    dialog.addButton(withTitle: "Deny")

    let granted = dialog.runModal() == .alertFirstButtonReturn
    let response = granted ? text : ""
    response.withCString { ptr in
      ghostty_surface_complete_clipboard_request(surface, ptr, state, true)
    }
  }
}

/// Writes content to the macOS clipboard, optionally with user confirmation.
private func onWriteClipboard(
  _ surfaceUserdata: UnsafeMutableRawPointer?,
  _ location: ghostty_clipboard_e,
  _ content: UnsafePointer<ghostty_clipboard_content_s>?,
  _ count: Int,
  _ requireConfirmation: Bool
) {
  guard let content, count > 0 else { return }

  // Extract text/plain synchronously before C pointers are freed.
  var extracted: String?
  for i in 0..<count {
    let entry = content[i]
    guard let mime = entry.mime, let data = entry.data else { continue }
    if String(cString: mime) == "text/plain" {
      extracted = String(cString: data)
      break
    }
  }
  guard let text = extracted else { return }

  let commitToPasteboard = {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }

  if requireConfirmation {
    DispatchQueue.main.async {
      let snippet = text.count > 80 ? String(text.prefix(80)) + "..." : text
      let dialog = NSAlert()
      dialog.messageText = "Clipboard Write"
      dialog.informativeText = "A terminal program wants to copy to clipboard:\n\n\"\(snippet)\"\n\nAllow?"
      dialog.alertStyle = .warning
      dialog.addButton(withTitle: "Allow")
      dialog.addButton(withTitle: "Deny")
      if dialog.runModal() == .alertFirstButtonReturn {
        commitToPasteboard()
      }
    }
  } else {
    DispatchQueue.main.async { commitToPasteboard() }
  }
}

/// Notifies the app that a terminal surface has been closed by the shell process.
private func onCloseSurface(
  _ surfaceUserdata: UnsafeMutableRawPointer?,
  _ processAlive: Bool
) {
  guard let surfaceUserdata else { return }
  let view = Unmanaged<GhosttyTerminalView>.fromOpaque(surfaceUserdata).takeUnretainedValue()
  DispatchQueue.main.async {
    NotificationCenter.default.post(
      name: .ghosttyCloseSurface,
      object: view,
      userInfo: ["processAlive": processAlive]
    )
  }
}

// MARK: - Helpers

private func terminalViewFromTarget(_ target: ghostty_target_s) -> GhosttyTerminalView? {
  guard target.tag == GHOSTTY_TARGET_SURFACE,
        let surface = target.target.surface,
        let ud = ghostty_surface_userdata(surface) else { return nil }
  return Unmanaged<GhosttyTerminalView>.fromOpaque(ud).takeUnretainedValue()
}

private func setCursorForShape(_ shape: ghostty_action_mouse_shape_e) {
  let cursor: NSCursor
  switch shape {
  case GHOSTTY_MOUSE_SHAPE_TEXT: cursor = .iBeam
  case GHOSTTY_MOUSE_SHAPE_POINTER: cursor = .pointingHand
  case GHOSTTY_MOUSE_SHAPE_CROSSHAIR: cursor = .crosshair
  case GHOSTTY_MOUSE_SHAPE_MOVE: cursor = .openHand
  case GHOSTTY_MOUSE_SHAPE_NOT_ALLOWED: cursor = .operationNotAllowed
  case GHOSTTY_MOUSE_SHAPE_EW_RESIZE: cursor = .resizeLeftRight
  case GHOSTTY_MOUSE_SHAPE_NS_RESIZE: cursor = .resizeUpDown
  default: cursor = .arrow
  }
  cursor.set()
}
