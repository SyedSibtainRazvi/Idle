import AppKit

// MARK: - InsightCardView

private final class InsightCardView: NSView {
  private let categoryBadge = NSTextField()
  private let titleLabel = NSTextField()
  private let explanationLabel = NSTextField()

  var insight: LearningInsight? {
    didSet { configure() }
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setup()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setup() {
    wantsLayer = true
    layer?.backgroundColor = IdleTheme.activeRowBg.cgColor
    layer?.cornerRadius = 8

    categoryBadge.translatesAutoresizingMaskIntoConstraints = false
    categoryBadge.font = NSFont.systemFont(ofSize: 10, weight: .medium)
    categoryBadge.textColor = IdleTheme.accentColor
    categoryBadge.backgroundColor = IdleTheme.accentColor.withAlphaComponent(0.15)
    categoryBadge.isBordered = false
    categoryBadge.isEditable = false
    categoryBadge.isSelectable = false
    categoryBadge.wantsLayer = true
    categoryBadge.layer?.cornerRadius = 4
    categoryBadge.alignment = .center
    addSubview(categoryBadge)

    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
    titleLabel.textColor = IdleTheme.primaryText
    titleLabel.backgroundColor = .clear
    titleLabel.isBordered = false
    titleLabel.isEditable = false
    titleLabel.isSelectable = false
    titleLabel.lineBreakMode = .byWordWrapping
    titleLabel.maximumNumberOfLines = 0
    titleLabel.preferredMaxLayoutWidth = 260
    titleLabel.cell?.wraps = true
    addSubview(titleLabel)

    explanationLabel.translatesAutoresizingMaskIntoConstraints = false
    explanationLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
    explanationLabel.textColor = IdleTheme.secondaryText
    explanationLabel.backgroundColor = .clear
    explanationLabel.isBordered = false
    explanationLabel.isEditable = false
    explanationLabel.isSelectable = true
    explanationLabel.lineBreakMode = .byWordWrapping
    explanationLabel.maximumNumberOfLines = 0
    explanationLabel.preferredMaxLayoutWidth = 260
    explanationLabel.cell?.wraps = true
    addSubview(explanationLabel)

    NSLayoutConstraint.activate([
      categoryBadge.topAnchor.constraint(equalTo: topAnchor, constant: 12),
      categoryBadge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
      categoryBadge.heightAnchor.constraint(equalToConstant: 18),

      titleLabel.topAnchor.constraint(equalTo: categoryBadge.bottomAnchor, constant: 8),
      titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
      titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),

      explanationLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
      explanationLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
      explanationLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
      explanationLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
    ])
  }

  private func configure() {
    guard let insight else { return }
    categoryBadge.stringValue = "  \(insight.category)  "
    titleLabel.stringValue = insight.title
    explanationLabel.stringValue = insight.explanation
  }
}

// MARK: - OptionRowView

private final class OptionRowView: NSView {
  let index: Int
  init(index: Int) {
    self.index = index
    super.init(frame: .zero)
  }
  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

// MARK: - QuizCardView

private final class QuizCardView: NSView {
  private let categoryBadge = NSTextField()
  private let questionLabel = NSTextField()
  private var optionRows: [OptionRowView] = []
  private var optionLabels: [NSTextField] = []
  private let explanationLabel = NSTextField()
  private let nextButton = NSButton()
  private let optionsStack = NSStackView()

  private(set) var answered = false
  private(set) var selectedOptionIndex: Int = -1
  var isInteractionEnabled = true

  var question: LearningQuestion? {
    didSet { configure() }
  }

  var onAnswered: ((Bool) -> Void)?
  var onNext: (() -> Void)?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setup()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setup() {
    wantsLayer = true
    layer?.backgroundColor = IdleTheme.activeRowBg.cgColor
    layer?.cornerRadius = 8

    categoryBadge.translatesAutoresizingMaskIntoConstraints = false
    categoryBadge.font = NSFont.systemFont(ofSize: 10, weight: .medium)
    categoryBadge.textColor = IdleTheme.accentColor
    categoryBadge.backgroundColor = IdleTheme.accentColor.withAlphaComponent(0.15)
    categoryBadge.isBordered = false
    categoryBadge.isEditable = false
    categoryBadge.isSelectable = false
    categoryBadge.wantsLayer = true
    categoryBadge.layer?.cornerRadius = 4
    categoryBadge.alignment = .center
    addSubview(categoryBadge)

    questionLabel.translatesAutoresizingMaskIntoConstraints = false
    questionLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
    questionLabel.textColor = IdleTheme.primaryText
    questionLabel.backgroundColor = .clear
    questionLabel.isBordered = false
    questionLabel.isEditable = false
    questionLabel.isSelectable = false
    questionLabel.lineBreakMode = .byWordWrapping
    questionLabel.maximumNumberOfLines = 0
    questionLabel.preferredMaxLayoutWidth = 260
    questionLabel.cell?.wraps = true
    addSubview(questionLabel)

    optionsStack.translatesAutoresizingMaskIntoConstraints = false
    optionsStack.orientation = .vertical
    optionsStack.spacing = 8
    optionsStack.alignment = .leading
    addSubview(optionsStack)

    let prefixes = ["A.", "B.", "C.", "D."]
    for i in 0..<4 {
      let row = OptionRowView(index: i)
      row.translatesAutoresizingMaskIntoConstraints = false
      row.wantsLayer = true
      row.layer?.backgroundColor = IdleTheme.hoverRowBg.cgColor
      row.layer?.cornerRadius = 6

      let label = NSTextField()
      label.translatesAutoresizingMaskIntoConstraints = false
      label.font = NSFont.systemFont(ofSize: 12, weight: .regular)
      label.textColor = IdleTheme.primaryText
      label.backgroundColor = .clear
      label.isBordered = false
      label.isEditable = false
      label.isSelectable = false
      label.lineBreakMode = .byWordWrapping
      label.maximumNumberOfLines = 0
      label.preferredMaxLayoutWidth = 240
      label.cell?.wraps = true
      label.stringValue = "\(prefixes[i]) Option"
      row.addSubview(label)

      NSLayoutConstraint.activate([
        label.topAnchor.constraint(equalTo: row.topAnchor, constant: 8),
        label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 10),
        label.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -10),
        label.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -8),
      ])

      let click = NSClickGestureRecognizer(target: self, action: #selector(optionTapped(_:)))
      row.addGestureRecognizer(click)

      optionsStack.addArrangedSubview(row)
      row.widthAnchor.constraint(equalTo: optionsStack.widthAnchor).isActive = true

      optionRows.append(row)
      optionLabels.append(label)
    }

    explanationLabel.translatesAutoresizingMaskIntoConstraints = false
    explanationLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
    explanationLabel.textColor = IdleTheme.secondaryText
    explanationLabel.backgroundColor = .clear
    explanationLabel.isBordered = false
    explanationLabel.isEditable = false
    explanationLabel.isSelectable = true
    explanationLabel.lineBreakMode = .byWordWrapping
    explanationLabel.maximumNumberOfLines = 0
    explanationLabel.preferredMaxLayoutWidth = 260
    explanationLabel.cell?.wraps = true
    explanationLabel.isHidden = true
    addSubview(explanationLabel)

    nextButton.translatesAutoresizingMaskIntoConstraints = false
    nextButton.title = "Next"
    nextButton.bezelStyle = .rounded
    nextButton.contentTintColor = IdleTheme.accentColor
    nextButton.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
    nextButton.target = self
    nextButton.action = #selector(nextTapped)
    nextButton.isHidden = true
    addSubview(nextButton)

    NSLayoutConstraint.activate([
      categoryBadge.topAnchor.constraint(equalTo: topAnchor, constant: 14),
      categoryBadge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
      categoryBadge.heightAnchor.constraint(equalToConstant: 18),

      questionLabel.topAnchor.constraint(equalTo: categoryBadge.bottomAnchor, constant: 10),
      questionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
      questionLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),

      optionsStack.topAnchor.constraint(equalTo: questionLabel.bottomAnchor, constant: 14),
      optionsStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
      optionsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),

      explanationLabel.topAnchor.constraint(equalTo: optionsStack.bottomAnchor, constant: 12),
      explanationLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
      explanationLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),

      nextButton.topAnchor.constraint(equalTo: explanationLabel.bottomAnchor, constant: 10),
      nextButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
      nextButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
    ])
  }

  private func configure() {
    guard let question else { return }
    answered = false
    categoryBadge.stringValue = "  \(question.category)  "
    questionLabel.stringValue = question.question
    explanationLabel.stringValue = question.explanation
    explanationLabel.isHidden = true
    nextButton.isHidden = true

    let prefixes = ["A.", "B.", "C.", "D."]
    for i in 0..<4 {
      optionLabels[i].stringValue = "\(prefixes[i]) \(question.options[i])"
      optionLabels[i].textColor = IdleTheme.primaryText
      optionRows[i].layer?.backgroundColor = IdleTheme.hoverRowBg.cgColor
      optionRows[i].alphaValue = 1.0
      optionRows[i].gestureRecognizers.forEach { optionRows[i].removeGestureRecognizer($0) }
      let click = NSClickGestureRecognizer(target: self, action: #selector(optionTapped(_:)))
      optionRows[i].addGestureRecognizer(click)
    }
  }

  func restoreAnswered(selectedIndex: Int) {
    guard let question, selectedIndex >= 0, selectedIndex < 4 else { return }
    answered = true
    self.selectedOptionIndex = selectedIndex
    applyAnswerHighlights(selectedIndex: selectedIndex, correctIndex: question.correctAnswerIndex)
  }

  @objc private func optionTapped(_ sender: NSClickGestureRecognizer) {
    guard isInteractionEnabled, !answered, let question, let row = sender.view as? OptionRowView else { return }
    answered = true
    let selectedIndex = row.index
    selectedOptionIndex = selectedIndex
    let isCorrect = selectedIndex == question.correctAnswerIndex
    applyAnswerHighlights(selectedIndex: selectedIndex, correctIndex: question.correctAnswerIndex)
    onAnswered?(isCorrect)
  }

  private func applyAnswerHighlights(selectedIndex: Int, correctIndex: Int) {
    let correctBg = NSColor(srgbRed: 0.20, green: 0.78, blue: 0.35, alpha: 0.2)
    let wrongBg = NSColor(srgbRed: 0.95, green: 0.30, blue: 0.30, alpha: 0.2)

    for i in 0..<4 {
      if i == correctIndex {
        optionRows[i].layer?.backgroundColor = correctBg.cgColor
      } else if i == selectedIndex {
        optionRows[i].layer?.backgroundColor = wrongBg.cgColor
      } else {
        optionRows[i].alphaValue = 0.4
      }
      optionRows[i].gestureRecognizers.forEach { optionRows[i].removeGestureRecognizer($0) }
    }

    explanationLabel.isHidden = false
    nextButton.isHidden = false
  }

  @objc private func nextTapped() {
    guard isInteractionEnabled else { return }
    onNext?()
  }

  override func resetCursorRects() {
    if !answered {
      for row in optionRows {
        addCursorRect(convert(row.bounds, from: row), cursor: .pointingHand)
      }
    }
  }
}

// MARK: - Pulsing Status Dot

private final class PulsingDotView: NSView {
  private var isPulsing = false

  var dotColor: NSColor = NSColor(srgbRed: 0.24, green: 0.80, blue: 0.44, alpha: 1) {
    didSet { needsDisplay = true }
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func draw(_ dirtyRect: NSRect) {
    dotColor.setFill()
    let dotRect = bounds.insetBy(dx: 1, dy: 1)
    NSBezierPath(ovalIn: dotRect).fill()
  }

  func startPulsing() {
    guard !isPulsing else { return }
    isPulsing = true

    let anim = CABasicAnimation(keyPath: "opacity")
    anim.fromValue = 1.0
    anim.toValue = 0.3
    anim.duration = 0.8
    anim.autoreverses = true
    anim.repeatCount = .infinity
    layer?.add(anim, forKey: "pulse")
  }

  func stopPulsing() {
    isPulsing = false
    layer?.removeAnimation(forKey: "pulse")
    layer?.opacity = 1.0
  }
}

// MARK: - LearningPanelView

final class LearningPanelView: NSView {
  private let headerView = NSView()
  private let headerLabel = NSTextField()
  private let toggleSwitch = NSSwitch()
  private let closeButton = PointerButton()
  private let statusBar = NSView()
  private let statusDot = PulsingDotView()
  private let statusLabel = NSTextField()
  private let disclosureLabel = NSTextField()
  private let progressRow = NSView()
  private let progressLabel = NSTextField()
  private let scoreLabel = NSTextField()
  private let contentScrollView = NSScrollView()
  private let scrollDocumentView = NSView()
  private let insightsStack = NSStackView()
  private let quizCard = QuizCardView()
  private let completionLabel = NSTextField()
  private let emptyLabel = NSTextField()
  private let startQuizButton = PointerButton()
  private let tokenFooter = NSView()
  private let tokenFooterDivider = NSView()
  private let tokenFooterLabel = NSTextField()

  private var mode: LearningPanelMode = .empty
  private var insights: [LearningInsight] = []
  private var quizQuestions: [LearningQuestion] = []
  private var currentQuestionIndex = 0
  private var correctCount = 0
  private var answeredCount = 0
  private var tokenInputs = 0
  private var tokenOutputs = 0
  private var tokenRequests = 0
  private(set) var isLearningEnabled = false

  var onClose: (() -> Void)?
  var shouldToggleLearning: ((Bool) -> Bool)?
  var onToggleLearning: ((Bool) -> Void)?
  var onStartQuiz: (() -> Void)?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setup()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - Public API

  var isQuizInProgress: Bool {
    mode == .quiz
  }

  private(set) var hasPendingQuiz = false

  func setHasPendingQuiz(_ pending: Bool) {
    hasPendingQuiz = pending
    if mode == .insights {
      applyMode(.insights)
    }
  }

  func showInsights(_ newInsights: [LearningInsight]) {
    guard mode != .quiz else { return } // never interrupt a quiz
    insights = newInsights
    if insights.isEmpty {
      applyMode(.empty)
    } else {
      rebuildInsightCards()
      applyMode(.insights)
    }
  }

  func startQuiz(_ questions: [LearningQuestion]) {
    guard !questions.isEmpty else { return }
    quizQuestions = questions
    currentQuestionIndex = 0
    correctCount = 0
    answeredCount = 0
    applyMode(.quiz)
    showCurrentQuestion()
  }

  func setStatus(text: String, isActive: Bool) {
    statusLabel.stringValue = text
    if isActive {
      statusDot.dotColor = NSColor(srgbRed: 0.24, green: 0.80, blue: 0.44, alpha: 1)
      statusDot.startPulsing()
      statusLabel.textColor = IdleTheme.primaryText
    } else {
      statusDot.dotColor = IdleTheme.secondaryText
      statusDot.stopPulsing()
      statusLabel.textColor = IdleTheme.secondaryText
    }
  }

  func updateTokenUsage(input: Int, output: Int, requests: Int) {
    tokenInputs = input
    tokenOutputs = output
    tokenRequests = requests
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    let inputStr = formatter.string(from: NSNumber(value: input)) ?? "\(input)"
    let outputStr = formatter.string(from: NSNumber(value: output)) ?? "\(output)"
    tokenFooterLabel.stringValue = "~\(inputStr) in / ~\(outputStr) out  \u{00B7}  \(requests) request\(requests == 1 ? "" : "s")"
  }

  func dimPanel() {
    statusLabel.textColor = IdleTheme.secondaryText
    statusDot.stopPulsing()
    statusDot.dotColor = IdleTheme.secondaryText
  }

  func currentLearningState() -> LearningState {
    var state = LearningState(
      mode: mode,
      insights: insights,
      pendingQuestions: [],
      quizQuestions: quizQuestions,
      currentQuestionIndex: currentQuestionIndex,
      correctCount: correctCount,
      answeredCount: answeredCount,
      currentQuestionAnswered: quizCard.answered,
      selectedOptionIndex: quizCard.selectedOptionIndex,
      tokenInputs: tokenInputs,
      tokenOutputs: tokenOutputs,
      tokenRequests: tokenRequests
    )
    state.statusText = statusLabel.stringValue
    state.statusActive = statusDot.layer?.animation(forKey: "pulse") != nil
    return state
  }

  func restoreLearningState(_ state: LearningState) {
    insights = state.insights
    quizQuestions = state.quizQuestions
    currentQuestionIndex = state.currentQuestionIndex
    correctCount = state.correctCount
    answeredCount = state.answeredCount

    // Restore status bar
    setStatus(text: state.statusText, isActive: state.statusActive)

    // Restore per-session token footer
    if state.tokenRequests > 0 {
      updateTokenUsage(input: state.tokenInputs, output: state.tokenOutputs, requests: state.tokenRequests)
    } else {
      tokenInputs = 0
      tokenOutputs = 0
      tokenRequests = 0
      tokenFooterLabel.stringValue = "0 tokens"
    }

    switch state.mode {
    case .empty:
      applyMode(.empty)
    case .insights:
      rebuildInsightCards()
      applyMode(.insights)
    case .quiz:
      if currentQuestionIndex < quizQuestions.count {
        applyMode(.quiz)
        showCurrentQuestion()
        // Restore answered state if the user had already answered this question
        if state.currentQuestionAnswered {
          quizCard.restoreAnswered(selectedIndex: state.selectedOptionIndex)
        }
      } else {
        applyMode(.summary)
      }
    case .summary:
      applyMode(.summary)
    }
  }

  // MARK: - Mode management

  private func applyMode(_ newMode: LearningPanelMode) {
    mode = newMode

    // Remove all content from scroll document
    scrollDocumentView.subviews.forEach { $0.removeFromSuperview() }

    switch mode {
    case .empty:
      contentScrollView.isHidden = true
      progressRow.isHidden = true
      completionLabel.isHidden = true
      emptyLabel.isHidden = false

    case .insights:
      contentScrollView.isHidden = false
      progressRow.isHidden = true
      completionLabel.isHidden = true
      emptyLabel.isHidden = true
      startQuizButton.isHidden = !hasPendingQuiz

      scrollDocumentView.addSubview(insightsStack)
      insightsStack.translatesAutoresizingMaskIntoConstraints = false

      if hasPendingQuiz {
        scrollDocumentView.addSubview(startQuizButton)
        startQuizButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
          insightsStack.topAnchor.constraint(equalTo: scrollDocumentView.topAnchor, constant: 4),
          insightsStack.leadingAnchor.constraint(equalTo: scrollDocumentView.leadingAnchor),
          insightsStack.trailingAnchor.constraint(equalTo: scrollDocumentView.trailingAnchor),

          startQuizButton.topAnchor.constraint(equalTo: insightsStack.bottomAnchor, constant: 12),
          startQuizButton.centerXAnchor.constraint(equalTo: scrollDocumentView.centerXAnchor),
          startQuizButton.widthAnchor.constraint(equalToConstant: 200),
          startQuizButton.heightAnchor.constraint(equalToConstant: 36),
          startQuizButton.bottomAnchor.constraint(equalTo: scrollDocumentView.bottomAnchor, constant: -8),
        ])
      } else {
        NSLayoutConstraint.activate([
          insightsStack.topAnchor.constraint(equalTo: scrollDocumentView.topAnchor, constant: 4),
          insightsStack.leadingAnchor.constraint(equalTo: scrollDocumentView.leadingAnchor),
          insightsStack.trailingAnchor.constraint(equalTo: scrollDocumentView.trailingAnchor),
          insightsStack.bottomAnchor.constraint(equalTo: scrollDocumentView.bottomAnchor, constant: -4),
        ])
      }

    case .quiz:
      contentScrollView.isHidden = false
      progressRow.isHidden = false
      completionLabel.isHidden = true
      emptyLabel.isHidden = true

      scrollDocumentView.addSubview(quizCard)
      quizCard.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([
        quizCard.topAnchor.constraint(equalTo: scrollDocumentView.topAnchor, constant: 4),
        quizCard.leadingAnchor.constraint(equalTo: scrollDocumentView.leadingAnchor),
        quizCard.trailingAnchor.constraint(equalTo: scrollDocumentView.trailingAnchor),
        quizCard.bottomAnchor.constraint(equalTo: scrollDocumentView.bottomAnchor, constant: -4),
      ])

    case .summary:
      contentScrollView.isHidden = true
      progressRow.isHidden = false
      completionLabel.isHidden = false
      emptyLabel.isHidden = true
      completionLabel.stringValue = "Quiz Complete! \(correctCount)/\(quizQuestions.count) correct"
      progressLabel.stringValue = "Done"
      scoreLabel.stringValue = "\(correctCount)/\(quizQuestions.count) correct"
    }
  }

  // MARK: - Quiz state

  private func showCurrentQuestion() {
    guard currentQuestionIndex < quizQuestions.count else {
      applyMode(.summary)
      return
    }
    quizCard.question = quizQuestions[currentQuestionIndex]
    progressLabel.stringValue = "Question \(currentQuestionIndex + 1) of \(quizQuestions.count)"
    scoreLabel.stringValue = answeredCount > 0 ? "\(correctCount)/\(answeredCount) correct" : ""
    contentScrollView.documentView?.scroll(.zero)
  }

  // MARK: - Insight cards

  private func rebuildInsightCards() {
    insightsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    for insight in insights {
      let card = InsightCardView()
      card.translatesAutoresizingMaskIntoConstraints = false
      card.insight = insight
      insightsStack.addArrangedSubview(card)
      card.widthAnchor.constraint(equalTo: insightsStack.widthAnchor).isActive = true
    }
  }

  // MARK: - Setup

  private func setup() {
    wantsLayer = true
    layer?.backgroundColor = IdleTheme.bgColor.cgColor

    setupHeader()
    setupStatusBar()
    setupDisclosureLabel()
    setupProgressRow()
    setupScrollView()
    setupStartQuizButton()
    setupCompletionLabel()
    setupEmptyState()
    setupTokenFooter()
    layoutViews()

    quizCard.onAnswered = { [weak self] isCorrect in
      guard let self else { return }
      self.answeredCount += 1
      if isCorrect { self.correctCount += 1 }
      self.scoreLabel.stringValue = "\(self.correctCount)/\(self.answeredCount) correct"
    }

    quizCard.onNext = { [weak self] in
      guard let self else { return }
      self.currentQuestionIndex += 1
      self.showCurrentQuestion()
    }

    setStatus(text: "Learning is off.", isActive: false)
    applyLearningEnabled(false, animated: false, updateSwitch: true)
  }

  private func setupHeader() {
    headerView.translatesAutoresizingMaskIntoConstraints = false
    headerView.wantsLayer = true
    headerView.layer?.backgroundColor = IdleTheme.bgColor.cgColor
    addSubview(headerView)

    headerLabel.translatesAutoresizingMaskIntoConstraints = false
    headerLabel.stringValue = "Idle Learning"
    headerLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
    headerLabel.textColor = IdleTheme.headerText
    headerLabel.backgroundColor = .clear
    headerLabel.isBordered = false
    headerLabel.isEditable = false
    headerLabel.isSelectable = false
    headerView.addSubview(headerLabel)

    toggleSwitch.translatesAutoresizingMaskIntoConstraints = false
    toggleSwitch.state = .off
    toggleSwitch.controlSize = .mini
    toggleSwitch.target = self
    toggleSwitch.action = #selector(toggleLearning(_:))
    toggleSwitch.toolTip = "Send terminal context to Claude CLI for learning insights (uses API tokens)"
    headerView.addSubview(toggleSwitch)

    closeButton.translatesAutoresizingMaskIntoConstraints = false
    closeButton.bezelStyle = .recessed
    closeButton.isBordered = false
    closeButton.title = ""
    let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
    if let xImage = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close") {
      closeButton.image = xImage.withSymbolConfiguration(config) ?? xImage
    } else {
      closeButton.title = "x"
    }
    closeButton.imagePosition = .imageOnly
    closeButton.target = self
    closeButton.action = #selector(closePanel)
    closeButton.toolTip = "Close Learning Panel"
    headerView.addSubview(closeButton)
  }

  private func setupStatusBar() {
    statusBar.translatesAutoresizingMaskIntoConstraints = false
    statusBar.wantsLayer = true
    addSubview(statusBar)

    statusDot.translatesAutoresizingMaskIntoConstraints = false
    statusBar.addSubview(statusDot)

    statusLabel.translatesAutoresizingMaskIntoConstraints = false
    statusLabel.stringValue = "Learning is off."
    statusLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
    statusLabel.textColor = IdleTheme.secondaryText
    statusLabel.backgroundColor = .clear
    statusLabel.isBordered = false
    statusLabel.isEditable = false
    statusLabel.isSelectable = false
    statusBar.addSubview(statusLabel)
  }

  private func setupDisclosureLabel() {
    disclosureLabel.translatesAutoresizingMaskIntoConstraints = false
    disclosureLabel.stringValue = "Uses your Claude CLI/account when enabled. Recent terminal context from this session may be sent to Claude. Token usage is shown below."
    disclosureLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
    disclosureLabel.textColor = IdleTheme.secondaryText
    disclosureLabel.backgroundColor = .clear
    disclosureLabel.isBordered = false
    disclosureLabel.isEditable = false
    disclosureLabel.isSelectable = false
    disclosureLabel.maximumNumberOfLines = 0
    disclosureLabel.lineBreakMode = .byWordWrapping
    addSubview(disclosureLabel)
  }

  private func setupProgressRow() {
    progressRow.translatesAutoresizingMaskIntoConstraints = false
    progressRow.isHidden = true
    addSubview(progressRow)

    progressLabel.translatesAutoresizingMaskIntoConstraints = false
    progressLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
    progressLabel.textColor = IdleTheme.accentColor
    progressLabel.backgroundColor = .clear
    progressLabel.isBordered = false
    progressLabel.isEditable = false
    progressLabel.isSelectable = false
    progressLabel.stringValue = ""
    progressRow.addSubview(progressLabel)

    scoreLabel.translatesAutoresizingMaskIntoConstraints = false
    scoreLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
    scoreLabel.textColor = IdleTheme.accentColor
    scoreLabel.backgroundColor = .clear
    scoreLabel.isBordered = false
    scoreLabel.isEditable = false
    scoreLabel.isSelectable = false
    scoreLabel.alignment = .right
    scoreLabel.stringValue = ""
    progressRow.addSubview(scoreLabel)
  }

  private func setupScrollView() {
    contentScrollView.translatesAutoresizingMaskIntoConstraints = false
    contentScrollView.hasVerticalScroller = true
    contentScrollView.hasHorizontalScroller = false
    contentScrollView.autohidesScrollers = true
    contentScrollView.drawsBackground = false
    contentScrollView.borderType = .noBorder
    contentScrollView.isHidden = true
    addSubview(contentScrollView)

    scrollDocumentView.translatesAutoresizingMaskIntoConstraints = false

    // Configure insights stack
    insightsStack.orientation = .vertical
    insightsStack.spacing = 10
    insightsStack.alignment = .leading

    let clipView = NSClipView()
    clipView.translatesAutoresizingMaskIntoConstraints = false
    clipView.drawsBackground = false
    clipView.documentView = scrollDocumentView
    contentScrollView.contentView = clipView
  }

  private func setupCompletionLabel() {
    completionLabel.translatesAutoresizingMaskIntoConstraints = false
    completionLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
    completionLabel.textColor = IdleTheme.accentColor
    completionLabel.backgroundColor = .clear
    completionLabel.isBordered = false
    completionLabel.isEditable = false
    completionLabel.isSelectable = false
    completionLabel.alignment = .center
    completionLabel.maximumNumberOfLines = 0
    completionLabel.lineBreakMode = .byWordWrapping
    completionLabel.isHidden = true
    addSubview(completionLabel)
  }

  private func setupStartQuizButton() {
    startQuizButton.translatesAutoresizingMaskIntoConstraints = false
    startQuizButton.title = "Start Quiz"
    startQuizButton.bezelStyle = .rounded
    startQuizButton.isBordered = false
    startQuizButton.wantsLayer = true
    startQuizButton.layer?.backgroundColor = IdleTheme.accentColor.cgColor
    startQuizButton.layer?.cornerRadius = 8
    startQuizButton.contentTintColor = .white
    startQuizButton.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
    startQuizButton.target = self
    startQuizButton.action = #selector(startQuizTapped)
    startQuizButton.isHidden = true
  }

  @objc private func startQuizTapped() {
    onStartQuiz?()
  }

  private func setupEmptyState() {
    emptyLabel.translatesAutoresizingMaskIntoConstraints = false
    emptyLabel.stringValue = "Questions will appear here\nwhen Claude is thinking"
    emptyLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
    emptyLabel.textColor = IdleTheme.secondaryText
    emptyLabel.backgroundColor = .clear
    emptyLabel.isBordered = false
    emptyLabel.isEditable = false
    emptyLabel.isSelectable = false
    emptyLabel.alignment = .center
    emptyLabel.maximumNumberOfLines = 0
    emptyLabel.lineBreakMode = .byWordWrapping
    addSubview(emptyLabel)
  }

  private func setupTokenFooter() {
    tokenFooter.translatesAutoresizingMaskIntoConstraints = false
    tokenFooter.wantsLayer = true
    tokenFooter.layer?.backgroundColor = IdleTheme.bgColor.cgColor
    addSubview(tokenFooter)

    tokenFooterDivider.translatesAutoresizingMaskIntoConstraints = false
    tokenFooterDivider.wantsLayer = true
    tokenFooterDivider.layer?.backgroundColor = IdleTheme.dividerColor.cgColor
    tokenFooter.addSubview(tokenFooterDivider)

    tokenFooterLabel.translatesAutoresizingMaskIntoConstraints = false
    tokenFooterLabel.stringValue = "0 tokens"
    tokenFooterLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
    tokenFooterLabel.textColor = IdleTheme.secondaryText
    tokenFooterLabel.backgroundColor = .clear
    tokenFooterLabel.isBordered = false
    tokenFooterLabel.isEditable = false
    tokenFooterLabel.isSelectable = false
    tokenFooterLabel.lineBreakMode = .byTruncatingTail
    tokenFooter.addSubview(tokenFooterLabel)
  }

  private func layoutViews() {
    NSLayoutConstraint.activate([
      // Header
      headerView.topAnchor.constraint(equalTo: topAnchor),
      headerView.leadingAnchor.constraint(equalTo: leadingAnchor),
      headerView.trailingAnchor.constraint(equalTo: trailingAnchor),
      headerView.heightAnchor.constraint(equalToConstant: 32),

      headerLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 12),
      headerLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

      toggleSwitch.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
      toggleSwitch.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -6),

      closeButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -8),
      closeButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
      closeButton.widthAnchor.constraint(equalToConstant: 20),
      closeButton.heightAnchor.constraint(equalToConstant: 20),

      // Status bar
      statusBar.topAnchor.constraint(equalTo: headerView.bottomAnchor),
      statusBar.leadingAnchor.constraint(equalTo: leadingAnchor),
      statusBar.trailingAnchor.constraint(equalTo: trailingAnchor),
      statusBar.heightAnchor.constraint(equalToConstant: 24),

      statusDot.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor, constant: 12),
      statusDot.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
      statusDot.widthAnchor.constraint(equalToConstant: 8),
      statusDot.heightAnchor.constraint(equalToConstant: 8),

      statusLabel.leadingAnchor.constraint(equalTo: statusDot.trailingAnchor, constant: 6),
      statusLabel.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
      statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: statusBar.trailingAnchor, constant: -8),

      disclosureLabel.topAnchor.constraint(equalTo: statusBar.bottomAnchor, constant: 6),
      disclosureLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
      disclosureLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

      // Progress row
      progressRow.topAnchor.constraint(equalTo: disclosureLabel.bottomAnchor, constant: 6),
      progressRow.leadingAnchor.constraint(equalTo: leadingAnchor),
      progressRow.trailingAnchor.constraint(equalTo: trailingAnchor),
      progressRow.heightAnchor.constraint(equalToConstant: 20),

      progressLabel.leadingAnchor.constraint(equalTo: progressRow.leadingAnchor, constant: 12),
      progressLabel.centerYAnchor.constraint(equalTo: progressRow.centerYAnchor),

      scoreLabel.trailingAnchor.constraint(equalTo: progressRow.trailingAnchor, constant: -12),
      scoreLabel.centerYAnchor.constraint(equalTo: progressRow.centerYAnchor),

      // Token footer
      tokenFooter.leadingAnchor.constraint(equalTo: leadingAnchor),
      tokenFooter.trailingAnchor.constraint(equalTo: trailingAnchor),
      tokenFooter.bottomAnchor.constraint(equalTo: bottomAnchor),
      tokenFooter.heightAnchor.constraint(equalToConstant: 28),

      tokenFooterDivider.topAnchor.constraint(equalTo: tokenFooter.topAnchor),
      tokenFooterDivider.leadingAnchor.constraint(equalTo: tokenFooter.leadingAnchor),
      tokenFooterDivider.trailingAnchor.constraint(equalTo: tokenFooter.trailingAnchor),
      tokenFooterDivider.heightAnchor.constraint(equalToConstant: 1),

      tokenFooterLabel.leadingAnchor.constraint(equalTo: tokenFooter.leadingAnchor, constant: 12),
      tokenFooterLabel.trailingAnchor.constraint(lessThanOrEqualTo: tokenFooter.trailingAnchor, constant: -8),
      tokenFooterLabel.centerYAnchor.constraint(equalTo: tokenFooter.centerYAnchor),

      // Scroll view — inset from panel edges
      contentScrollView.topAnchor.constraint(equalTo: progressRow.bottomAnchor, constant: 8),
      contentScrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
      contentScrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
      contentScrollView.bottomAnchor.constraint(equalTo: tokenFooter.topAnchor, constant: -10),

      // Document view inside scroll — width pinned to clip view for vertical-only scrolling
      scrollDocumentView.topAnchor.constraint(equalTo: contentScrollView.contentView.topAnchor),
      scrollDocumentView.leadingAnchor.constraint(equalTo: contentScrollView.contentView.leadingAnchor),
      scrollDocumentView.widthAnchor.constraint(equalTo: contentScrollView.contentView.widthAnchor),

      // Completion label
      completionLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
      completionLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
      completionLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -24),

      // Empty state
      emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
      emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
      emptyLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -24),
    ])
  }

  // MARK: - Actions

  @objc private func toggleLearning(_ sender: NSSwitch) {
    let requestedState = sender.state == .on
    if let shouldToggleLearning, !shouldToggleLearning(requestedState) {
      sender.state = isLearningEnabled ? .on : .off
      return
    }
    applyLearningEnabled(requestedState, animated: true, updateSwitch: false)
    onToggleLearning?(requestedState)
  }

  @objc private func closePanel() {
    onClose?()
  }

  func refreshColors() {
    layer?.backgroundColor = IdleTheme.bgColor.cgColor
    headerView.layer?.backgroundColor = IdleTheme.bgColor.cgColor
    headerLabel.textColor = IdleTheme.headerText
    statusLabel.textColor = IdleTheme.secondaryText
    disclosureLabel.textColor = IdleTheme.secondaryText
    progressLabel.textColor = IdleTheme.accentColor
    scoreLabel.textColor = IdleTheme.accentColor
    completionLabel.textColor = IdleTheme.accentColor
    emptyLabel.textColor = IdleTheme.secondaryText
    tokenFooter.layer?.backgroundColor = IdleTheme.bgColor.cgColor
    tokenFooterDivider.layer?.backgroundColor = IdleTheme.dividerColor.cgColor
    tokenFooterLabel.textColor = IdleTheme.secondaryText
  }

  private func applyLearningEnabled(_ enabled: Bool, animated: Bool, updateSwitch: Bool) {
    isLearningEnabled = enabled
    if updateSwitch {
      toggleSwitch.state = enabled ? .on : .off
    }

    quizCard.isInteractionEnabled = enabled

    let updates = {
      let alpha: CGFloat = enabled ? 1.0 : 0.35
      self.statusBar.alphaValue = alpha
      self.contentScrollView.alphaValue = alpha
      self.progressRow.alphaValue = alpha
      self.emptyLabel.alphaValue = alpha
    }

    if animated {
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.2
        self.statusBar.animator().alphaValue = enabled ? 1.0 : 0.35
        self.contentScrollView.animator().alphaValue = enabled ? 1.0 : 0.35
        self.progressRow.animator().alphaValue = enabled ? 1.0 : 0.35
        self.emptyLabel.animator().alphaValue = enabled ? 1.0 : 0.35
      }
    } else {
      updates()
    }

    if !enabled {
      statusDot.stopPulsing()
    }
  }
}
