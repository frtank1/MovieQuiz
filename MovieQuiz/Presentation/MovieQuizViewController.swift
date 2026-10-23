import UIKit

final class MovieQuizViewController: UIViewController {
    private struct QuizQuestion {
        let imageName: String
        let text: String
        let correctAnswer: Bool
    }

    private struct QuizStepViewModel {
        let image: UIImage
        let text: String
        let questionNumber: String
    }

    private struct QuizResultsViewModel {
        let title: String
        let text: String
        let buttonText: String
    }

    @IBOutlet private weak var imageView: UIImageView!
    @IBOutlet private weak var textLabel: UILabel!
    @IBOutlet private weak var questionNumberLabel: UILabel!
    @IBOutlet private weak var yesButton: UIButton!
    @IBOutlet private weak var noButton: UIButton!

    private let questions: [QuizQuestion] = [
        QuizQuestion(
            imageName: "The Godfather",
            text: "Рейтинг этого фильма больше чем 6?",
            correctAnswer: true
        ),
        QuizQuestion(
            imageName: "The Dark Knight",
            text: "Рейтинг этого фильма больше чем 6?",
            correctAnswer: true
        ),
        QuizQuestion(
            imageName: "Kill Bill",
            text: "Рейтинг этого фильма больше чем 6?",
            correctAnswer: true
        ),
        QuizQuestion(
            imageName: "The Avengers",
            text: "Рейтинг этого фильма больше чем 6?",
            correctAnswer: true
        ),
        QuizQuestion(
            imageName: "Deadpool",
            text: "Рейтинг этого фильма больше чем 6?",
            correctAnswer: true
        ),
        QuizQuestion(
            imageName: "The Green Knight",
            text: "Рейтинг этого фильма больше чем 6?",
            correctAnswer: true
        ),
        QuizQuestion(
            imageName: "Old",
            text: "Рейтинг этого фильма больше чем 6?",
            correctAnswer: false
        ),
        QuizQuestion(
            imageName: "The Ice Age Adventures of Buck Wild",
            text: "Рейтинг этого фильма больше чем 6?",
            correctAnswer: false
        ),
        QuizQuestion(
            imageName: "Tesla",
            text: "Рейтинг этого фильма больше чем 6?",
            correctAnswer: false
        ),
        QuizQuestion(
            imageName: "Vivarium",
            text: "Рейтинг этого фильма больше чем 6?",
            correctAnswer: false
        )
    ]

    private var currentQuestionIndex = 0
    private var correctAnswers = 0
    private var isAnswerProcessing = false

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

    override func viewDidLoad() {
        super.viewDidLoad()
        imageView.layer.cornerRadius = 20
        imageView.clipsToBounds = true
        showCurrentQuestion()
    }

    @IBAction private func yesButtonClicked(_ sender: UIButton) {
        answerCurrentQuestion(true)
    }

    @IBAction private func noButtonClicked(_ sender: UIButton) {
        answerCurrentQuestion(false)
    }

    private func showCurrentQuestion() {
        let question = questions[currentQuestionIndex]
        show(quiz: convert(model: question))
        isAnswerProcessing = false
        setAnswerButtonsEnabled(true)
    }

    private func convert(model: QuizQuestion) -> QuizStepViewModel {
        QuizStepViewModel(
            image: UIImage(named: model.imageName) ?? UIImage(),
            text: model.text,
            questionNumber: "\(currentQuestionIndex + 1)/\(questions.count)"
        )
    }

    private func show(quiz step: QuizStepViewModel) {
        imageView.image = step.image
        imageView.layer.borderWidth = 0
        imageView.layer.borderColor = nil
        textLabel.text = step.text
        questionNumberLabel.text = step.questionNumber
    }

    private func answerCurrentQuestion(_ answer: Bool) {
        guard !isAnswerProcessing else { return }
        isAnswerProcessing = true
        setAnswerButtonsEnabled(false)

        let isCorrect = answer == questions[currentQuestionIndex].correctAnswer
        if isCorrect {
            correctAnswers += 1
        }

        imageView.layer.borderWidth = 8
        imageView.layer.borderColor = (
            isCorrect ? correctAnswerColor : incorrectAnswerColor
        ).cgColor

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self = self else { return }
            self.imageView.layer.borderWidth = 0
            self.imageView.layer.borderColor = nil
            self.showNextQuestionOrResults()
        }
    }

    private func showNextQuestionOrResults() {
        if currentQuestionIndex == questions.count - 1 {
            showResults()
        } else {
            currentQuestionIndex += 1
            showCurrentQuestion()
        }
    }

    private func showResults() {
        let result = QuizResultsViewModel(
            title: "Этот раунд окончен!",
            text: "Ваш результат: \(correctAnswers)/\(questions.count)",
            buttonText: "Сыграть ещё раз"
        )
        show(quiz: result)
    }

    private func show(quiz result: QuizResultsViewModel) {
        let alert = UIAlertController(
            title: result.title,
            message: result.text,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: result.buttonText, style: .default) { [weak self] _ in
            self?.restartQuiz()
        })
        present(alert, animated: true)
    }

    private func restartQuiz() {
        currentQuestionIndex = 0
        correctAnswers = 0
        showCurrentQuestion()
    }

    private func setAnswerButtonsEnabled(_ isEnabled: Bool) {
        yesButton.isEnabled = isEnabled
        noButton.isEnabled = isEnabled
    }
}
