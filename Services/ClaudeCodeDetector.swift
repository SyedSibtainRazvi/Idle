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
}

// MARK: - Detector

final class ClaudeCodeDetector {
  weak var delegate: ClaudeCodeDetectorDelegate?

  private(set) var currentPhase: ClaudeCodePhase = .inactive
  private var pollingTimer: DispatchSourceTimer?
  private var isClaudeRunning = false
  private var readViewportText: (() -> String?)?
  /// The current working directory, updated live when the user `cd`s.
  private var currentWorkingDirectory: String = ""
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
    "Planning",
    "Analyzing",
    "considering",
    "approach",
  ]

  private let executingPatterns: [String] = [
    "Write(",
    "Edit(",
    "Bash(",
    "Read(",
    "Grep(",
    "Glob(",
    "$ ",
    "running ",
    "Created ",
    "Updated ",
  ]

  deinit {
    stopMonitoring()
  }

  // MARK: - Public API

  /// Call when the terminal title changes. Starts/stops monitoring based on whether "claude" is in the title.
  /// Must be called on main thread.
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

  /// Update the working directory without restarting monitoring.
  /// Call when the user `cd`s inside an active Claude session.
  func updateWorkingDirectory(_ directory: String) {
    dispatchPrecondition(condition: .onQueue(.main))
    currentWorkingDirectory = directory
  }

  /// Stop all monitoring and reset phase. Call on session close or tab switch.
  /// Must be called on main thread.
  func stopMonitoring() {
    dispatchPrecondition(condition: .onQueue(.main))
    epoch += 1
    pollingTimer?.cancel()
    pollingTimer = nil
    isClaudeRunning = false
    readViewportText = nil
    currentPhase = .inactive
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

  private func pollTerminal(epoch: UInt64) {
    // Dispatch all work to main thread to avoid deadlock.
    // Classification is fast (string matching), so main thread is fine.
    DispatchQueue.main.async { [weak self] in
      guard let self, self.isClaudeRunning, epoch == self.epoch else { return }
      guard let text = self.readViewportText?(), !text.isEmpty else { return }

      let lines = text.components(separatedBy: .newlines)
      let recentLines = lines.suffix(30)
      let recentText = recentLines.joined(separator: "\n")

      let phase = self.classifyPhase(recentText: recentText)
      let context = ClaudeCodeContext(
        workingDirectory: self.currentWorkingDirectory,
        recentOutput: recentText,
        planningText: phase == .thinking ? self.extractThinkingBlock(from: recentText) : ""
      )

      self.setPhase(phase, context: context)
    }
  }

  func classifyPhase(recentText: String) -> ClaudeCodePhase {
    var thinkingScore = 0
    var executingScore = 0

    for pattern in thinkingPatterns {
      if recentText.contains(pattern) {
        thinkingScore += 1
      }
    }

    for pattern in executingPatterns {
      if recentText.contains(pattern) {
        executingScore += 1
      }
    }

    if executingScore > thinkingScore {
      return .executing
    } else if thinkingScore > 0 {
      return .thinking
    }
    return .executing // Default to executing when claude is running but phase is unclear
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

  private func setPhase(_ newPhase: ClaudeCodePhase, context: ClaudeCodeContext) {
    guard newPhase != currentPhase else { return }
    currentPhase = newPhase
    delegate?.claudeCodePhaseDidChange(newPhase, context: context)
  }
}
