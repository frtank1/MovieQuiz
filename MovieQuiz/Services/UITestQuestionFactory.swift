#if DEBUG
import UIKit

final class UITestQuestionFactory: QuestionFactoryProtocol {
    private weak var delegate: QuestionFactoryDelegate?
    private let posters = ["The Godfather", "The Avengers"]
    private var nextIndex = 0

    init(delegate: QuestionFactoryDelegate) {
        self.delegate = delegate
    }

    func loadData() {
        nextIndex = 0
        delegate?.didLoadDataFromServer()
    }

    func requestNextQuestion() {
        let poster = posters[nextIndex % posters.count]
        nextIndex += 1
        guard let image = UIImage(named: poster)?.pngData() else {
            delegate?.didFailToLoadData(with: QuestionFactoryError.invalidImage)
            return
        }
        delegate?.didReceiveNextQuestion(question: QuizQuestion(
            image: image,
            text: "Рейтинг этого фильма больше, чем 7?",
            correctAnswer: true
        ))
    }
}
#endif
