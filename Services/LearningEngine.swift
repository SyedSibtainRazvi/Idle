import Foundation

// MARK: - Types

struct LearningInsight: Identifiable {
  let id: UUID
  let title: String
  let explanation: String
  let category: String
}

struct LearningQuestion: Identifiable {
  let id: UUID
  let question: String
  let explanation: String
  let category: String
  let options: [String]       // exactly 4 options
  let correctAnswerIndex: Int // 0-3
}

struct TokenUsage {
  var inputTokens: Int = 0
  var outputTokens: Int = 0
  var totalTokens: Int { inputTokens + outputTokens }
  var requestCount: Int = 0
}

protocol LearningEngineDelegate: AnyObject {
  func learningEngineDidGenerate(insights: [LearningInsight], questions: [LearningQuestion], requestID: UUID)
  func learningEngineDidEncounterError(_ error: String, requestID: UUID)
  func learningEngineDidUpdateTokenUsage(_ usage: TokenUsage, requestID: UUID)
}

// MARK: - Engine

final class LearningEngine {
  weak var delegate: LearningEngineDelegate?

  private var currentProcess: Process?
  private let processLock = NSLock()
  /// Monotonic counter incremented on every stop(). Callbacks check this to
  /// discard results from invalidated generations.
  private(set) var epoch: UInt64 = 0
  private(set) var lastGenerationTime: Date = .distantPast
  private let debounceInterval: TimeInterval = 10.0
  private let processTimeout: TimeInterval = 60.0
  private let generationQueue = DispatchQueue(label: "com.idle.learning-engine", qos: .utility)
  private var claudeBinaryPath: String?

  deinit {
    stop()
  }

  // MARK: - Public API

  func generate(context: ClaudeCodeContext, requestID: UUID) {
    let now = Date()
    guard now.timeIntervalSince(lastGenerationTime) >= debounceInterval else { return }
    lastGenerationTime = now

    processLock.lock()
    let capturedEpoch = epoch
    processLock.unlock()

    generationQueue.async { [weak self] in
      self?.performGeneration(context: context, requestID: requestID, epoch: capturedEpoch)
    }
  }

  func stop() {
    processLock.lock()
    epoch += 1
    let proc = currentProcess
    currentProcess = nil
    processLock.unlock()
    proc?.terminate()
    // Reset debounce so the next session can generate immediately
    lastGenerationTime = .distantPast
  }

  // MARK: - Private

  private func performGeneration(context: ClaudeCodeContext, requestID: UUID, epoch: UInt64) {
    guard let claudePath = findClaudeBinary() else {
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.processLock.lock()
        let stale = epoch != self.epoch
        self.processLock.unlock()
        guard !stale else { return }
        self.delegate?.learningEngineDidEncounterError("Claude CLI not found in PATH", requestID: requestID)
      }
      return
    }

    // Check epoch again before launching — stop() may have been called while
    // this block was queued on generationQueue.
    processLock.lock()
    let staleBeforeRun = epoch != self.epoch
    processLock.unlock()
    guard !staleBeforeRun else { return }

    let prompt = buildPrompt(context: context)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: claudePath)
    process.arguments = ["--print", "-p", prompt]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    processLock.lock()
    currentProcess = process
    processLock.unlock()

    do {
      try process.run()
    } catch {
      processLock.lock()
      currentProcess = nil
      let staleAfterFail = epoch != self.epoch
      processLock.unlock()
      guard !staleAfterFail else { return }
      DispatchQueue.main.async { [weak self] in
        self?.delegate?.learningEngineDidEncounterError("Failed to run claude: \(error.localizedDescription)", requestID: requestID)
      }
      return
    }

    // Wait with timeout to prevent indefinite hangs.
    let timeoutWork = DispatchWorkItem { process.terminate() }
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + processTimeout, execute: timeoutWork)
    process.waitUntilExit()
    timeoutWork.cancel()

    processLock.lock()
    currentProcess = nil
    let stale = epoch != self.epoch
    processLock.unlock()

    // If stop() was called (epoch bumped) while the process was running,
    // discard everything — this generation is no longer wanted.
    guard !stale else { return }

    guard process.terminationStatus == 0 else {
      let wasTimedOut = !timeoutWork.isCancelled
      let message = wasTimedOut
        ? "Claude CLI timed out after \(Int(processTimeout))s"
        : "Claude exited with status \(process.terminationStatus)"
      DispatchQueue.main.async { [weak self] in
        self?.delegate?.learningEngineDidEncounterError(message, requestID: requestID)
      }
      return
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8), !output.isEmpty else {
      DispatchQueue.main.async { [weak self] in
        self?.delegate?.learningEngineDidEncounterError("Empty response from claude", requestID: requestID)
      }
      return
    }

    // Estimate token usage (~4 chars per token) — per-request, not accumulated.
    // The delegate is responsible for accumulating per-session.
    let usage = TokenUsage(
      inputTokens: prompt.count / 4,
      outputTokens: output.count / 4,
      requestCount: 1
    )

    let (insights, questions) = parseResponse(from: output)
    DispatchQueue.main.async { [weak self] in
      self?.delegate?.learningEngineDidUpdateTokenUsage(usage, requestID: requestID)
      if insights.isEmpty && questions.isEmpty {
        self?.delegate?.learningEngineDidEncounterError("Could not parse response", requestID: requestID)
      } else {
        self?.delegate?.learningEngineDidGenerate(insights: insights, questions: questions, requestID: requestID)
      }
    }
  }

  private func findClaudeBinary() -> String? {
    if let cached = claudeBinaryPath {
      return cached
    }

    // Search common paths
    let searchPaths = [
      "/usr/local/bin/claude",
      "/opt/homebrew/bin/claude",
      "\(NSHomeDirectory())/.local/bin/claude",
      "\(NSHomeDirectory())/.npm-global/bin/claude",
    ]

    for path in searchPaths {
      if FileManager.default.isExecutableFile(atPath: path) {
        claudeBinaryPath = path
        return path
      }
    }

    // Try `which` as fallback
    let whichProcess = Process()
    whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    whichProcess.arguments = ["claude"]
    let whichPipe = Pipe()
    whichProcess.standardOutput = whichPipe
    whichProcess.standardError = FileHandle.nullDevice

    do {
      try whichProcess.run()
      whichProcess.waitUntilExit()
      if whichProcess.terminationStatus == 0 {
        let data = whichPipe.fileHandleForReading.readDataToEndOfFile()
        if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty {
          claudeBinaryPath = path
          return path
        }
      }
    } catch {}

    return nil
  }

  private func buildPrompt(context: ClaudeCodeContext) -> String {
    let recentOutput = String(context.recentOutput.prefix(2000))

    return """
    You are helping a developer learn while an AI coding assistant works on their code.
    The AI assistant is currently thinking/planning in a terminal session.

    Working directory: \(context.workingDirectory)

    Recent terminal output:
    ```
    \(recentOutput)
    ```

    Generate educational content about what the AI is doing. Provide:
    1. 2-3 contextual insights — short explanations of what the AI is currently analyzing and why it matters
    2. 5 multiple-choice quiz questions testing understanding of the concepts being applied

    Each quiz question must have exactly 4 options with one correct answer.
    Shuffle the correct answer position across questions.

    Respond ONLY with valid JSON in this exact format (no markdown, no backticks):
    {
      "insights": [
        {
          "category": "Architecture",
          "title": "Analyzing Module Structure",
          "explanation": "Claude is examining how the codebase splits responsibilities across files. This modular pattern makes each piece independently testable and reusable."
        }
      ],
      "questions": [
        {
          "category": "Architecture",
          "question": "Why is the code being split into separate modules?",
          "options": ["To make the repo larger", "To separate concerns for testability and reuse", "To slow down compilation", "To confuse other developers"],
          "correctAnswerIndex": 1,
          "explanation": "Modular architecture separates concerns, making code easier to test, maintain, and reuse."
        }
      ]
    }

    Categories should be one of: Architecture, Git, Testing, Performance, Security, Patterns, Debugging, DevOps
    """
  }

  private func parseResponse(from output: String) -> (insights: [LearningInsight], questions: [LearningQuestion]) {
    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)

    // Find JSON object boundaries
    guard let startIndex = trimmed.firstIndex(of: "{"),
          let endIndex = trimmed.lastIndex(of: "}") else {
      return ([], [])
    }

    let jsonString = String(trimmed[startIndex...endIndex])
    guard let jsonData = jsonString.data(using: .utf8) else { return ([], []) }

    struct RawInsight: Decodable {
      let category: String
      let title: String
      let explanation: String
    }

    struct RawQuestion: Decodable {
      let category: String
      let question: String
      let explanation: String
      let options: [String]
      let correctAnswerIndex: Int
    }

    struct RawResponse: Decodable {
      let insights: [RawInsight]?
      let questions: [RawQuestion]?
    }

    do {
      let raw = try JSONDecoder().decode(RawResponse.self, from: jsonData)

      let insights = (raw.insights ?? []).map { r in
        LearningInsight(id: UUID(), title: r.title, explanation: r.explanation, category: r.category)
      }

      let questions = (raw.questions ?? []).compactMap { r -> LearningQuestion? in
        guard r.options.count == 4,
              r.correctAnswerIndex >= 0,
              r.correctAnswerIndex < 4 else {
          return nil
        }
        return LearningQuestion(
          id: UUID(),
          question: r.question,
          explanation: r.explanation,
          category: r.category,
          options: r.options,
          correctAnswerIndex: r.correctAnswerIndex
        )
      }

      return (insights, questions)
    } catch {
      NSLog("[LearningEngine] JSON parse error: %@", error.localizedDescription)
      return ([], [])
    }
  }
}
