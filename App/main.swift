import AppKit

// Initialize the Ghostty terminal engine.
if ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) != GHOSTTY_SUCCESS {
  // Show a user-visible dialog instead of silently crashing.
  _ = NSApplication.shared
  let alert = NSAlert()
  alert.messageText = "Idle — Fatal Error"
  alert.informativeText = "The terminal engine failed to initialize. Please reinstall the application."
  alert.alertStyle = .critical
  alert.addButton(withTitle: "Quit")
  alert.runModal()
  exit(1)
}

// Process any CLI-only actions before launching the GUI.
ghostty_cli_try_action()

// Start the macOS application.
let nsApp = NSApplication.shared
let appDelegate = AppDelegate()
nsApp.delegate = appDelegate
nsApp.setActivationPolicy(.regular)
nsApp.run()
