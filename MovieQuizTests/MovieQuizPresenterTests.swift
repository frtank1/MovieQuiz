import Foundation
import XCTest
@testable import MovieQuiz

@MainActor
final class MovieQuizPresenterTests: XCTestCase {
    private final class ViewMock: MovieQuizViewControllerProtocol {
        private(set) var steps: [QuizStepViewModel] = []
        private(set) var results: [QuizResultsViewModel] = []
        private(set) var highlightedAnswers: [Bool] = []
        private(set) var loadingShownCount = 0
        private(set) var loadingHiddenCount = 0
        private(set) var errors: [String] = []
        private(set) var answerButtonsEnabled: [Bool] = []

        func show(quiz step: QuizStepViewModel) {
            XCTAssertTrue(Thread.isMainThread)
            steps.append(step)
        }

        func show(quiz result: QuizResultsViewModel) {
            XCTAssertTrue(Thread.isMainThread)
            results.append(result)
        }

        func highlightImageBorder(isCorrectAnswer: Bool) {
            XCTAssertTrue(Thread.isMainThread)
            highlightedAnswers.append(isCorrectAnswer)
        }

        func showLoadingIndicator() {
            XCTAssertTrue(Thread.isMainThread)
            loadingShownCount += 1
        }

        func hideLoadingIndicator() {
            XCTAssertTrue(Thread.isMainThread)
            loadingHiddenCount += 1
        }

        func showNetworkError(message: String) {
            XCTAssertTrue(Thread.isMainThread)
            errors.append(message)
        }

        func setAnswerButtonsEnabled(_ isEnabled: Bool) {
            XCTAssertTrue(Thread.isMainThread)
            answerButtonsEnabled.append(isEnabled)
        }
    }

    private final class QuestionFactoryMock: QuestionFactoryProtocol {
        weak var delegate: QuestionFactoryDelegate?
        private(set) var loadCount = 0
        private(set) var requestCount = 0

        func loadData() {
            loadCount += 1
        }

        func requestNextQuestion() {
            requestCount += 1
        }

        func finishLoading() {
            delegate?.didLoadDataFromServer()
        }

        func send(_ question: QuizQuestion?) {
            delegate?.didReceiveNextQuestion(question: question)
        }

        func fail(_ error: Error) {
            delegate?.didFailToLoadData(with: error)
        }
    }

    private final class StatisticsMock: StatisticServiceProtocol {
        struct StoredResult {
            let correct: Int
            let total: Int
        }

        var gamesCount = 0
        var bestGame = GameResult(correct: 0, total: 0, date: Date(timeIntervalSince1970: 0))
        var totalAccuracy = 0.0
        private(set) var storedResults: [StoredResult] = []

        func store(correct count: Int, total amount: Int) {
            storedResults.append(StoredResult(correct: count, total: amount))
            gamesCount += 1
            let result = GameResult(correct: count, total: amount, date: Date(timeIntervalSince1970: 0))
            if result.isBetterThan(bestGame) {
                bestGame = result
            }
            let correctTotal = storedResults.reduce(0) { $0 + $1.correct }
            let questionTotal = storedResults.reduce(0) { $0 + $1.total }
            totalAccuracy = questionTotal == 0 ? 0 : Double(correctTotal) / Double(questionTotal) * 100
        }
    }

    private final class SchedulerMock {
        struct Work {
            let delay: TimeInterval
            let action: () -> Void
        }

        private(set) var work: [Work] = []

        func schedule(after delay: TimeInterval, action: @escaping () -> Void) {
            work.append(Work(delay: delay, action: action))
        }

        func runNext() {
            guard !work.isEmpty else {
                XCTFail("No scheduled feedback work")
                return
            }
            work.removeFirst().action()
        }
    }

    private struct Fixture {
        let sut: MovieQuizPresenter
        let view: ViewMock
        let factory: QuestionFactoryMock
        let statistics: StatisticsMock
        let scheduler: SchedulerMock
    }

    private func makeSUT() -> Fixture {
        let view = ViewMock()
        let factory = QuestionFactoryMock()
        let statistics = StatisticsMock()
        let scheduler = SchedulerMock()
        let sut = MovieQuizPresenter(
            viewController: view,
            statisticService: statistics,
            questionFactoryBuilder: { delegate in
                factory.delegate = delegate
                return factory
            },
            schedule: { delay, action in
                scheduler.schedule(after: delay, action: action)
            }
        )
        return Fixture(sut: sut, view: view, factory: factory, statistics: statistics, scheduler: scheduler)
    }

    private func question(correctAnswer: Bool = true, text: String = "Question Text", image: Data = Data()) -> QuizQuestion {
        QuizQuestion(image: image, text: text, correctAnswer: correctAnswer)
    }

    private func drainMainQueue() {
        let drained = expectation(description: "Presenter callbacks delivered")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
    }

    private func load(_ fixture: Fixture) {
        fixture.factory.finishLoading()
        drainMainQueue()
    }

    private func showQuestion(_ fixture: Fixture, correctAnswer: Bool = true) {
        fixture.factory.send(question(correctAnswer: correctAnswer))
        drainMainQueue()
    }

    private func playRound(_ fixture: Fixture, answers: [Bool], expectedAnswers: [Bool]) {
        XCTAssertEqual(answers.count, 10)
        XCTAssertEqual(expectedAnswers.count, 10)
        for index in 0..<10 {
            showQuestion(fixture, correctAnswer: expectedAnswers[index])
            if answers[index] {
                fixture.sut.yesButtonClicked()
            } else {
                fixture.sut.noButtonClicked()
            }
            fixture.scheduler.runNext()
        }
    }

    func testPresenterConvertModel() {
        let fixture = makeSUT()
        let emptyData = Data()
        let model = QuizQuestion(image: emptyData, text: "Question Text", correctAnswer: true)

        let step = fixture.sut.convert(model: model)

        XCTAssertEqual(step.image, emptyData)
        XCTAssertEqual(step.question, "Question Text")
        XCTAssertEqual(step.questionNumber, "1/10")
    }

    func testInitializationLoadsMoviesAndShowsLoadingState() {
        let fixture = makeSUT()

        XCTAssertEqual(fixture.factory.loadCount, 1)
        XCTAssertEqual(fixture.factory.requestCount, 0)
        XCTAssertGreaterThan(fixture.view.loadingShownCount, 0)
        XCTAssertEqual(fixture.view.answerButtonsEnabled.last, false)
        XCTAssertEqual(fixture.view.steps.count, 1)
        XCTAssertEqual(fixture.view.steps.first?.question, "Загрузка фильмов…")
        XCTAssertTrue(fixture.statistics.storedResults.isEmpty)
    }

    func testLoadedMovieListRequestsFirstQuestion() {
        let fixture = makeSUT()

        load(fixture)

        XCTAssertEqual(fixture.factory.requestCount, 1)
        XCTAssertEqual(fixture.view.answerButtonsEnabled.last, false)
        XCTAssertTrue(fixture.view.results.isEmpty)
    }

    func testReceivedQuestionDisplaysDataAndEnablesAnswers() {
        let fixture = makeSUT()
        load(fixture)
        let data = Data([0, 1, 2, 3])

        fixture.factory.send(question(text: "A new question", image: data))
        drainMainQueue()

        XCTAssertEqual(fixture.view.steps.count, 2)
        XCTAssertEqual(fixture.view.steps.last?.image, data)
        XCTAssertEqual(fixture.view.steps.last?.question, "A new question")
        XCTAssertEqual(fixture.view.steps.last?.questionNumber, "1/10")
        XCTAssertGreaterThan(fixture.view.loadingHiddenCount, 0)
        XCTAssertEqual(fixture.view.answerButtonsEnabled.last, true)
    }

    func testYesAnswerChecksTrueQuestionAndSchedulesOneSecondFeedback() {
        let fixture = makeSUT()
        load(fixture)
        showQuestion(fixture)

        fixture.sut.yesButtonClicked()

        XCTAssertEqual(fixture.view.highlightedAnswers, [true])
        XCTAssertEqual(fixture.view.answerButtonsEnabled.last, false)
        XCTAssertEqual(fixture.scheduler.work.count, 1)
        XCTAssertEqual(fixture.scheduler.work.first?.delay, 1)
        XCTAssertEqual(fixture.factory.requestCount, 1)

        fixture.scheduler.runNext()

        XCTAssertEqual(fixture.factory.requestCount, 2)
        XCTAssertEqual(fixture.sut.convert(model: question()).questionNumber, "2/10")
    }

    func testNoAnswerChecksFalseQuestionAsCorrect() {
        let fixture = makeSUT()
        load(fixture)
        showQuestion(fixture, correctAnswer: false)

        fixture.sut.noButtonClicked()

        XCTAssertEqual(fixture.view.highlightedAnswers, [true])
        XCTAssertEqual(fixture.scheduler.work.count, 1)
    }

    func testWrongAnswerHighlightsIncorrectResult() {
        let fixture = makeSUT()
        load(fixture)
        showQuestion(fixture, correctAnswer: true)

        fixture.sut.noButtonClicked()

        XCTAssertEqual(fixture.view.highlightedAnswers, [false])
        XCTAssertEqual(fixture.scheduler.work.count, 1)
    }

    func testRepeatedTapsCannotScheduleOrScoreMoreThanOneAnswer() {
        let fixture = makeSUT()
        load(fixture)
        showQuestion(fixture)

        fixture.sut.yesButtonClicked()
        fixture.sut.yesButtonClicked()
        fixture.sut.noButtonClicked()

        XCTAssertEqual(fixture.view.highlightedAnswers, [true])
        XCTAssertEqual(fixture.scheduler.work.count, 1)
        fixture.scheduler.runNext()
        for _ in 1..<10 {
            showQuestion(fixture)
            fixture.sut.noButtonClicked()
            fixture.scheduler.runNext()
        }

        XCTAssertEqual(fixture.statistics.storedResults.count, 1)
        XCTAssertEqual(fixture.statistics.storedResults.first?.correct, 1)
        XCTAssertEqual(fixture.statistics.storedResults.first?.total, 10)
    }

    func testTapsBeforeQuestionAndDuringNextQuestionLoadingAreIgnored() {
        let fixture = makeSUT()

        fixture.sut.yesButtonClicked()
        fixture.sut.noButtonClicked()
        XCTAssertTrue(fixture.view.highlightedAnswers.isEmpty)
        XCTAssertTrue(fixture.scheduler.work.isEmpty)

        load(fixture)
        showQuestion(fixture)
        fixture.sut.yesButtonClicked()
        fixture.scheduler.runNext()
        fixture.sut.yesButtonClicked()
        fixture.sut.noButtonClicked()

        XCTAssertEqual(fixture.view.highlightedAnswers, [true])
        XCTAssertTrue(fixture.scheduler.work.isEmpty)
    }

    func testTenAnswersStoreOneRoundAndDisplayResults() {
        let fixture = makeSUT()
        load(fixture)
        let answers = [true, false, true, false, true, false, true, false, true, false]

        playRound(fixture, answers: answers, expectedAnswers: answers)

        XCTAssertEqual(fixture.factory.requestCount, 10)
        XCTAssertEqual(fixture.statistics.storedResults.count, 1)
        XCTAssertEqual(fixture.statistics.storedResults.first?.correct, 10)
        XCTAssertEqual(fixture.statistics.storedResults.first?.total, 10)
        XCTAssertEqual(fixture.view.results.count, 1)
        XCTAssertEqual(fixture.view.results.first?.title, "Этот раунд окончен!")
        XCTAssertTrue(fixture.view.results.first?.text.contains("10/10") == true)
        XCTAssertTrue(fixture.view.results.first?.text.contains("100.00%") == true)
        XCTAssertEqual(fixture.view.steps.dropFirst().map(\.questionNumber), (1...10).map { "\($0)/10" })
        XCTAssertTrue(fixture.scheduler.work.isEmpty)
    }

    func testMixedAnswersProduceExactScore() {
        let fixture = makeSUT()
        load(fixture)

        playRound(
            fixture,
            answers: [true, true, true, false, false, false, false, false, false, false],
            expectedAnswers: Array(repeating: true, count: 10)
        )

        XCTAssertEqual(fixture.statistics.storedResults.first?.correct, 3)
        XCTAssertTrue(fixture.view.results.first?.text.contains("3/10") == true)
        XCTAssertTrue(fixture.view.results.first?.text.contains("30.00%") == true)
    }

    func testRestartResetsQuestionNumberAndScoreWithoutReloadingMovies() {
        let fixture = makeSUT()
        load(fixture)
        playRound(fixture, answers: Array(repeating: true, count: 10), expectedAnswers: Array(repeating: true, count: 10))

        fixture.sut.restartGame()

        XCTAssertEqual(fixture.factory.loadCount, 1)
        XCTAssertEqual(fixture.factory.requestCount, 11)
        XCTAssertEqual(fixture.sut.convert(model: question()).questionNumber, "1/10")
        playRound(fixture, answers: Array(repeating: false, count: 10), expectedAnswers: Array(repeating: true, count: 10))

        XCTAssertEqual(fixture.statistics.storedResults.map(\.correct), [10, 0])
        XCTAssertEqual(fixture.view.results.count, 2)
        XCTAssertTrue(fixture.view.results.last?.text.contains("0/10") == true)
    }

    func testLoadFailureDisplaysErrorAndRetryReloadsMovies() {
        let fixture = makeSUT()
        let error = NSError(domain: "PresenterTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "Connection failed"])

        fixture.factory.fail(error)
        drainMainQueue()

        XCTAssertEqual(fixture.view.errors, ["Connection failed"])
        XCTAssertEqual(fixture.view.answerButtonsEnabled.last, false)
        XCTAssertGreaterThan(fixture.view.loadingHiddenCount, 0)
        XCTAssertTrue(fixture.statistics.storedResults.isEmpty)

        fixture.sut.retryLoading()

        XCTAssertEqual(fixture.factory.loadCount, 2)
        XCTAssertEqual(fixture.sut.convert(model: question()).questionNumber, "1/10")
        load(fixture)
        showQuestion(fixture)
        XCTAssertEqual(fixture.view.answerButtonsEnabled.last, true)
    }

    func testNilQuestionDisplaysErrorWithoutRecordingRound() {
        let fixture = makeSUT()
        load(fixture)

        fixture.factory.send(nil)
        drainMainQueue()

        XCTAssertEqual(fixture.view.errors.count, 1)
        XCTAssertFalse(fixture.view.errors.first?.isEmpty ?? true)
        XCTAssertEqual(fixture.view.steps.count, 1)
        XCTAssertEqual(fixture.view.steps.first?.question, "Загрузка фильмов…")
        XCTAssertTrue(fixture.statistics.storedResults.isEmpty)
        XCTAssertEqual(fixture.view.answerButtonsEnabled.last, false)
    }

    func testRetryDiscardsUnfinishedScoreAndStaleScheduledFeedback() {
        let fixture = makeSUT()
        load(fixture)
        showQuestion(fixture)
        fixture.sut.yesButtonClicked()

        fixture.sut.retryLoading()
        fixture.scheduler.runNext()

        XCTAssertEqual(fixture.factory.loadCount, 2)
        XCTAssertEqual(fixture.factory.requestCount, 1)
        XCTAssertTrue(fixture.statistics.storedResults.isEmpty)
        XCTAssertEqual(fixture.sut.convert(model: question()).questionNumber, "1/10")

        load(fixture)
        playRound(fixture, answers: Array(repeating: false, count: 10), expectedAnswers: Array(repeating: true, count: 10))

        XCTAssertEqual(fixture.statistics.storedResults.map(\.correct), [0])
    }

    func testFailureInvalidatesPendingFeedback() {
        let fixture = makeSUT()
        load(fixture)
        showQuestion(fixture)
        fixture.sut.yesButtonClicked()

        fixture.factory.fail(URLError(.timedOut))
        drainMainQueue()
        fixture.scheduler.runNext()

        XCTAssertEqual(fixture.factory.requestCount, 1)
        XCTAssertEqual(fixture.view.errors.count, 1)
        XCTAssertTrue(fixture.view.results.isEmpty)
        XCTAssertTrue(fixture.statistics.storedResults.isEmpty)
    }

    func testQuestionIndexHelpersKeepConversionAndLastQuestionInSync() {
        let fixture = makeSUT()
        XCTAssertFalse(fixture.sut.isLastQuestion())

        for _ in 0..<9 {
            fixture.sut.switchToNextQuestion()
        }

        XCTAssertTrue(fixture.sut.isLastQuestion())
        XCTAssertEqual(fixture.sut.convert(model: question()).questionNumber, "10/10")

        fixture.sut.resetQuestionIndex()

        XCTAssertFalse(fixture.sut.isLastQuestion())
        XCTAssertEqual(fixture.sut.convert(model: question()).questionNumber, "1/10")
    }

    func testResultsMessageUsesInjectedStatisticsAndTwoDecimalAccuracy() {
        let fixture = makeSUT()
        fixture.statistics.gamesCount = 4
        fixture.statistics.bestGame = GameResult(correct: 8, total: 10, date: Date(timeIntervalSince1970: 0))
        fixture.statistics.totalAccuracy = 72.126

        let message = fixture.sut.makeResultsMessage()

        XCTAssertTrue(message.contains("0/10"))
        XCTAssertTrue(message.contains("4"))
        XCTAssertTrue(message.contains("8/10"))
        XCTAssertTrue(message.contains("72.13%"))
    }

    func testPresenterDoesNotRetainItsView() throws {
        var view: ViewMock? = ViewMock()
        weak var weakView = view
        let factory = QuestionFactoryMock()
        let sut = MovieQuizPresenter(
            viewController: try XCTUnwrap(view),
            statisticService: StatisticsMock(),
            questionFactoryBuilder: { delegate in
                factory.delegate = delegate
                return factory
            },
            schedule: { _, _ in }
        )

        view = nil

        XCTAssertNil(weakView)
        factory.finishLoading()
        drainMainQueue()
        factory.send(question())
        drainMainQueue()
        XCTAssertEqual(sut.questionsAmount, 10)
        XCTAssertNil(weakView)
    }

    func testPendingFeedbackDoesNotRetainPresenter() {
        let view = ViewMock()
        let factory = QuestionFactoryMock()
        let scheduler = SchedulerMock()
        var sut: MovieQuizPresenter? = MovieQuizPresenter(
            viewController: view,
            statisticService: StatisticsMock(),
            questionFactoryBuilder: { delegate in
                factory.delegate = delegate
                return factory
            },
            schedule: { delay, action in scheduler.schedule(after: delay, action: action) }
        )
        weak var weakPresenter = sut
        factory.finishLoading()
        drainMainQueue()
        factory.send(question())
        drainMainQueue()
        sut?.yesButtonClicked()
        XCTAssertEqual(scheduler.work.count, 1)

        sut = nil

        XCTAssertNil(weakPresenter)
        scheduler.runNext()
        XCTAssertNil(weakPresenter)
        XCTAssertTrue(view.results.isEmpty)
    }
}
