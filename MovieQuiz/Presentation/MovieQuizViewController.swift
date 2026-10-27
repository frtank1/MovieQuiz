import UIKit

final class MovieQuizViewController: UIViewController, MovieQuizViewControllerProtocol {
    @IBOutlet private weak var imageView: UIImageView!
    @IBOutlet private weak var textLabel: UILabel!
    @IBOutlet private weak var questionNumberLabel: UILabel!
    @IBOutlet private weak var yesButton: UIButton!
    @IBOutlet private weak var noButton: UIButton!
    @IBOutlet private weak var activityIndicator: UIActivityIndicatorView!

    private var presenter: MovieQuizPresenter?
    private var presenterBuilder: ((MovieQuizViewControllerProtocol) -> MovieQuizPresenter)?
    private var alertPresenter: AlertPresenting?

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

    func setup(presenterBuilder: @escaping (MovieQuizViewControllerProtocol) -> MovieQuizPresenter) {
        self.presenterBuilder = presenterBuilder
    }

    func setup(alertPresenter: AlertPresenting) {
        self.alertPresenter = alertPresenter
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        imageView.layer.cornerRadius = 20
        imageView.clipsToBounds = true
        imageView.isAccessibilityElement = true
        if alertPresenter == nil {
            alertPresenter = AlertPresenter(viewController: self)
        }
        presenter = presenterBuilder?(self) ?? MovieQuizPresenter(viewController: self)
        presenterBuilder = nil
    }

    @IBAction private func yesButtonClicked(_ sender: UIButton) {
        presenter?.yesButtonClicked()
    }

    @IBAction private func noButtonClicked(_ sender: UIButton) {
        presenter?.noButtonClicked()
    }

    func show(quiz step: QuizStepViewModel) {
        imageView.image = UIImage(data: step.image)
        clearAnswerFeedback()
        textLabel.text = step.question
        questionNumberLabel.text = step.questionNumber
    }

    func show(quiz result: QuizResultsViewModel) {
        clearAnswerFeedback()
        let model = AlertModel(
            title: result.title,
            message: result.text,
            buttonText: result.buttonText
        ) { [weak self] in
            self?.presenter?.restartGame()
        }
        alertPresenter?.show(model: model)
    }

    func highlightImageBorder(isCorrectAnswer: Bool) {
        imageView.layer.borderWidth = 8
        imageView.layer.borderColor = (
            isCorrectAnswer ? correctAnswerColor : incorrectAnswerColor
        ).cgColor
    }

    func showLoadingIndicator() {
        clearAnswerFeedback()
        setAnswerButtonsEnabled(false)
        activityIndicator.startAnimating()
    }

    func hideLoadingIndicator() {
        activityIndicator.stopAnimating()
    }

    func showNetworkError(message: String) {
        clearAnswerFeedback()
        hideLoadingIndicator()
        setAnswerButtonsEnabled(false)
        let model = AlertModel(
            title: "Ошибка",
            message: message,
            buttonText: "Попробовать ещё раз"
        ) { [weak self] in
            self?.presenter?.retryLoading()
        }
        alertPresenter?.show(model: model)
    }

    func setAnswerButtonsEnabled(_ isEnabled: Bool) {
        yesButton.isEnabled = isEnabled
        noButton.isEnabled = isEnabled
    }

    private func clearAnswerFeedback() {
        imageView.layer.borderWidth = 0
        imageView.layer.borderColor = nil
    }
}
