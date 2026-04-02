import Foundation

// MARK: - Types

enum ClaudeCodePhase {
  case inactive
  case thinking
  case executing
}

struct ClaudeCodeContext {
  let workingDirectory: String
  let recentOutput: String
  let planningText: String
}

protocol ClaudeCodeDetectorDelegate: AnyObject {
  func claudeCodePhaseDidChange(_ phase: ClaudeCodePhase, context: ClaudeCodeContext)
  func claudeCodeContextDidUpdate(_ phase: ClaudeCodePhase, context: ClaudeCodeContext)
}

// MARK: - Detector

final class ClaudeCodeDetector {
  weak var delegate: ClaudeCodeDetectorDelegate?

  private(set) var currentPhase: ClaudeCodePhase = .inactive
  private var pollingTimer: DispatchSourceTimer?
  private var isClaudeRunning = false
  private var readViewportText: (() -> String?)?
  private var currentWorkingDirectory: String = ""
  /// Hash of last viewport text to detect when content actually changes.
  private var lastContentHash: Int = 0
  /// Monotonic counter incremented on every stopMonitoring(). Stale poll
  /// callbacks check this to avoid firing after the detector was rebound.
  private var epoch: UInt64 = 0

  private let pollingInterval: TimeInterval = 2.0
  private let pollingQueue = DispatchQueue(label: "com.idle.claude-detector", qos: .utility)

  private let thinkingPatterns: [String] = [
    "Thinking...",
    "thinking",
    "I'll ",
    "I will ",
    "Let me ",
    "## Plan",
    "# Plan",
    "Planning",
    "Analyzing",
    "considering",
    "approach",
    "I need to",
    "The issue",
    "Looking at",
    "strategy",
    "investigate",
    "understand",
    "Step ",
    "First,",
    "Then,",
  ]

  private let executingPatterns: [String] = [
    "Write(",
    "Edit(",
    "Bash(",
    "Read(",
    "Grep(",
    "Glob(",
    "Agent(",
    "Skill(",
    "TaskCreate(",
    "TaskUpdate(",
    "WebFetch(",
    "WebSearch(",
    "NotebookEdit(",
    "$ ",
    "running ",
    "Created ",
    "Updated ",
    "Compiling",
    "Building",
  ]

  deinit {
    stopMonitoring()
  }

  // MARK: - Public API

  func titleDidChange(_ title: String, workingDirectory: String, viewportReader: @escaping () -> String?) {
    dispatchPrecondition(condition: .onQueue(.main))
    let isClaudeInTitle = title.lowercased().contains("claude")
    readViewportText = viewportReader
    currentWorkingDirectory = workingDirectory

    if isClaudeInTitle && !isClaudeRunning {
      isClaudeRunning = true
      startPolling()
    } else if !isClaudeInTitle && isClaudeRunning {
      stopMonitoring()
      setPhase(.inactive, context: ClaudeCodeContext(
        workingDirectory: workingDirectory,
        recentOutput: "",
        planningText: ""
      ))
    }
  }

  func startContentDetection(workingDirectory: String, viewportReader: @escaping () -> String?) {
    dispatchPrecondition(condition: .onQueue(.main))
    readViewportText = viewportReader
    currentWorkingDirectory = workingDirectory
    guard pollingTimer == nil else { return }
    startPolling()
  }

  func updateWorkingDirectory(_ directory: String) {
    dispatchPrecondition(condition: .onQueue(.main))
    currentWorkingDirectory = directory
  }

  func stopMonitoring() {
    dispatchPrecondition(condition: .onQueue(.main))
    epoch += 1
    pollingTimer?.cancel()
    pollingTimer = nil
    isClaudeRunning = false
    readViewportText = nil
    currentPhase = .inactive
    lastContentHash = 0
  }

  // MARK: - Polling

  private func startPolling() {
    stopPollingTimer()

    let capturedEpoch = epoch
    let timer = DispatchSource.makeTimerSource(queue: pollingQueue)
    timer.schedule(deadline: .now(), repeating: pollingInterval)
    timer.setEventHandler { [weak self] in
      self?.pollTerminal(epoch: capturedEpoch)
    }
    timer.resume()
    pollingTimer = timer
  }

  private func stopPollingTimer() {
    pollingTimer?.cancel()
    pollingTimer = nil
  }

  private static let contentMarkers: [String] = [
    "\u{2B58}",  // ⏺ — Claude Code's prompt symbol
    "\u{25CF}",  // ● — alternate bullet
    "Claude Code",
  ]

  private func pollTerminal(epoch: UInt64) {
    DispatchQueue.main.async { [weak self] in
      guard let self, epoch == self.epoch else { return }
      guard let text = self.readViewportText?(), !text.isEmpty else { return }

      if !self.isClaudeRunning {
        let hasMarker = Self.contentMarkers.contains { text.contains($0) }
        guard hasMarker else { return }
        self.isClaudeRunning = true
      }

      let lines = text.components(separatedBy: .newlines)
      let recentLines = lines.suffix(30)
      let recentText = recentLines.joined(separator: "\n")
      let contentHash = recentText.hashValue

      let phase = self.classifyPhase(recentText: recentText)
      let context = ClaudeCodeContext(
        workingDirectory: self.currentWorkingDirectory,
        recentOutput: recentText,
        planningText: phase == .thinking ? self.extractThinkingBlock(from: recentText) : ""
      )

      // Always notify on phase change
      if phase != self.currentPhase {
        self.currentPhase = phase
        self.lastContentHash = contentHash
        self.delegate?.claudeCodePhaseDidChange(phase, context: context)
        return
      }

      // Also notify when content changes within the same phase
      if contentHash != self.lastContentHash {
        self.lastContentHash = contentHash
        self.delegate?.claudeCodeContextDidUpdate(phase, context: context)
      }
    }
  }

  func classifyPhase(recentText: String) -> ClaudeCodePhase {
    let lines = recentText.components(separatedBy: .newlines)

    for line in lines.reversed() {
      let isThinking = thinkingPatterns.contains { line.contains($0) }
      let isExecuting = executingPatterns.contains { line.contains($0) }

      if isExecuting && !isThinking {
        return .executing
      }
      if isThinking && !isExecuting {
        return .thinking
      }
    }
    return .executing
  }

  private func extractThinkingBlock(from text: String) -> String {
    let lines = text.components(separatedBy: .newlines)
    var thinkingLines: [String] = []
    var inThinking = false

    for line in lines {
      if thinkingPatterns.contains(where: { line.contains($0) }) {
        inThinking = true
      }
      if inThinking {
        thinkingLines.append(line)
      }
      if executingPatterns.contains(where: { line.contains($0) }) {
        inThinking = false
      }
    }

    return thinkingLines.joined(separator: "\n")
  }
}
