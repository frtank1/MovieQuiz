import Foundation

@MainActor
final class MovieQuizPresenter: QuestionFactoryDelegate {
    let questionsAmount = 10

    private weak var viewController: MovieQuizViewControllerProtocol?
    private let statisticService: StatisticServiceProtocol
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void
    private var questionFactory: QuestionFactoryProtocol?
    private var currentQuestion: QuizQuestion?
    private var currentQuestionIndex = 0
    private var correctAnswers = 0
    private var isAnswerProcessing = false
    private var isRoundFinished = false
    private var isAwaitingQuestion = false
    private var quizGeneration = UUID()
    private var answerID: UUID?

    init(
        viewController: MovieQuizViewControllerProtocol,
        statisticService: StatisticServiceProtocol = StatisticService(),
        questionFactoryBuilder: (QuestionFactoryDelegate) -> QuestionFactoryProtocol = {
            QuestionFactory(moviesLoader: MoviesLoader(), delegate: $0)
        },
        schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, action in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
        }
    ) {
        self.viewController = viewController
        self.statisticService = statisticService
        self.schedule = schedule
        questionFactory = questionFactoryBuilder(self)
        retryLoading()
    }

    func convert(model: QuizQuestion) -> QuizStepViewModel {
        QuizStepViewModel(
            image: model.image,
            question: model.text,
            questionNumber: "\(currentQuestionIndex + 1)/\(questionsAmount)"
        )
    }

    func isLastQuestion() -> Bool {
        currentQuestionIndex == questionsAmount - 1
    }

    func resetQuestionIndex() {
        currentQuestionIndex = 0
    }

    func switchToNextQuestion() {
        guard !isLastQuestion() else { return }
        currentQuestionIndex += 1
    }

    func yesButtonClicked() {
        didAnswer(isYes: true)
    }

    func noButtonClicked() {
        didAnswer(isYes: false)
    }

    private func didAnswer(isYes: Bool) {
        guard let currentQuestion = currentQuestion else { return }
        proceedWithAnswer(isCorrect: isYes == currentQuestion.correctAnswer)
    }

    func proceedWithAnswer(isCorrect: Bool) {
        guard currentQuestion != nil, !isAnswerProcessing, !isRoundFinished else { return }
        isAnswerProcessing = true
        let id = UUID()
        answerID = id
        viewController?.setAnswerButtonsEnabled(false)
        if isCorrect {
            correctAnswers += 1
        }
        viewController?.highlightImageBorder(isCorrectAnswer: isCorrect)
        let generation = quizGeneration
        schedule(1) { [weak self] in
            guard let self = self, self.quizGeneration == generation, self.answerID == id else { return }
            self.proceedToNextQuestionOrResults()
        }
    }

    func proceedToNextQuestionOrResults() {
        guard isAnswerProcessing, answerID != nil, !isRoundFinished else { return }
        answerID = nil
        isAnswerProcessing = false
        currentQuestion = nil
        if isLastQuestion() {
            isRoundFinished = true
            statisticService.store(correct: correctAnswers, total: questionsAmount)
            let result = QuizResultsViewModel(
                title: "Этот раунд окончен!",
                text: makeResultsMessage(),
                buttonText: "Сыграть еще раз"
            )
            viewController?.show(quiz: result)
        } else {
            switchToNextQuestion()
            requestNextQuestion()
        }
    }

    func makeResultsMessage() -> String {
        let bestGame = statisticService.bestGame
        let accuracy = String(
            format: "%.2f",
            locale: Locale(identifier: "en_US_POSIX"),
            statisticService.totalAccuracy
        )
        return """
        Ваш результат: \(correctAnswers)/\(questionsAmount)
        Количество сыгранных квизов: \(statisticService.gamesCount)
        Рекорд: \(bestGame.correct)/\(bestGame.total) (\(bestGame.date.dateTimeString))
        Средняя точность: \(accuracy)%
        """
    }

    func restartGame() {
        resetRound()
        requestNextQuestion()
    }

    func retryLoading() {
        resetRound()
        viewController?.show(quiz: QuizStepViewModel(
            image: Data(),
            question: "Загрузка фильмов…",
            questionNumber: "1/\(questionsAmount)"
        ))
        viewController?.showLoadingIndicator()
        questionFactory?.loadData()
    }

    private func resetRound() {
        quizGeneration = UUID()
        answerID = nil
        resetQuestionIndex()
        correctAnswers = 0
        currentQuestion = nil
        isAnswerProcessing = false
        isRoundFinished = false
        isAwaitingQuestion = false
        viewController?.setAnswerButtonsEnabled(false)
    }

    private func requestNextQuestion() {
        currentQuestion = nil
        isAwaitingQuestion = true
        viewController?.setAnswerButtonsEnabled(false)
        viewController?.showLoadingIndicator()
        questionFactory?.requestNextQuestion()
    }

    nonisolated func didReceiveNextQuestion(question: QuizQuestion?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isAwaitingQuestion, !self.isRoundFinished else { return }
            self.isAwaitingQuestion = false
            self.viewController?.hideLoadingIndicator()
            guard let question = question else {
                self.showNetworkError(message: "Не удалось получить следующий вопрос.")
                return
            }
            self.currentQuestion = question
            self.isAnswerProcessing = false
            self.viewController?.show(quiz: self.convert(model: question))
            self.viewController?.setAnswerButtonsEnabled(true)
        }
    }

    nonisolated func didLoadDataFromServer() {
        DispatchQueue.main.async { [weak self] in
            self?.requestNextQuestion()
        }
    }

    nonisolated func didFailToLoadData(with error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.showNetworkError(message: error.localizedDescription)
        }
    }

    private func showNetworkError(message: String) {
        quizGeneration = UUID()
        answerID = nil
        currentQuestion = nil
        isAwaitingQuestion = false
        isAnswerProcessing = false
        viewController?.setAnswerButtonsEnabled(false)
        viewController?.hideLoadingIndicator()
        viewController?.showNetworkError(message: message)
    }
}
