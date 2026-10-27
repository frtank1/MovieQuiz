import UIKit

final class MovieQuizViewController: UIViewController, QuestionFactoryDelegate {
    @IBOutlet private weak var imageView: UIImageView!
    @IBOutlet private weak var textLabel: UILabel!
    @IBOutlet private weak var questionNumberLabel: UILabel!
    @IBOutlet private weak var yesButton: UIButton!
    @IBOutlet private weak var noButton: UIButton!
    @IBOutlet private weak var activityIndicator: UIActivityIndicatorView!

    private var questionFactory: QuestionFactoryProtocol?
    private var alertPresenter: AlertPresenting?
    private var statisticService: StatisticServiceProtocol = StatisticService()
    private var currentQuestion: QuizQuestion?
    private let questionsAmount = 10
    private var currentQuestionIndex = 0
    private var correctAnswers = 0
    private var isAnswerProcessing = false
    private var quizGeneration = UUID()

    private let correctAnswerColor = UIColor(
        red: 96.0 / 255.0,
        green: 194.0 / 255.0,
        blue: 142.0 / 255.0,
        alpha: 1
    )
    private let incorrectAnswerColor = UIColor(
        red: 245.0 / 255.0,
        green: 107.0 / 255.0,
        blue: 108.0 / 255.0,
        alpha: 1
    )

    func setup(statisticService: StatisticServiceProtocol) {
        self.statisticService = statisticService
    }

    func setup(questionFactory: QuestionFactoryProtocol) {
        self.questionFactory = questionFactory
    }

    func setup(alertPresenter: AlertPresenting) {
        self.alertPresenter = alertPresenter
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        imageView.layer.cornerRadius = 20
        imageView.clipsToBounds = true
        if alertPresenter == nil {
            alertPresenter = AlertPresenter(viewController: self)
        }
        if questionFactory == nil {
            questionFactory = QuestionFactory(moviesLoader: MoviesLoader(), delegate: self)
        }
        loadQuestions()
    }

    nonisolated func didReceiveNextQuestion(question: QuizQuestion?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.hideLoadingIndicator()
            guard let question = question else {
                self.showNetworkError(message: "Не удалось получить следующий вопрос.")
                return
            }
            self.currentQuestion = question
            self.show(quiz: self.convert(model: question))
            self.isAnswerProcessing = false
            self.setAnswerButtonsEnabled(true)
        }
    }

    @IBAction private func yesButtonClicked(_ sender: UIButton) {
        answerCurrentQuestion(true)
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

    @IBAction private func noButtonClicked(_ sender: UIButton) {
        answerCurrentQuestion(false)
    }

    private func requestNextQuestion() {
        currentQuestion = nil
        showLoadingIndicator()
        setAnswerButtonsEnabled(false)
        questionFactory?.requestNextQuestion()
    }

    func showLoadingIndicator() {
        setAnswerButtonsEnabled(false)
        activityIndicator.startAnimating()
    }

    private func loadQuestions() {
        quizGeneration = UUID()
        currentQuestion = nil
        currentQuestionIndex = 0
        correctAnswers = 0
        isAnswerProcessing = false
        clearAnswerFeedback()
        imageView.image = nil
        textLabel.text = "Загрузка фильмов…"
        questionNumberLabel.text = "1/\(questionsAmount)"
        showLoadingIndicator()
        questionFactory?.loadData()
    }

    func hideLoadingIndicator() {
        activityIndicator.stopAnimating()
    }

    func showNetworkError(message: String) {
        quizGeneration = UUID()
        currentQuestion = nil
        isAnswerProcessing = false
        clearAnswerFeedback()
        setAnswerButtonsEnabled(false)
        hideLoadingIndicator()
        let model = AlertModel(
            title: "Ошибка",
            message: message,
            buttonText: "Попробовать ещё раз"
        ) { [weak self] in
            self?.loadQuestions()
        }
        alertPresenter?.show(model: model)
    }

    private func convert(model: QuizQuestion) -> QuizStepViewModel {
        QuizStepViewModel(
            image: UIImage(data: model.image) ?? UIImage(),
            text: model.text,
            questionNumber: "\(currentQuestionIndex + 1)/\(questionsAmount)"
        )
    }

    private func show(quiz step: QuizStepViewModel) {
        imageView.image = step.image
        clearAnswerFeedback()
        textLabel.text = step.text
        questionNumberLabel.text = step.questionNumber
    }

    private func answerCurrentQuestion(_ answer: Bool) {
        guard !isAnswerProcessing, let currentQuestion = currentQuestion else { return }
        isAnswerProcessing = true
        setAnswerButtonsEnabled(false)

        let isCorrect = answer == currentQuestion.correctAnswer
        if isCorrect {
            correctAnswers += 1
        }

        imageView.layer.borderWidth = 8
        imageView.layer.borderColor = (
            isCorrect ? correctAnswerColor : incorrectAnswerColor
        ).cgColor

        let generation = quizGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self = self, self.quizGeneration == generation else { return }
            self.clearAnswerFeedback()
            self.showNextQuestionOrResults()
        }
    }

    private func showNextQuestionOrResults() {
        if currentQuestionIndex == questionsAmount - 1 {
            showResults()
        } else {
            currentQuestionIndex += 1
            requestNextQuestion()
        }
    }

    private func showResults() {
        statisticService.store(correct: correctAnswers, total: questionsAmount)
        let bestGame = statisticService.bestGame
        let accuracy = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), statisticService.totalAccuracy)
        let result = QuizResultsViewModel(
            title: "Этот раунд окончен!",
            text: """
            Ваш результат: \(correctAnswers)/\(questionsAmount)
            Количество сыгранных квизов: \(statisticService.gamesCount)
            Рекорд: \(bestGame.correct)/\(bestGame.total) (\(bestGame.date.dateTimeString))
            Средняя точность: \(accuracy)%
            """,
            buttonText: "Сыграть еще раз"
        )
        show(quiz: result)
    }

    private func show(quiz result: QuizResultsViewModel) {
        let model = AlertModel(
            title: result.title,
            message: result.text,
            buttonText: result.buttonText
        ) { [weak self] in
            guard let self = self else { return }
            self.restartQuiz()
        }
        alertPresenter?.show(model: model)
    }

    private func restartQuiz() {
        currentQuestionIndex = 0
        correctAnswers = 0
        isAnswerProcessing = false
        clearAnswerFeedback()
        requestNextQuestion()
    }

    private func clearAnswerFeedback() {
        imageView.layer.borderWidth = 0
        imageView.layer.borderColor = nil
    }

    private func setAnswerButtonsEnabled(_ isEnabled: Bool) {
        yesButton.isEnabled = isEnabled
        noButton.isEnabled = isEnabled
    }
}
