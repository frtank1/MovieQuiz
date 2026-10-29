import XCTest
import UIKit
@testable import MovieQuiz

@MainActor
final class MovieQuizViewControllerTests: XCTestCase {
    @MainActor
    private struct QuizScreen {
        let controller: MovieQuizViewController
        let window: UIWindow
        let poster: UIImageView
        let question: UILabel
        let number: UILabel
        let yes: UIButton
        let no: UIButton

        func close() {
            controller.dismiss(animated: false)
            window.isHidden = true
            window.rootViewController = nil
        }
    }

    func testStoryboardStartsAtFirstQuestionWithLoadedPoster() throws {
        let screen = try makeScreen()
        defer { screen.close() }

        XCTAssertEqual(screen.number.text, "1/10")
        XCTAssertEqual(screen.question.text, "Рейтинг этого фильма больше чем 6?")
        XCTAssertEqual(screen.yes.title(for: .normal), "Да")
        XCTAssertEqual(screen.no.title(for: .normal), "Нет")
        XCTAssertTrue(screen.yes.isEnabled)
        XCTAssertTrue(screen.no.isEnabled)
        XCTAssertEqual(screen.poster.image?.pngData(), UIImage(named: "The Godfather")?.pngData())
        XCTAssertGreaterThan(screen.poster.image?.size.width ?? 0, 0)
        XCTAssertEqual(screen.poster.layer.cornerRadius, 20)
        XCTAssertTrue(screen.poster.clipsToBounds)
        XCTAssertEqual(screen.poster.layer.borderWidth, 0)
    }

    func testPerfectRoundIgnoresRepeatedAnswersAndClearsFeedbackAfterOneSecond() async throws {
        let screen = try makeScreen()
        defer { screen.close() }

        let answeredAt = Date()
        screen.yes.sendActions(for: .touchUpInside)
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
        XCTAssertEqual(screen.poster.image?.pngData(), UIImage(named: "The Dark Knight")?.pngData())

        for question in 2...10 {
            try await answer(question <= 6, question: question, on: screen)
        }
        let alert = try XCTUnwrap(screen.controller.presentedViewController as? UIAlertController)
        XCTAssertEqual(alert.title, "Этот раунд окончен!")
        XCTAssertEqual(alert.message, "Ваш результат: 10/10")
        XCTAssertEqual(alert.actions.map(\.title), ["Сыграть ещё раз"])
        XCTAssertEqual(screen.poster.layer.borderWidth, 0)
        XCTAssertFalse(screen.yes.isEnabled)
        XCTAssertFalse(screen.no.isEnabled)
    }

    func testWrongAnswerShowsRedFeedbackAndIsExcludedFromScore() async throws {
        let screen = try makeScreen()
        defer { screen.close() }

        screen.no.sendActions(for: .touchUpInside)
        XCTAssertEqual(screen.poster.layer.borderWidth, 8)
        assertBorderColor(screen.poster, red: 245, green: 107, blue: 108)
        try await waitUntil { screen.number.text == "2/10" }
        for question in 2...10 {
            try await answer(question <= 6, question: question, on: screen)
        }
        let alert = try XCTUnwrap(screen.controller.presentedViewController as? UIAlertController)
        XCTAssertEqual(alert.message, "Ваш результат: 9/10")
        XCTAssertEqual(alert.actions.first?.title, "Сыграть ещё раз")
        XCTAssertEqual(screen.poster.layer.borderWidth, 0)
    }

    func testLayoutIsUnambiguousAtCommonPortraitSizes() throws {
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

            let poster: UIImageView = try find("moviePoster", in: controller.view)
            let question: UILabel = try find("questionText", in: controller.view)
            let yes: UIButton = try find("yesButton", in: controller.view)
            let no: UIButton = try find("noButton", in: controller.view)
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

    private func instantiateController() throws -> MovieQuizViewController {
        let storyboard = UIStoryboard(name: "Main", bundle: Bundle(for: MovieQuizViewController.self))
        return try XCTUnwrap(storyboard.instantiateInitialViewController() as? MovieQuizViewController)
    }

    private func makeScreen() throws -> QuizScreen {
        let controller = try instantiateController()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.loadViewIfNeeded()
        controller.view.layoutIfNeeded()
        return QuizScreen(
            controller: controller,
            window: window,
            poster: try find("moviePoster", in: controller.view),
            question: try find("questionText", in: controller.view),
            number: try find("questionNumber", in: controller.view),
            yes: try find("yesButton", in: controller.view),
            no: try find("noButton", in: controller.view)
        )
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
