import AppKit

final class GhosttyTerminalView: NSView, NSTextInputClient {
  private(set) var surface: ghostty_surface_t?

  /// The working directory for this terminal's shell.
  let workingDirectory: String

  /// Opaque pointer from Unmanaged.passRetained(self), stored for safe release.
  private var retainedSelfPointer: UnsafeMutableRawPointer?

  /// Text accumulated from insertText during a single keyDown cycle (IME support).
  private var inputMethodBuffer: [String]?

  /// Current IME composition (preedit) string.
  private var compositionText = NSMutableAttributedString()

  /// Previous force-touch pressure stage, used to avoid duplicate reports.
  private var lastPressureStage: Int = 0

  override var acceptsFirstResponder: Bool { true }

  init(frame frameRect: NSRect = .zero, workingDirectory: String? = nil) {
    self.workingDirectory = workingDirectory ?? FileManager.default.homeDirectoryForCurrentUser.path
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.masksToBounds = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit {
    destroySurface()
  }

  /// Release the ghostty surface. Safe to call multiple times.
  func destroySurface() {
    guard let s = surface else { return }
    surface = nil
    ghostty_surface_free(s)
    if let ptr = retainedSelfPointer {
      Unmanaged<GhosttyTerminalView>.fromOpaque(ptr).release()
      retainedSelfPointer = nil
    }
  }

  // MARK: - View Lifecycle

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    assignDisplayID()
    syncSurfaceDimensions()
    DispatchQueue.main.async { [weak self] in
      self?.initializeSurfaceWhenReady()
    }
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    if let w = window {
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      layer?.contentsScale = w.backingScaleFactor
      CATransaction.commit()
    }
    guard let surface else { return }
    let backed = convertToBacking(frame)
    let xScale = backed.width / frame.width
    let yScale = backed.height / frame.height
    ghostty_surface_set_content_scale(surface, xScale, yScale)
    let sz = convertToBacking(bounds)
    ghostty_surface_set_size(
      surface,
      UInt32(max(sz.width.rounded(.down), 1)),
      UInt32(max(sz.height.rounded(.down), 1))
    )
  }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    if surface != nil { syncSurfaceDimensions() }
  }

  override func layout() {
    super.layout()
    if window != nil && bounds.width > 10 && bounds.height > 10 {
      initializeSurface()
      syncSurfaceDimensions()
    }
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach { removeTrackingArea($0) }
    addTrackingArea(NSTrackingArea(
      rect: frame,
      options: [.mouseEnteredAndExited, .mouseMoved, .inVisibleRect, .activeAlways],
      owner: self,
      userInfo: nil
    ))
  }

  // MARK: - Focus

  override func becomeFirstResponder() -> Bool {
    guard let surface else { return false }
    ghostty_surface_set_focus(surface, true)
    return true
  }

  override func resignFirstResponder() -> Bool {
    if let surface { ghostty_surface_set_focus(surface, false) }
    return true
  }

  // MARK: - Keyboard Input

  override func keyDown(with event: NSEvent) {
    guard let surface else { return super.keyDown(with: event) }

    // Fast path: Ctrl-only combinations bypass IME to prevent key drops.
    let deviceFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if deviceFlags.contains(.control) && !deviceFlags.contains(.command) && !deviceFlags.contains(.option) {
      if dispatchControlKey(event, surface: surface) { return }
    }

    let action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
    let translated = buildTranslationEvent(from: event, surface: surface)

    // Accumulate IME input.
    inputMethodBuffer = []
    defer { inputMethodBuffer = nil }

    let hadComposition = compositionText.length > 0
    interpretKeyEvents([translated])
    flushCompositionState(clearIfNeeded: hadComposition)

    // Build and dispatch the key event to Ghostty.
    var input = ghostty_input_key_s()
    input.action = action
    input.keycode = UInt32(event.keyCode)
    input.mods = extractModifiers(from: event)
    input.unshifted_codepoint = baseCodepoint(from: event)

    let accumulated = inputMethodBuffer ?? []
    if !accumulated.isEmpty {
      // IME committed text.
      input.composing = false
      input.consumed_mods = textTranslationModifiers(from: translated.modifierFlags)
      for text in accumulated {
        if isTextualInput(text) {
          text.withCString { ptr in
            input.text = ptr
            _ = ghostty_surface_key(surface, input)
          }
        } else {
          input.text = nil
          _ = ghostty_surface_key(surface, input)
        }
      }
    } else {
      input.composing = compositionText.length > 0 || hadComposition
      input.consumed_mods = textTranslationModifiers(from: translated.modifierFlags)
      if let text = resolveKeyText(for: translated), isTextualInput(text) {
        text.withCString { ptr in
          input.text = ptr
          _ = ghostty_surface_key(surface, input)
        }
      } else {
        input.text = nil
        _ = ghostty_surface_key(surface, input)
      }
    }
  }

  override func keyUp(with event: NSEvent) {
    guard let surface else { return super.keyUp(with: event) }
    var input = ghostty_input_key_s()
    input.action = GHOSTTY_ACTION_RELEASE
    input.keycode = UInt32(event.keyCode)
    input.mods = extractModifiers(from: event)
    input.consumed_mods = GHOSTTY_MODS_NONE
    input.text = nil
    input.unshifted_codepoint = baseCodepoint(from: event)
    input.composing = false
    _ = ghostty_surface_key(surface, input)
  }

  override func flagsChanged(with event: NSEvent) {
    guard let surface else { return super.flagsChanged(with: event) }
    var input = ghostty_input_key_s()
    input.action = GHOSTTY_ACTION_PRESS
    input.keycode = UInt32(event.keyCode)
    input.mods = extractModifiers(from: event)
    input.consumed_mods = GHOSTTY_MODS_NONE
    input.text = nil
    input.unshifted_codepoint = 0
    input.composing = false
    _ = ghostty_surface_key(surface, input)
  }

  // MARK: - Mouse Buttons

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    guard let surface else { return }
    ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, extractModifiers(from: event))
  }

  override func mouseUp(with event: NSEvent) {
    lastPressureStage = 0
    guard let surface else { return }
    ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, extractModifiers(from: event))
    ghostty_surface_mouse_pressure(surface, 0, 0)
  }

  override func rightMouseDown(with event: NSEvent) {
    guard let surface else { return super.rightMouseDown(with: event) }
    if !ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RIGHT, extractModifiers(from: event)) {
      super.rightMouseDown(with: event)
    }
  }

  override func rightMouseUp(with event: NSEvent) {
    guard let surface else { return super.rightMouseUp(with: event) }
    if !ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_RIGHT, extractModifiers(from: event)) {
      super.rightMouseUp(with: event)
    }
  }

  override func otherMouseDown(with event: NSEvent) {
    guard let surface else { return }
    ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, translateMouseButton(event.buttonNumber), extractModifiers(from: event))
  }

  override func otherMouseUp(with event: NSEvent) {
    guard let surface else { return }
    ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, translateMouseButton(event.buttonNumber), extractModifiers(from: event))
  }

  // MARK: - Mouse Movement

  override func mouseMoved(with event: NSEvent) {
    guard let surface else { return }
    let loc = convert(event.locationInWindow, from: nil)
    ghostty_surface_mouse_pos(surface, loc.x, frame.height - loc.y, extractModifiers(from: event))
  }

  override func mouseDragged(with event: NSEvent) { mouseMoved(with: event) }
  override func rightMouseDragged(with event: NSEvent) { mouseMoved(with: event) }
  override func otherMouseDragged(with event: NSEvent) { mouseMoved(with: event) }

  override func mouseEntered(with event: NSEvent) {
    guard let surface else { return }
    let loc = convert(event.locationInWindow, from: nil)
    ghostty_surface_mouse_pos(surface, loc.x, frame.height - loc.y, extractModifiers(from: event))
  }

  override func mouseExited(with event: NSEvent) {
    guard let surface else { return }
    if NSEvent.pressedMouseButtons != 0 { return }
    ghostty_surface_mouse_pos(surface, -1, -1, extractModifiers(from: event))
  }

  // MARK: - Scroll

  override func scrollWheel(with event: NSEvent) {
    guard let surface else { return }
    let precise = event.hasPreciseScrollingDeltas
    let dx = event.scrollingDeltaX * (precise ? 2 : 1)
    let dy = event.scrollingDeltaY * (precise ? 2 : 1)

    var scrollMods: Int32 = precise ? 1 : 0
    let momentum = momentumFromPhase(event.momentumPhase)
    scrollMods |= Int32(momentum.rawValue) << 1

    ghostty_surface_mouse_scroll(surface, dx, dy, scrollMods)
  }

  // MARK: - Force Touch

  override func pressureChange(with event: NSEvent) {
    guard let surface else { return }
    ghostty_surface_mouse_pressure(surface, UInt32(event.stage), Double(event.pressure))
    if lastPressureStage < 2 { lastPressureStage = event.stage }
  }

  // MARK: - Context Menu

  override func menu(for event: NSEvent) -> NSMenu? {
    let menu = NSMenu()
    menu.addItem(withTitle: "Copy", action: #selector(copySelection), keyEquivalent: "")
    menu.addItem(withTitle: "Paste", action: #selector(pasteClipboard), keyEquivalent: "")
    menu.addItem(.separator())
    menu.addItem(withTitle: "Select All", action: #selector(selectAllText), keyEquivalent: "")
    menu.addItem(.separator())
    menu.addItem(withTitle: "Clear", action: #selector(clearTerminal), keyEquivalent: "")
    for item in menu.items where item.action != nil {
      item.target = self
    }
    return menu
  }

  @objc private func copySelection() {
    guard let surface else { return }
    var textResult = ghostty_text_s()
    guard ghostty_surface_read_selection(surface, &textResult) else { return }
    defer { ghostty_surface_free_text(surface, &textResult) }
    guard let textPtr = textResult.text else { return }
    let copied = String(cString: textPtr)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(copied, forType: .string)
  }

  @objc private func pasteClipboard() {
    paste(nil)
  }

  @objc private func selectAllText() {
    guard let surface else { return }
    let cmd = "select_all"
    _ = ghostty_surface_binding_action(surface, cmd, UInt(cmd.utf8.count))
  }

  @objc private func clearTerminal() {
    guard let surface else { return }
    let cmd = "clear_screen"
    _ = ghostty_surface_binding_action(surface, cmd, UInt(cmd.utf8.count))
  }

  // MARK: - Viewport Text

  func readViewportText() -> String? {
    guard let surface else { return nil }

    let topLeft = ghostty_point_s(tag: GHOSTTY_POINT_VIEWPORT, coord: GHOSTTY_POINT_COORD_TOP_LEFT, x: 0, y: 0)
    let bottomRight = ghostty_point_s(tag: GHOSTTY_POINT_VIEWPORT, coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT, x: UInt32.max, y: UInt32.max)
    let sel = ghostty_selection_s(top_left: topLeft, bottom_right: bottomRight, rectangle: false)

    var result = ghostty_text_s()
    guard ghostty_surface_read_text(surface, sel, &result) else { return nil }
    defer { ghostty_surface_free_text(surface, &result) }
    guard let ptr = result.text else { return nil }
    return String(cString: ptr)
  }

  // MARK: - Paste / Send Text

  func paste(_ sender: Any?) {
    guard let text = NSPasteboard.general.string(forType: .string) else { return }
    send(text: text)
  }

  func send(text: String) {
    guard let surface else { return }
    text.withCString { ptr in
      ghostty_surface_text(surface, ptr, UInt(text.utf8.count))
    }
  }

  // MARK: - NSTextInputClient

  func hasMarkedText() -> Bool {
    compositionText.length > 0
  }

  func markedRange() -> NSRange {
    guard compositionText.length > 0 else {
      return NSRange(location: NSNotFound, length: 0)
    }
    return NSRange(location: 0, length: compositionText.length)
  }

  func selectedRange() -> NSRange {
    NSRange(location: NSNotFound, length: 0)
  }

  func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
    switch string {
    case let attr as NSAttributedString:
      compositionText = NSMutableAttributedString(attributedString: attr)
    case let plain as String:
      compositionText = NSMutableAttributedString(string: plain)
    default:
      break
    }
    if inputMethodBuffer == nil { flushCompositionState() }
  }

  func unmarkText() {
    guard compositionText.length > 0 else { return }
    compositionText.mutableString.setString("")
    flushCompositionState()
  }

  func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

  func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
    nil
  }

  func characterIndex(for point: NSPoint) -> Int { 0 }

  func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
    guard let surface else {
      return NSRect(origin: frame.origin, size: .zero)
    }
    var cx: Double = 0, cy: Double = 0, cw: Double = 0, ch: Double = 0
    ghostty_surface_ime_point(surface, &cx, &cy, &cw, &ch)
    let viewRect = NSRect(x: cx, y: frame.height - cy, width: cw, height: max(ch, 1))
    let winRect = convert(viewRect, to: nil)
    guard let w = window else { return winRect }
    return w.convertToScreen(winRect)
  }

  func insertText(_ string: Any, replacementRange: NSRange) {
    guard NSApp.currentEvent != nil else { return }
    var chars = ""
    switch string {
    case let attr as NSAttributedString: chars = attr.string
    case let plain as String: chars = plain
    default: return
    }
    unmarkText()
    if var buf = inputMethodBuffer {
      buf.append(chars)
      inputMethodBuffer = buf
      return
    }
    send(text: chars)
  }

  override func doCommand(by selector: Selector) {
    // Swallow unhandled commands to prevent NSBeep.
  }

  // MARK: - Private — Surface Management

  private func initializeSurfaceWhenReady() {
    if surface == nil && bounds.width > 10 && bounds.height > 10 {
      initializeSurface()
    }
  }

  private func initializeSurface() {
    guard surface == nil else { return }

    let opaquePtr = Unmanaged.passRetained(self).toOpaque()
    retainedSelfPointer = opaquePtr

    var cfg = ghostty_surface_config_new()
    cfg.userdata = opaquePtr
    cfg.platform_tag = GHOSTTY_PLATFORM_MACOS
    cfg.platform = ghostty_platform_u(
      macos: ghostty_platform_macos_s(nsview: Unmanaged.passUnretained(self).toOpaque())
    )
    cfg.scale_factor = resolveScaleFactor()
    cfg.font_size = Float(SettingsManager.shared.fontSize)
    cfg.context = GHOSTTY_SURFACE_CONTEXT_WINDOW

    let cwd = workingDirectory
    let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

    var created: ghostty_surface_t?
    cwd.withCString { cwdPtr in
      shell.withCString { shellPtr in
        cfg.working_directory = cwdPtr
        cfg.command = shellPtr
        created = ghostty_surface_new(GhosttyRuntime.shared.app, &cfg)
      }
    }

    guard let s = created else {
      // Surface creation failed — release the retained self to prevent leak.
      Unmanaged<GhosttyTerminalView>.fromOpaque(opaquePtr).release()
      retainedSelfPointer = nil
      return
    }
    surface = s

    assignDisplayID()
    syncSurfaceDimensions()
    ghostty_surface_set_focus(s, true)
    ghostty_surface_refresh(s)
  }

  private func assignDisplayID() {
    guard let surface,
          let screen = window?.screen ?? NSScreen.main,
          let did = screen.displayID,
          did != 0 else { return }
    ghostty_surface_set_display_id(surface, did)
  }

  private func syncSurfaceDimensions() {
    guard let surface else { return }
    let scale = resolveScaleFactor()
    ghostty_surface_set_content_scale(surface, scale, scale)
    let backed = convertToBacking(bounds)
    ghostty_surface_set_size(
      surface,
      UInt32(max(backed.width.rounded(.down), 1)),
      UInt32(max(backed.height.rounded(.down), 1))
    )
    ghostty_surface_refresh(surface)
  }

  private func resolveScaleFactor() -> Double {
    Double(window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
  }

  // MARK: - Private — Keyboard Helpers

  /// Dispatch a Ctrl-modified key directly, bypassing IME.
  private func dispatchControlKey(_ event: NSEvent, surface: ghostty_surface_t) -> Bool {
    ghostty_surface_set_focus(surface, true)

    var input = ghostty_input_key_s()
    input.action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
    input.keycode = UInt32(event.keyCode)
    input.mods = extractModifiers(from: event)
    input.consumed_mods = GHOSTTY_MODS_NONE
    input.composing = false
    input.unshifted_codepoint = baseCodepoint(from: event)

    let chars = event.charactersIgnoringModifiers ?? event.characters ?? ""
    if chars.isEmpty {
      input.text = nil
      return ghostty_surface_key(surface, input)
    }
    return chars.withCString { ptr in
      input.text = ptr
      return ghostty_surface_key(surface, input)
    }
  }

  /// Build a synthetic NSEvent with modifier flags adjusted per Ghostty config
  /// (e.g. macos-option-as-alt).
  private func buildTranslationEvent(from event: NSEvent, surface: ghostty_surface_t) -> NSEvent {
    let ghosttyMods = ghostty_surface_key_translation_mods(surface, extractModifiers(from: event))

    // Build new flags by applying the Ghostty-translated modifiers.
    var flags = event.modifierFlags.subtracting([.shift, .control, .option, .command])
    if ghosttyMods.rawValue & GHOSTTY_MODS_SHIFT.rawValue != 0 { flags.insert(.shift) }
    if ghosttyMods.rawValue & GHOSTTY_MODS_CTRL.rawValue != 0 { flags.insert(.control) }
    if ghosttyMods.rawValue & GHOSTTY_MODS_ALT.rawValue != 0 { flags.insert(.option) }
    if ghosttyMods.rawValue & GHOSTTY_MODS_SUPER.rawValue != 0 { flags.insert(.command) }

    guard flags != event.modifierFlags else { return event }

    return NSEvent.keyEvent(
      with: event.type,
      location: event.locationInWindow,
      modifierFlags: flags,
      timestamp: event.timestamp,
      windowNumber: event.windowNumber,
      context: nil,
      characters: event.characters(byApplyingModifiers: flags) ?? "",
      charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
      isARepeat: event.isARepeat,
      keyCode: event.keyCode
    ) ?? event
  }

  /// Send current IME composition state to the surface.
  private func flushCompositionState(clearIfNeeded: Bool = true) {
    guard let surface else { return }
    if compositionText.length > 0 {
      let str = compositionText.string
      let len = str.utf8CString.count
      if len > 0 {
        str.withCString { ptr in
          ghostty_surface_preedit(surface, ptr, UInt(len - 1))
        }
      }
    } else if clearIfNeeded {
      ghostty_surface_preedit(surface, nil, 0)
    }
  }

  /// Derive the text to send for a given key event. Filters out function keys
  /// and handles control character stripping.
  private func resolveKeyText(for event: NSEvent) -> String? {
    guard let chars = event.characters, !chars.isEmpty else { return nil }
    guard chars.count == 1, let scalar = chars.unicodeScalars.first else { return chars }

    // Control characters: strip control modifier so Ghostty encodes them.
    if scalar.value < 0x20 {
      let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      if flags.contains(.control) {
        return event.characters(byApplyingModifiers: event.modifierFlags.subtracting(.control))
      }
      return chars
    }

    // Private Use Area (function keys on macOS) — don't send as text.
    if scalar.value >= 0xF700 && scalar.value <= 0xF8FF {
      return nil
    }

    return chars
  }

  /// Returns true if the text contains printable characters (>= 0x20).
  private func isTextualInput(_ text: String) -> Bool {
    guard let first = text.utf8.first else { return false }
    return first >= 0x20
  }

  /// Convert NSEvent modifier flags to Ghostty modifier bitmask.
  private func extractModifiers(from event: NSEvent) -> ghostty_input_mods_e {
    var bits = GHOSTTY_MODS_NONE.rawValue
    let flags = event.modifierFlags
    if flags.contains(.shift) { bits |= GHOSTTY_MODS_SHIFT.rawValue }
    if flags.contains(.control) { bits |= GHOSTTY_MODS_CTRL.rawValue }
    if flags.contains(.option) { bits |= GHOSTTY_MODS_ALT.rawValue }
    if flags.contains(.command) { bits |= GHOSTTY_MODS_SUPER.rawValue }
    return ghostty_input_mods_e(rawValue: bits)
  }

  /// Modifiers consumed by text translation (Shift and Option only on macOS).
  private func textTranslationModifiers(from flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
    var bits = GHOSTTY_MODS_NONE.rawValue
    if flags.contains(.shift) { bits |= GHOSTTY_MODS_SHIFT.rawValue }
    if flags.contains(.option) { bits |= GHOSTTY_MODS_ALT.rawValue }
    return ghostty_input_mods_e(rawValue: bits)
  }

  /// The unshifted codepoint for a key event (used by Ghostty for keycode matching).
  private func baseCodepoint(from event: NSEvent) -> UInt32 {
    guard event.type == .keyDown || event.type == .keyUp else { return 0 }
    let chars = event.characters(byApplyingModifiers: [])
                ?? event.charactersIgnoringModifiers
                ?? event.characters
    guard let scalar = chars?.unicodeScalars.first else { return 0 }
    return scalar.value
  }

  // MARK: - Private — Mouse Helpers

  private func translateMouseButton(_ buttonNumber: Int) -> ghostty_input_mouse_button_e {
    switch buttonNumber {
    case 0: return GHOSTTY_MOUSE_LEFT
    case 1: return GHOSTTY_MOUSE_RIGHT
    case 2: return GHOSTTY_MOUSE_MIDDLE
    case 3: return GHOSTTY_MOUSE_EIGHT
    case 4: return GHOSTTY_MOUSE_NINE
    case 5: return GHOSTTY_MOUSE_SIX
    case 6: return GHOSTTY_MOUSE_SEVEN
    case 7: return GHOSTTY_MOUSE_FOUR
    case 8: return GHOSTTY_MOUSE_FIVE
    case 9: return GHOSTTY_MOUSE_TEN
    case 10: return GHOSTTY_MOUSE_ELEVEN
    default: return GHOSTTY_MOUSE_UNKNOWN
    }
  }

  private func momentumFromPhase(_ phase: NSEvent.Phase) -> ghostty_input_mouse_momentum_e {
    switch phase {
    case .began: return GHOSTTY_MOUSE_MOMENTUM_BEGAN
    case .stationary: return GHOSTTY_MOUSE_MOMENTUM_STATIONARY
    case .changed: return GHOSTTY_MOUSE_MOMENTUM_CHANGED
    case .ended: return GHOSTTY_MOUSE_MOMENTUM_ENDED
    case .cancelled: return GHOSTTY_MOUSE_MOMENTUM_CANCELLED
    case .mayBegin: return GHOSTTY_MOUSE_MOMENTUM_MAY_BEGIN
    default: return GHOSTTY_MOUSE_MOMENTUM_NONE
    }
  }
}

// MARK: - NSScreen Display ID

private extension NSScreen {
  var displayID: UInt32? {
    let key = NSDeviceDescriptionKey("NSScreenNumber")
    if let v = deviceDescription[key] as? UInt32 { return v }
    if let v = deviceDescription[key] as? Int { return UInt32(v) }
    if let v = deviceDescription[key] as? NSNumber { return v.uint32Value }
    return nil
  }
}
