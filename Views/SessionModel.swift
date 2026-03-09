import AppKit

// MARK: - Shared constants

enum IdleTheme {
  /// Base background color derived from the active terminal theme.
  static var bgColor: NSColor { currentBg }
  static var dividerColor: NSColor { currentBg.blending(fraction: 0.12, of: .white) }
  static var headerText: NSColor { currentFg.withAlphaComponent(0.6) }
  static var activeRowBg: NSColor { currentBg.blending(fraction: 0.10, of: .white) }
  static var hoverRowBg: NSColor { currentBg.blending(fraction: 0.06, of: .white) }
  static var inactiveRowBg: NSColor { currentBg.blending(fraction: 0.02, of: .white) }
  static var accentColor: NSColor { currentAccent }
  static var secondaryText: NSColor { currentFg.withAlphaComponent(0.5) }
  static var primaryText: NSColor { currentFg.withAlphaComponent(0.92) }

  // Backing storage — updated by ThemeManager
  private(set) static var currentBg = NSColor(srgbRed: 0.067, green: 0.067, blue: 0.075, alpha: 1)
  private(set) static var currentFg = NSColor(white: 0.92, alpha: 1)
  private(set) static var currentAccent = NSColor(srgbRed: 0.40, green: 0.56, blue: 1.0, alpha: 1)

  static func update(background: NSColor, foreground: NSColor, accent: NSColor) {
    currentBg = background
    currentFg = foreground
    currentAccent = accent
  }
}

extension NSColor {
  /// Blend toward another color by a fraction (0 = self, 1 = other).
  func blending(fraction: CGFloat, of other: NSColor) -> NSColor {
    guard let s = usingColorSpace(.sRGB), let o = other.usingColorSpace(.sRGB) else { return self }
    return NSColor(
      srgbRed: s.redComponent + (o.redComponent - s.redComponent) * fraction,
      green: s.greenComponent + (o.greenComponent - s.greenComponent) * fraction,
      blue: s.blueComponent + (o.blueComponent - s.blueComponent) * fraction,
      alpha: 1
    )
  }
}

enum IdleConstants {
  static let homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
}

enum LearningPanelMode: Int {
  case empty = 0
  case insights = 1
  case quiz = 2
  case summary = 3
}

struct LearningState {
  var mode: LearningPanelMode = .empty
  var insights: [LearningInsight] = []
  var pendingQuestions: [LearningQuestion] = []
  var quizQuestions: [LearningQuestion] = []
  var currentQuestionIndex: Int = 0
  var correctCount: Int = 0
  var answeredCount: Int = 0
  var currentQuestionAnswered: Bool = false
  var selectedOptionIndex: Int = -1
  var tokenInputs: Int = 0
  var tokenOutputs: Int = 0
  var tokenRequests: Int = 0
  var statusText: String = "Learning is off."
  var statusActive: Bool = false
}

struct SessionItem {
  let id: UUID
  var label: String
  var title: String
  /// The raw terminal title from Ghostty, used for Claude detection.
  /// Not overwritten by PWD updates, unlike `title`.
  var processTitle: String = ""
  var workingDirectory: String
  var gitBranch: String?
  var isRunning: Bool
  var terminalView: GhosttyTerminalView?
  var learningState = LearningState()

  init(
    label: String,
    title: String,
    workingDirectory: String,
    gitBranch: String? = nil,
    isRunning: Bool = false,
    terminalView: GhosttyTerminalView
  ) {
    self.id = UUID()
    self.label = label
    self.title = title
    self.processTitle = ""
    self.workingDirectory = workingDirectory
    self.gitBranch = gitBranch
    self.isRunning = isRunning
    self.terminalView = terminalView
  }
}

protocol SidebarDelegate: AnyObject {
  func sidebarDidSelectSession(at index: Int)
  func sidebarDidCloseSession(at index: Int)
  func sidebarDidRenameSession(at index: Int, to newLabel: String)
  func sidebarDidClickNewSession()
}
