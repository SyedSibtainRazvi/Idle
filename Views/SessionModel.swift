import AppKit

// MARK: - Shared constants

enum IdleTheme {
  static let bgColor = NSColor(srgbRed: 0.067, green: 0.067, blue: 0.075, alpha: 1)         // #111113
  static let dividerColor = NSColor(srgbRed: 0.16, green: 0.16, blue: 0.175, alpha: 1)       // #29292D
  static let headerText = NSColor(white: 0.55, alpha: 1)
  static let activeRowBg = NSColor(srgbRed: 0.18, green: 0.18, blue: 0.20, alpha: 1)          // #2E2E33
  static let hoverRowBg = NSColor(srgbRed: 0.125, green: 0.125, blue: 0.14, alpha: 1)         // #202024
  static let inactiveRowBg = NSColor(srgbRed: 0.098, green: 0.098, blue: 0.11, alpha: 1)      // #19191C
  static let accentColor = NSColor(srgbRed: 0.40, green: 0.56, blue: 1.0, alpha: 1)           // #668FFF
  static let secondaryText = NSColor(white: 0.48, alpha: 1)
  static let primaryText = NSColor(white: 0.92, alpha: 1)
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
