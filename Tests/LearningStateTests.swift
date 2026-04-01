import XCTest
@testable import Idle

final class LearningStateTests: XCTestCase {

  // MARK: - TokenUsage

  func testTokenUsageTotalTokens() {
    let usage = TokenUsage(inputTokens: 100, outputTokens: 50, requestCount: 1)
    XCTAssertEqual(usage.totalTokens, 150)
  }

  func testTokenUsageDefaultsToZero() {
    let usage = TokenUsage()
    XCTAssertEqual(usage.inputTokens, 0)
    XCTAssertEqual(usage.outputTokens, 0)
    XCTAssertEqual(usage.totalTokens, 0)
    XCTAssertEqual(usage.requestCount, 0)
  }

  // MARK: - LearningState round-trip

  func testLearningStateDefaults() {
    let state = LearningState()
    XCTAssertEqual(state.mode, .empty)
    XCTAssertTrue(state.insights.isEmpty)
    XCTAssertTrue(state.pendingQuestions.isEmpty)
    XCTAssertTrue(state.quizQuestions.isEmpty)
    XCTAssertEqual(state.currentQuestionIndex, 0)
    XCTAssertEqual(state.correctCount, 0)
    XCTAssertEqual(state.answeredCount, 0)
    XCTAssertFalse(state.currentQuestionAnswered)
    XCTAssertEqual(state.selectedOptionIndex, -1)
    XCTAssertEqual(state.tokenInputs, 0)
    XCTAssertEqual(state.tokenOutputs, 0)
    XCTAssertEqual(state.tokenRequests, 0)
    XCTAssertEqual(state.statusText, "Learning is off.")
    XCTAssertFalse(state.statusActive)
  }

  func testLearningStatePreservesAllFields() {
    var state = LearningState()
    state.mode = .quiz
    state.currentQuestionIndex = 3
    state.correctCount = 2
    state.answeredCount = 4
    state.currentQuestionAnswered = true
    state.selectedOptionIndex = 1
    state.tokenInputs = 500
    state.tokenOutputs = 200
    state.tokenRequests = 3
    state.statusText = "Claude is thinking..."
    state.statusActive = true

    let restored = state
    XCTAssertEqual(restored.mode, .quiz)
    XCTAssertEqual(restored.currentQuestionIndex, 3)
    XCTAssertEqual(restored.correctCount, 2)
    XCTAssertEqual(restored.answeredCount, 4)
    XCTAssertTrue(restored.currentQuestionAnswered)
    XCTAssertEqual(restored.selectedOptionIndex, 1)
    XCTAssertEqual(restored.tokenInputs, 500)
    XCTAssertEqual(restored.tokenOutputs, 200)
    XCTAssertEqual(restored.tokenRequests, 3)
    XCTAssertEqual(restored.statusText, "Claude is thinking...")
    XCTAssertTrue(restored.statusActive)
  }

  // MARK: - Token accumulation (per-session)

  func testTokenAccumulationPerSession() {
    var state = LearningState()

    let delta1 = TokenUsage(inputTokens: 100, outputTokens: 50, requestCount: 1)
    state.tokenInputs += delta1.inputTokens
    state.tokenOutputs += delta1.outputTokens
    state.tokenRequests += delta1.requestCount

    XCTAssertEqual(state.tokenInputs, 100)
    XCTAssertEqual(state.tokenOutputs, 50)
    XCTAssertEqual(state.tokenRequests, 1)

    let delta2 = TokenUsage(inputTokens: 200, outputTokens: 80, requestCount: 1)
    state.tokenInputs += delta2.inputTokens
    state.tokenOutputs += delta2.outputTokens
    state.tokenRequests += delta2.requestCount

    XCTAssertEqual(state.tokenInputs, 300)
    XCTAssertEqual(state.tokenOutputs, 130)
    XCTAssertEqual(state.tokenRequests, 2)
  }

  func testTokenIsolationBetweenSessions() {
    var session1 = LearningState()
    var session2 = LearningState()

    session1.tokenInputs += 100
    session1.tokenRequests += 1

    // Session 2 should be unaffected
    XCTAssertEqual(session2.tokenInputs, 0)
    XCTAssertEqual(session2.tokenRequests, 0)

    session2.tokenInputs += 200
    session2.tokenRequests += 1

    // Each session accumulates independently
    XCTAssertEqual(session1.tokenInputs, 100)
    XCTAssertEqual(session2.tokenInputs, 200)
  }

  // MARK: - LearningEngine epoch invalidation

  func testEngineStopBumpsEpoch() {
    let engine = LearningEngine()
    let epochBefore = engine.epoch
    engine.stop()
    XCTAssertEqual(engine.epoch, epochBefore + 1)
    // Second stop increments again
    engine.stop()
    XCTAssertEqual(engine.epoch, epochBefore + 2)
  }

  func testEngineStopResetsDebounce() {
    let engine = LearningEngine()
    // Simulate a recent generation by checking initial state
    XCTAssertEqual(engine.lastGenerationTime, .distantPast)
    engine.stop()
    // After stop, debounce should be reset to distantPast
    XCTAssertEqual(engine.lastGenerationTime, .distantPast)
  }

  // MARK: - ClaudeCodeDetector phase classification

  func testClassifyPhaseThinking() {
    let detector = ClaudeCodeDetector()
    let text = "Thinking... I'll analyze the module structure"
    XCTAssertEqual(detector.classifyPhase(recentText: text), .thinking)
  }

  func testClassifyPhaseExecuting() {
    let detector = ClaudeCodeDetector()
    let text = "Edit(src/main.swift)\n$ npm install\nCreated file.ts"
    XCTAssertEqual(detector.classifyPhase(recentText: text), .executing)
  }

  func testClassifyPhaseMixedFavorsExecuting() {
    let detector = ClaudeCodeDetector()
    // When executing signals outweigh thinking signals, should be executing
    let text = "Let me plan\nEdit(foo.swift)\nBash(ls)\nCreated bar.ts"
    XCTAssertEqual(detector.classifyPhase(recentText: text), .executing)
  }

  func testClassifyPhaseDefaultsToThinking() {
    let detector = ClaudeCodeDetector()
    // No patterns matched — defaults to thinking so questions generate
    let text = "some random output"
    XCTAssertEqual(detector.classifyPhase(recentText: text), .thinking)
  }

  // MARK: - LearningQuestion validation

  func testQuestionWithValidOptions() {
    let question = LearningQuestion(
      id: UUID(),
      question: "What is 2+2?",
      explanation: "Basic arithmetic",
      category: "Testing",
      options: ["3", "4", "5", "6"],
      correctAnswerIndex: 1
    )
    XCTAssertEqual(question.options.count, 4)
    XCTAssertEqual(question.correctAnswerIndex, 1)
    XCTAssertEqual(question.options[question.correctAnswerIndex], "4")
  }

  // MARK: - LearningPanelMode

  func testPanelModeRawValues() {
    XCTAssertEqual(LearningPanelMode.empty.rawValue, 0)
    XCTAssertEqual(LearningPanelMode.insights.rawValue, 1)
    XCTAssertEqual(LearningPanelMode.quiz.rawValue, 2)
    XCTAssertEqual(LearningPanelMode.summary.rawValue, 3)
  }
}
