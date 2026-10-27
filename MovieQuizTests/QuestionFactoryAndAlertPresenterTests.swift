import XCTest
import UIKit
@testable import MovieQuiz

final class QuestionFactoryTests: XCTestCase {
    private final class DelegateSpy: QuestionFactoryDelegate {
        private(set) var receivedQuestions: [QuizQuestion?] = []

        func didReceiveNextQuestion(question: QuizQuestion?) {
            receivedQuestions.append(question)
        }
    }

    func testEachRequestDeliversExactlyOneValidQuestion() throws {
        let factory = QuestionFactory()
        let delegate = DelegateSpy()
        let expectedAnswers = [
            "The Godfather": true,
            "The Dark Knight": true,
            "Kill Bill": true,
            "The Avengers": true,
            "Deadpool": true,
            "The Green Knight": true,
            "Old": false,
            "The Ice Age Adventures of Buck Wild": false,
            "Tesla": false,
            "Vivarium": false
        ]
        factory.setup(delegate: delegate)
        XCTAssertTrue(delegate.receivedQuestions.isEmpty)

        for requestNumber in 1...100 {
            factory.requestNextQuestion()

            XCTAssertEqual(delegate.receivedQuestions.count, requestNumber)
            let question = try XCTUnwrap(delegate.receivedQuestions.last ?? nil)
            let expectedAnswer = try XCTUnwrap(expectedAnswers[question.imageName])
            XCTAssertEqual(question.text, "Рейтинг этого фильма больше чем 6?")
            XCTAssertEqual(question.correctAnswer, expectedAnswer)
        }
    }

    func testFactoryDoesNotRetainItsDelegate() {
        let factory = QuestionFactory()
        var delegate: DelegateSpy? = DelegateSpy()
        weak var weakDelegate = delegate
        if let delegate {
            factory.setup(delegate: delegate)
        }

        XCTAssertNotNil(weakDelegate)
        delegate = nil

        XCTAssertNil(weakDelegate)
        factory.requestNextQuestion()
    }

    func testSetupReplacesThePreviousDelegate() {
        let factory = QuestionFactory()
        let firstDelegate = DelegateSpy()
        let secondDelegate = DelegateSpy()
        factory.setup(delegate: firstDelegate)
        factory.requestNextQuestion()
        XCTAssertEqual(firstDelegate.receivedQuestions.count, 1)

        factory.setup(delegate: secondDelegate)
        XCTAssertEqual(firstDelegate.receivedQuestions.count, 1)
        XCTAssertTrue(secondDelegate.receivedQuestions.isEmpty)
        factory.requestNextQuestion()

        XCTAssertEqual(firstDelegate.receivedQuestions.count, 1)
        XCTAssertEqual(secondDelegate.receivedQuestions.count, 1)
    }

    func testRequestsWithoutADelegateAreSafeAndDoNotReplayAfterSetup() {
        let factory = QuestionFactory()
        for _ in 0..<3 {
            factory.requestNextQuestion()
        }

        let delegate = DelegateSpy()
        factory.setup(delegate: delegate)
        XCTAssertTrue(delegate.receivedQuestions.isEmpty)
        factory.requestNextQuestion()

        XCTAssertEqual(delegate.receivedQuestions.count, 1)
        XCTAssertNotNil(delegate.receivedQuestions.first ?? nil)
    }
}

@MainActor
final class AlertPresenterTests: XCTestCase {
    private final class ViewControllerSpy: UIViewController {
        private(set) var presentationCount = 0
        private(set) var presentedController: UIViewController?
        private(set) var wasAnimated: Bool?

        override func present(
            _ viewControllerToPresent: UIViewController,
            animated flag: Bool,
            completion: (() -> Void)? = nil
        ) {
            presentationCount += 1
            presentedController = viewControllerToPresent
            wasAnimated = flag
        }
    }

    func testShowPresentsOneAlertWithTheModelContentAndOneDefaultAction() throws {
        let owner = ViewControllerSpy()
        let presenter = AlertPresenter(viewController: owner)
        var completionCalls = 0
        let model = AlertModel(
            title: "Результат тестового раунда",
            message: "Верных ответов: 7 из 10",
            buttonText: "Начать новый раунд",
            completion: { completionCalls += 1 }
        )

        presenter.show(model: model)

        XCTAssertEqual(owner.presentationCount, 1)
        XCTAssertEqual(owner.wasAnimated, true)
        let alert = try XCTUnwrap(owner.presentedController as? UIAlertController)
        XCTAssertEqual(alert.preferredStyle, .alert)
        XCTAssertEqual(alert.title, model.title)
        XCTAssertEqual(alert.message, model.message)
        XCTAssertEqual(alert.actions.count, 1)
        let action = try XCTUnwrap(alert.actions.first)
        XCTAssertEqual(action.title, model.buttonText)
        XCTAssertEqual(action.style, .default)
        XCTAssertTrue(action.isEnabled)
        XCTAssertEqual(completionCalls, 0)
    }

    func testPresenterDoesNotRetainItsOwnerAndShowIsSafeAfterOwnerDeallocation() throws {
        var owner: ViewControllerSpy? = ViewControllerSpy()
        weak var weakOwner = owner
        let presenter = AlertPresenter(viewController: try XCTUnwrap(owner))
        XCTAssertNotNil(weakOwner)

        owner = nil

        XCTAssertNil(weakOwner)
        var completionCalls = 0
        presenter.show(model: AlertModel(
            title: "Раунд окончен",
            message: "Результат: 0/10",
            buttonText: "Повторить",
            completion: { completionCalls += 1 }
        ))
        XCTAssertNil(weakOwner)
        XCTAssertEqual(completionCalls, 0)
    }
}
