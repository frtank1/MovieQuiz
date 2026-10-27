import XCTest
import UIKit
@testable import MovieQuiz

@MainActor
final class MovieQuizViewControllerTests: XCTestCase {
    private final class QuestionFactoryStub: QuestionFactoryProtocol {
        weak var delegate: QuestionFactoryDelegate?
        var automaticallyResponds = true
        var loadCount = 0
        var requestCount = 0
        private(set) var currentQuestion: QuizQuestion?

        func loadData() {
            loadCount += 1
            if automaticallyResponds {
                delegate?.didLoadDataFromServer()
            }
        }

        func requestNextQuestion() {
            requestCount += 1
            if automaticallyResponds {
                let data = UIImage(named: "The Godfather")?.pngData() ?? Data()
                let question = QuizQuestion(
                    image: data,
                    text: "Рейтинг этого фильма больше, чем 7?",
                    correctAnswer: true
                )
                currentQuestion = question
                delegate?.didReceiveNextQuestion(question: question)
            }
        }
    }

    private final class AlertSpy: AlertPresenting {
        var models: [AlertModel] = []

        func show(model: AlertModel) {
            models.append(model)
        }
    }

    @MainActor
    private struct QuizScreen {
        let controller: MovieQuizViewController
        let window: UIWindow
        let poster: UIImageView
        let question: UILabel
        let number: UILabel
        let yes: UIButton
        let no: UIButton
        let statistics: StatisticService
        let storage: UserDefaults
        let suiteName: String
        let factory: QuestionFactoryStub

        func close() {
            controller.dismiss(animated: false)
            window.isHidden = true
            window.rootViewController = nil
            storage.removePersistentDomain(forName: suiteName)
        }
    }

    func testStoryboardStartsAtFirstQuestionWithLoadedPoster() async throws {
        let screen = try await makeScreen()
        defer { screen.close() }

        XCTAssertEqual(screen.number.text, "1/10")
        XCTAssertEqual(screen.question.text, "Рейтинг этого фильма больше, чем 7?")
        XCTAssertEqual(screen.yes.title(for: .normal), "Да")
        XCTAssertEqual(screen.no.title(for: .normal), "Нет")
        XCTAssertTrue(screen.yes.isEnabled)
        XCTAssertTrue(screen.no.isEnabled)
        let question = try currentQuestion(on: screen)
        XCTAssertEqual(screen.poster.image?.pngData(), UIImage(data: question.image)?.pngData())
        XCTAssertGreaterThan(screen.poster.image?.size.width ?? 0, 0)
        XCTAssertEqual(screen.poster.layer.cornerRadius, 20)
        XCTAssertTrue(screen.poster.clipsToBounds)
        XCTAssertEqual(screen.poster.layer.borderWidth, 0)
    }

    func testPerfectRoundIgnoresRepeatedAnswersAndClearsFeedbackAfterOneSecond() async throws {
        let screen = try await makeScreen()
        defer { screen.close() }

        let answeredAt = Date()
        let firstAnswer = try currentQuestion(on: screen).correctAnswer
        (firstAnswer ? screen.yes : screen.no).sendActions(for: .touchUpInside)
        XCTAssertFalse(screen.yes.isEnabled)
        XCTAssertFalse(screen.no.isEnabled)
        XCTAssertEqual(screen.poster.layer.borderWidth, 8)
        assertBorderColor(screen.poster, red: 96, green: 194, blue: 142)

        for _ in 0..<5 {
            screen.yes.sendActions(for: .touchUpInside)
            screen.no.sendActions(for: .touchUpInside)
        }
        try await Task.sleep(nanoseconds: 750_000_000)
        XCTAssertEqual(screen.number.text, "1/10")
        XCTAssertFalse(screen.yes.isEnabled)
        try await waitUntil { screen.number.text == "2/10" }
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(answeredAt), 0.95)
        XCTAssertEqual(screen.poster.layer.borderWidth, 0)
        XCTAssertNil(screen.poster.layer.borderColor)
        XCTAssertTrue(screen.yes.isEnabled)
        XCTAssertTrue(screen.no.isEnabled)
        let nextQuestion = try currentQuestion(on: screen)
        XCTAssertEqual(screen.poster.image?.pngData(), UIImage(data: nextQuestion.image)?.pngData())

        for question in 2...10 {
            try await answer(try currentQuestion(on: screen).correctAnswer, question: question, on: screen)
        }
        let alert = try XCTUnwrap(screen.controller.presentedViewController as? UIAlertController)
        XCTAssertEqual(alert.title, "Этот раунд окончен!")
        assertResult(alert, correct: 10, on: screen)
        XCTAssertEqual(alert.actions.map(\.title), ["Сыграть еще раз"])
        XCTAssertEqual(screen.poster.layer.borderWidth, 0)
        XCTAssertFalse(screen.yes.isEnabled)
        XCTAssertFalse(screen.no.isEnabled)
    }

    func testWrongAnswerShowsRedFeedbackAndIsExcludedFromScore() async throws {
        let screen = try await makeScreen()
        defer { screen.close() }

        let wrongAnswer = try !currentQuestion(on: screen).correctAnswer
        (wrongAnswer ? screen.yes : screen.no).sendActions(for: .touchUpInside)
        XCTAssertEqual(screen.poster.layer.borderWidth, 8)
        assertBorderColor(screen.poster, red: 245, green: 107, blue: 108)
        try await waitUntil { screen.number.text == "2/10" }
        for question in 2...10 {
            try await answer(try currentQuestion(on: screen).correctAnswer, question: question, on: screen)
        }
        let alert = try XCTUnwrap(screen.controller.presentedViewController as? UIAlertController)
        assertResult(alert, correct: 9, on: screen)
        XCTAssertEqual(alert.actions.first?.title, "Сыграть еще раз")
        XCTAssertEqual(screen.poster.layer.borderWidth, 0)
    }

    func testLayoutIsUnambiguousAtCommonPortraitSizes() async throws {
        let sizes = [
            CGSize(width: 375, height: 812),
            CGSize(width: 390, height: 844),
            CGSize(width: 440, height: 956)
        ]
        for size in sizes {
            let controller = try instantiateController()
            controller.loadViewIfNeeded()
            controller.view.frame = CGRect(origin: .zero, size: size)
            controller.additionalSafeAreaInsets = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()

            let poster: UIImageView = try find("Poster", in: controller.view)
            let question: UILabel = try find("questionText", in: controller.view)
            let yes: UIButton = try find("Yes", in: controller.view)
            let no: UIButton = try find("No", in: controller.view)
            try await waitUntil { yes.isEnabled && no.isEnabled }
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            for view in descendants(of: controller.view) {
                XCTAssertFalse(view.hasAmbiguousLayout, "Ambiguous layout at \(size): \(view.accessibilityIdentifier ?? String(describing: type(of: view)))")
            }
            for view in [poster, question, yes, no] {
                let frame = view.convert(view.bounds, to: controller.view)
                XCTAssertTrue(controller.view.bounds.contains(frame), "Content outside \(size): \(frame)")
                XCTAssertGreaterThan(frame.width, 0)
                XCTAssertGreaterThan(frame.height, 0)
            }
            XCTAssertGreaterThanOrEqual(yes.bounds.height, 44)
            XCTAssertGreaterThanOrEqual(no.bounds.height, 44)
            let questionHeight = question.sizeThatFits(CGSize(width: question.bounds.width, height: .greatestFiniteMagnitude)).height
            XCTAssertGreaterThanOrEqual(question.bounds.height + 1, questionHeight, "Question text must fit at \(size).")
        }
    }

    func testLoadingStartsWithSpinnerAndBlocksAnswersUntilPosterArrives() async throws {
        let factory = QuestionFactoryStub()
        factory.automaticallyResponds = false
        let screen = try await makeScreen(factory: factory, waitsForQuestion: false)
        defer { screen.close() }
        let indicator: UIActivityIndicatorView = try find("loadingIndicator", in: screen.controller.view)

        XCTAssertEqual(factory.loadCount, 1)
        XCTAssertEqual(factory.requestCount, 0)
        XCTAssertTrue(indicator.isAnimating)
        XCTAssertNil(screen.poster.image)
        XCTAssertFalse(screen.yes.isEnabled)
        XCTAssertFalse(screen.no.isEnabled)
        screen.yes.sendActions(for: .touchUpInside)
        XCTAssertEqual(screen.poster.layer.borderWidth, 0)

        factory.delegate?.didLoadDataFromServer()
        try await waitUntil { factory.requestCount == 1 }
        XCTAssertTrue(indicator.isAnimating)
        XCTAssertFalse(screen.yes.isEnabled)
        factory.delegate?.didReceiveNextQuestion(question: QuizQuestion(
            image: try XCTUnwrap(UIImage(named: "The Godfather")?.pngData()),
            text: "Рейтинг этого фильма больше, чем 7?",
            correctAnswer: true
        ))
        try await waitUntil { screen.yes.isEnabled }
        XCTAssertFalse(indicator.isAnimating)
        XCTAssertTrue(indicator.isHidden)
        XCTAssertNotNil(screen.poster.image)
    }

    func testNetworkErrorStopsSpinnerAndRetryLoadsAgainWithoutRecordingGame() async throws {
        let factory = QuestionFactoryStub()
        factory.automaticallyResponds = false
        let presenter = AlertSpy()
        let screen = try await makeScreen(factory: factory, alertPresenter: presenter, waitsForQuestion: false)
        defer { screen.close() }
        let indicator: UIActivityIndicatorView = try find("loadingIndicator", in: screen.controller.view)

        screen.factory.delegate?.didFailToLoadData(with: URLError(.notConnectedToInternet))
        try await waitUntil { presenter.models.count == 1 }
        XCTAssertFalse(indicator.isAnimating)
        XCTAssertFalse(screen.yes.isEnabled)
        XCTAssertFalse(screen.no.isEnabled)
        XCTAssertEqual(screen.statistics.gamesCount, 0)
        let model = try XCTUnwrap(presenter.models.first)
        XCTAssertEqual(model.title, "Ошибка")
        XCTAssertFalse(model.message.isEmpty)
        XCTAssertEqual(model.buttonText, "Попробовать ещё раз")

        model.completion()
        XCTAssertEqual(factory.loadCount, 2)
        XCTAssertTrue(indicator.isAnimating)
        XCTAssertEqual(screen.number.text, "1/10")
        XCTAssertFalse(screen.yes.isEnabled)
        XCTAssertEqual(screen.statistics.gamesCount, 0)
    }

    func testNilQuestionShowsErrorInsteadOfEnablingBlankQuestion() async throws {
        let factory = QuestionFactoryStub()
        factory.automaticallyResponds = false
        let presenter = AlertSpy()
        let screen = try await makeScreen(factory: factory, alertPresenter: presenter, waitsForQuestion: false)
        defer { screen.close() }

        screen.factory.delegate?.didLoadDataFromServer()
        try await waitUntil { screen.factory.requestCount == 1 }
        screen.factory.delegate?.didReceiveNextQuestion(question: nil)
        try await waitUntil { presenter.models.count == 1 }
        XCTAssertEqual(presenter.models.first?.title, "Ошибка")
        XCTAssertFalse(screen.yes.isEnabled)
        XCTAssertFalse(screen.no.isEnabled)
    }

    func testErrorInvalidatesDelayedAnswerTransition() async throws {
        let presenter = AlertSpy()
        let screen = try await makeScreen(alertPresenter: presenter)
        defer { screen.close() }
        screen.yes.sendActions(for: .touchUpInside)
        screen.factory.delegate?.didFailToLoadData(with: QuestionFactoryError.invalidImage)
        try await waitUntil { presenter.models.count == 1 }
        try await Task.sleep(nanoseconds: 1_200_000_000)

        XCTAssertEqual(screen.factory.requestCount, 1)
        XCTAssertEqual(screen.number.text, "1/10")
        XCTAssertFalse(screen.yes.isEnabled)
        XCTAssertEqual(screen.statistics.gamesCount, 0)
    }

    private func instantiateController(
        statisticService: StatisticServiceProtocol? = nil,
        factory: QuestionFactoryStub = QuestionFactoryStub(),
        alertPresenter: AlertPresenting? = nil
    ) throws -> MovieQuizViewController {
        let storyboard = UIStoryboard(name: "Main", bundle: Bundle(for: MovieQuizViewController.self))
        let controller = try XCTUnwrap(storyboard.instantiateInitialViewController() as? MovieQuizViewController)
        controller.setup { view in
            MovieQuizPresenter(
                viewController: view,
                statisticService: statisticService ?? StatisticService(),
                questionFactoryBuilder: { delegate in
                    factory.delegate = delegate
                    return factory
                }
            )
        }
        if let alertPresenter {
            controller.setup(alertPresenter: alertPresenter)
        }
        return controller
    }

    private func makeScreen(
        factory: QuestionFactoryStub = QuestionFactoryStub(),
        alertPresenter: AlertPresenting? = nil,
        waitsForQuestion: Bool = true
    ) async throws -> QuizScreen {
        let suiteName = "MovieQuiz.UIHostTests.\(UUID().uuidString)"
        let storage = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        storage.removePersistentDomain(forName: suiteName)
        let statistics = StatisticService(storage: storage)
        let controller = try instantiateController(statisticService: statistics, factory: factory, alertPresenter: alertPresenter)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.loadViewIfNeeded()
        controller.view.layoutIfNeeded()
        let screen = QuizScreen(
            controller: controller,
            window: window,
            poster: try find("Poster", in: controller.view),
            question: try find("questionText", in: controller.view),
            number: try find("Index", in: controller.view),
            yes: try find("Yes", in: controller.view),
            no: try find("No", in: controller.view),
            statistics: statistics,
            storage: storage,
            suiteName: suiteName,
            factory: factory
        )
        if waitsForQuestion {
            try await waitUntil { screen.yes.isEnabled && screen.no.isEnabled }
        }
        return screen
    }

    private func currentQuestion(on screen: QuizScreen) throws -> QuizQuestion {
        try XCTUnwrap(screen.factory.currentQuestion)
    }

    private func assertResult(_ alert: UIAlertController, correct: Int, on screen: QuizScreen, file: StaticString = #filePath, line: UInt = #line) {
        let expectedAccuracy = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), Double(correct) * 10)
        let expected = """
        Ваш результат: \(correct)/10
        Количество сыгранных квизов: 1
        Рекорд: \(correct)/10 (\(screen.statistics.bestGame.date.dateTimeString))
        Средняя точность: \(expectedAccuracy)%
        """
        XCTAssertEqual(alert.message, expected, file: file, line: line)
        XCTAssertEqual(screen.statistics.gamesCount, 1, file: file, line: line)
        XCTAssertEqual(screen.statistics.bestGame.correct, correct, file: file, line: line)
        XCTAssertEqual(screen.statistics.bestGame.total, 10, file: file, line: line)
        XCTAssertEqual(screen.statistics.totalAccuracy, Double(correct) * 10, accuracy: 0.001, file: file, line: line)
    }

    private func answer(_ yes: Bool, question: Int, on screen: QuizScreen) async throws {
        XCTAssertEqual(screen.number.text, "\(question)/10")
        (yes ? screen.yes : screen.no).sendActions(for: .touchUpInside)
        if question < 10 {
            try await waitUntil { screen.number.text == "\(question + 1)/10" }
        } else {
            try await waitUntil { screen.controller.presentedViewController is UIAlertController }
        }
    }

    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("Timed out waiting for the visible quiz state to change.")
                throw NSError(domain: "MovieQuizTests.Timeout", code: 1)
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func find<T: UIView>(_ identifier: String, in root: UIView) throws -> T {
        try XCTUnwrap(descendants(of: root).first { $0.accessibilityIdentifier == identifier } as? T)
    }

    private func descendants(of view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
    }

    private func assertBorderColor(_ poster: UIImageView, red: CGFloat, green: CGFloat, blue: CGFloat, file: StaticString = #filePath, line: UInt = #line) {
        guard let color = poster.layer.borderColor else {
            return XCTFail("Answer feedback must have a border color.", file: file, line: line)
        }
        var actualRed: CGFloat = 0
        var actualGreen: CGFloat = 0
        var actualBlue: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(UIColor(cgColor: color).getRed(&actualRed, green: &actualGreen, blue: &actualBlue, alpha: &alpha), file: file, line: line)
        XCTAssertEqual(actualRed, red / 255, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actualGreen, green / 255, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actualBlue, blue / 255, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(alpha, 1, accuracy: 0.001, file: file, line: line)
    }
}
