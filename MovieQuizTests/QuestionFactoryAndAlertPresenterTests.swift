import XCTest
import UIKit
@testable import MovieQuiz

@MainActor
final class QuestionFactoryTests: XCTestCase {
    private final class DelegateSpy: QuestionFactoryDelegate {
        private(set) var receivedQuestions: [QuizQuestion?] = []
        private(set) var loadedCount = 0
        private(set) var errors: [Error] = []
        var onLoad: (() -> Void)?
        var onQuestion: (() -> Void)?
        var onFailure: (() -> Void)?

        func didReceiveNextQuestion(question: QuizQuestion?) {
            XCTAssertTrue(Thread.isMainThread)
            receivedQuestions.append(question)
            onQuestion?()
        }

        func didLoadDataFromServer() {
            XCTAssertTrue(Thread.isMainThread)
            loadedCount += 1
            onLoad?()
        }

        func didFailToLoadData(with error: Error) {
            XCTAssertTrue(Thread.isMainThread)
            errors.append(error)
            onFailure?()
        }
    }

    private final class MoviesLoaderStub: MoviesLoading {
        private(set) var requests: [(Result<MostPopularMovies, Error>) -> Void] = []

        func loadMovies(handler: @escaping (Result<MostPopularMovies, Error>) -> Void) {
            requests.append(handler)
        }
    }

    private final class NetworkClientStub: NetworkRouting {
        struct Request {
            let url: URL
            let handler: (Result<Data, Error>) -> Void
        }
        private(set) var requests: [Request] = []

        func fetch(url: URL, handler: @escaping (Result<Data, Error>) -> Void) {
            requests.append(Request(url: url, handler: handler))
        }
    }

    private func movie(rating: String = "8.2", image: String = "https://images.example.invalid/poster.jpg") -> MostPopularMovie {
        MostPopularMovie(title: "Film (2026)", rating: rating, imageURL: URL(string: image)!)
    }

    private func imageData() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
        return renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }.pngData()!
    }

    private func drainMainQueue() {
        let drained = expectation(description: "Main callbacks delivered")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 2)
    }

    private func load(_ movies: [MostPopularMovie], factory: QuestionFactory, loader: MoviesLoaderStub) {
        factory.loadData()
        loader.requests.last?(.success(MostPopularMovies(errorMessage: "", items: movies, success: true)))
        drainMainQueue()
    }

    func testLoadingMovieListDoesNotRequestPosterUntilQuestionIsRequested() {
        let loader = MoviesLoaderStub()
        let client = NetworkClientStub()
        let delegate = DelegateSpy()
        let factory = QuestionFactory(moviesLoader: loader, delegate: delegate, networkClient: client)

        load([movie()], factory: factory, loader: loader)

        XCTAssertEqual(loader.requests.count, 1)
        XCTAssertEqual(delegate.loadedCount, 1)
        XCTAssertTrue(client.requests.isEmpty)
        XCTAssertTrue(delegate.receivedQuestions.isEmpty)
        XCTAssertTrue(delegate.errors.isEmpty)
    }

    func testValidPosterProducesOneQuestionWithRatingAboveSeven() throws {
        let loader = MoviesLoaderStub()
        let client = NetworkClientStub()
        let delegate = DelegateSpy()
        let factory = QuestionFactory(moviesLoader: loader, delegate: delegate, networkClient: client)
        load([movie(rating: "7.1")], factory: factory, loader: loader)

        factory.requestNextQuestion()
        XCTAssertEqual(client.requests.count, 1)
        let data = imageData()
        client.requests[0].handler(.success(data))
        drainMainQueue()

        XCTAssertEqual(delegate.receivedQuestions.count, 1)
        let question = try XCTUnwrap(delegate.receivedQuestions.first ?? nil)
        XCTAssertEqual(question.image, data)
        XCTAssertNotNil(UIImage(data: question.image))
        XCTAssertEqual(question.text, "Рейтинг этого фильма больше, чем 7?")
        XCTAssertTrue(question.correctAnswer)
        XCTAssertTrue(delegate.errors.isEmpty)
    }

    func testRatingEqualToSevenProducesFalseAnswer() throws {
        let loader = MoviesLoaderStub()
        let client = NetworkClientStub()
        let delegate = DelegateSpy()
        let factory = QuestionFactory(moviesLoader: loader, delegate: delegate, networkClient: client)
        load([movie(rating: "7")], factory: factory, loader: loader)

        factory.requestNextQuestion()
        client.requests[0].handler(.success(imageData()))
        drainMainQueue()

        let question = try XCTUnwrap(delegate.receivedQuestions.first ?? nil)
        XCTAssertFalse(question.correctAnswer)
    }

    func testPosterRequestUsesResizedAmazonURL() {
        let loader = MoviesLoaderStub()
        let client = NetworkClientStub()
        let delegate = DelegateSpy()
        let factory = QuestionFactory(moviesLoader: loader, delegate: delegate, networkClient: client)
        load([movie(image: "https://m.media-amazon.com/images/poster._V1_w1200_h1800_AL_.jpg")], factory: factory, loader: loader)

        factory.requestNextQuestion()

        XCTAssertEqual(client.requests.first?.url.absoluteString, "https://m.media-amazon.com/images/poster._V0_UX600_.jpg")
    }

    func testListFailureIsForwardedAndRetryCanSucceed() throws {
        let loader = MoviesLoaderStub()
        let client = NetworkClientStub()
        let delegate = DelegateSpy()
        let factory = QuestionFactory(moviesLoader: loader, delegate: delegate, networkClient: client)
        let expected = NSError(domain: "MovieQuiz.FactoryTests", code: 51)

        factory.loadData()
        loader.requests[0](.failure(expected))
        drainMainQueue()

        XCTAssertTrue(try XCTUnwrap(delegate.errors.first) as NSError === expected)
        XCTAssertEqual(delegate.loadedCount, 0)
        XCTAssertTrue(client.requests.isEmpty)

        load([movie()], factory: factory, loader: loader)

        XCTAssertEqual(loader.requests.count, 2)
        XCTAssertEqual(delegate.loadedCount, 1)
        XCTAssertEqual(delegate.errors.count, 1)
    }

    func testEmptyMovieListReportsFailure() throws {
        let loader = MoviesLoaderStub()
        let delegate = DelegateSpy()
        let factory = QuestionFactory(moviesLoader: loader, delegate: delegate, networkClient: NetworkClientStub())

        load([], factory: factory, loader: loader)

        guard case QuestionFactoryError.noMovies = try XCTUnwrap(delegate.errors.first) else {
            return XCTFail("Expected empty movie list error")
        }
        XCTAssertEqual(delegate.loadedCount, 0)
        XCTAssertTrue(delegate.receivedQuestions.isEmpty)
    }

    func testRequestBeforeLoadingReportsFailureWithoutNetworkRequest() throws {
        let client = NetworkClientStub()
        let delegate = DelegateSpy()
        let factory = QuestionFactory(moviesLoader: MoviesLoaderStub(), delegate: delegate, networkClient: client)

        factory.requestNextQuestion()

        guard case QuestionFactoryError.noMovies = try XCTUnwrap(delegate.errors.first) else {
            return XCTFail("Expected no movies error")
        }
        XCTAssertTrue(client.requests.isEmpty)
    }

    func testPosterTransportFailureIsForwarded() throws {
        let loader = MoviesLoaderStub()
        let client = NetworkClientStub()
        let delegate = DelegateSpy()
        let factory = QuestionFactory(moviesLoader: loader, delegate: delegate, networkClient: client)
        load([movie()], factory: factory, loader: loader)
        let expected = NSError(domain: NSURLErrorDomain, code: URLError.notConnectedToInternet.rawValue)

        factory.requestNextQuestion()
        client.requests[0].handler(.failure(expected))
        drainMainQueue()

        XCTAssertTrue(try XCTUnwrap(delegate.errors.first) as NSError === expected)
        XCTAssertTrue(delegate.receivedQuestions.isEmpty)
    }

    func testMalformedPosterDataReportsInvalidImage() throws {
        let loader = MoviesLoaderStub()
        let client = NetworkClientStub()
        let delegate = DelegateSpy()
        let factory = QuestionFactory(moviesLoader: loader, delegate: delegate, networkClient: client)
        load([movie()], factory: factory, loader: loader)

        factory.requestNextQuestion()
        client.requests[0].handler(.success(Data("not an image".utf8)))
        drainMainQueue()

        guard case QuestionFactoryError.invalidImage = try XCTUnwrap(delegate.errors.first) else {
            return XCTFail("Expected invalid image error")
        }
        XCTAssertTrue(delegate.receivedQuestions.isEmpty)
    }

    func testInvalidRatingsAreRejectedBeforePosterRequest() throws {
        for rating in ["", "not a rating", "nan", "inf", "-0.1", "10.1"] {
            let loader = MoviesLoaderStub()
            let client = NetworkClientStub()
            let delegate = DelegateSpy()
            let factory = QuestionFactory(moviesLoader: loader, delegate: delegate, networkClient: client)
            load([movie(rating: rating)], factory: factory, loader: loader)

            factory.requestNextQuestion()

            guard case QuestionFactoryError.invalidRating = try XCTUnwrap(delegate.errors.first) else {
                return XCTFail("Expected invalid rating error for \(rating)")
            }
            XCTAssertTrue(client.requests.isEmpty)
        }
    }

    func testNonNetworkPosterURLsAreRejected() throws {
        for image in ["file:///tmp/poster.png", "/relative-poster.jpg", "ftp://images.example.invalid/poster.jpg"] {
            let loader = MoviesLoaderStub()
            let client = NetworkClientStub()
            let delegate = DelegateSpy()
            let factory = QuestionFactory(moviesLoader: loader, delegate: delegate, networkClient: client)
            load([movie(image: image)], factory: factory, loader: loader)

            factory.requestNextQuestion()

            guard case QuestionFactoryError.invalidPosterURL = try XCTUnwrap(delegate.errors.first) else {
                return XCTFail("Expected invalid poster URL error")
            }
            XCTAssertTrue(client.requests.isEmpty)
        }
    }

    func testBackgroundListAndPosterSuccessCallbacksReachDelegateOnMainThread() {
        let loader = MoviesLoaderStub()
        let client = NetworkClientStub()
        let delegate = DelegateSpy()
        let factory = QuestionFactory(moviesLoader: loader, delegate: delegate, networkClient: client)
        let loaded = expectation(description: "List callback on main")
        let questionReceived = expectation(description: "Question callback on main")
        delegate.onLoad = { loaded.fulfill() }
        delegate.onQuestion = { questionReceived.fulfill() }
        factory.loadData()
        let response = MostPopularMovies(errorMessage: "", items: [movie()])
        let listCallback = loader.requests[0]

        DispatchQueue.global().async { listCallback(.success(response)) }
        wait(for: [loaded], timeout: 2)
        factory.requestNextQuestion()
        let posterCallback = client.requests[0].handler
        let data = imageData()
        DispatchQueue.global().async { posterCallback(.success(data)) }
        wait(for: [questionReceived], timeout: 2)

        XCTAssertEqual(delegate.loadedCount, 1)
        XCTAssertEqual(delegate.receivedQuestions.count, 1)
        XCTAssertTrue(delegate.errors.isEmpty)
    }

    func testBackgroundFailureCallbackReachesDelegateOnMainThread() {
        let loader = MoviesLoaderStub()
        let delegate = DelegateSpy()
        let factory = QuestionFactory(moviesLoader: loader, delegate: delegate, networkClient: NetworkClientStub())
        let failed = expectation(description: "Failure callback on main")
        delegate.onFailure = { failed.fulfill() }
        factory.loadData()
        let callback = loader.requests[0]

        DispatchQueue.global().async { callback(.failure(URLError(.timedOut))) }
        wait(for: [failed], timeout: 2)

        XCTAssertEqual(delegate.errors.count, 1)
    }

    func testBackgroundPosterFailureReachesDelegateOnMainThread() {
        let loader = MoviesLoaderStub()
        let client = NetworkClientStub()
        let delegate = DelegateSpy()
        let factory = QuestionFactory(moviesLoader: loader, delegate: delegate, networkClient: client)
        load([movie()], factory: factory, loader: loader)
        let failed = expectation(description: "Poster failure callback on main")
        delegate.onFailure = { failed.fulfill() }
        factory.requestNextQuestion()
        let callback = client.requests[0].handler

        DispatchQueue.global().async { callback(.failure(URLError(.timedOut))) }
        wait(for: [failed], timeout: 2)

        XCTAssertEqual(delegate.errors.count, 1)
        XCTAssertTrue(delegate.receivedQuestions.isEmpty)
    }

    func testOldListSuccessAndFailureCannotReplaceRetriedList() {
        let loader = MoviesLoaderStub()
        let client = NetworkClientStub()
        let delegate = DelegateSpy()
        let factory = QuestionFactory(moviesLoader: loader, delegate: delegate, networkClient: client)
        factory.loadData()
        factory.loadData()
        let newest = movie(image: "https://images.example.invalid/newest.jpg")

        loader.requests[1](.success(MostPopularMovies(errorMessage: "", items: [newest])))
        loader.requests[0](.success(MostPopularMovies(errorMessage: "", items: [movie()])))
        loader.requests[0](.failure(URLError(.timedOut)))
        drainMainQueue()
        factory.requestNextQuestion()

        XCTAssertEqual(delegate.loadedCount, 1)
        XCTAssertTrue(delegate.errors.isEmpty)
        XCTAssertEqual(client.requests.first?.url, newest.imageURL)
    }

    func testOldPosterCallbacksAreIgnoredAfterReloadingMovieList() {
        let loader = MoviesLoaderStub()
        let client = NetworkClientStub()
        let delegate = DelegateSpy()
        let factory = QuestionFactory(moviesLoader: loader, delegate: delegate, networkClient: client)
        load([movie()], factory: factory, loader: loader)
        factory.requestNextQuestion()
        factory.loadData()
        let data = imageData()

        client.requests[0].handler(.success(data))
        client.requests[0].handler(.failure(URLError(.timedOut)))
        loader.requests[1](.success(MostPopularMovies(errorMessage: "", items: [movie(rating: "7")])))
        drainMainQueue()

        XCTAssertEqual(delegate.loadedCount, 2)
        XCTAssertTrue(delegate.receivedQuestions.isEmpty)
        XCTAssertTrue(delegate.errors.isEmpty)

        factory.requestNextQuestion()
        client.requests[1].handler(.success(data))
        drainMainQueue()

        XCTAssertEqual(delegate.receivedQuestions.count, 1)
        XCTAssertEqual((delegate.receivedQuestions.first ?? nil)?.correctAnswer, false)
    }

    func testOnlyNewestQuestionRequestCanDeliverItsPoster() {
        let loader = MoviesLoaderStub()
        let client = NetworkClientStub()
        let delegate = DelegateSpy()
        let factory = QuestionFactory(moviesLoader: loader, delegate: delegate, networkClient: client)
        load([movie()], factory: factory, loader: loader)
        factory.requestNextQuestion()
        factory.requestNextQuestion()
        let data = imageData()

        client.requests[0].handler(.failure(URLError(.timedOut)))
        client.requests[1].handler(.success(data))
        client.requests[1].handler(.success(data))
        drainMainQueue()

        XCTAssertEqual(delegate.receivedQuestions.count, 1)
        XCTAssertTrue(delegate.errors.isEmpty)
    }

    func testFactoryDoesNotRetainDelegateAndMissingDelegateIsSafe() throws {
        let loader = MoviesLoaderStub()
        let client = NetworkClientStub()
        var delegate: DelegateSpy? = DelegateSpy()
        weak var weakDelegate = delegate
        let factory = QuestionFactory(moviesLoader: loader, delegate: try XCTUnwrap(delegate), networkClient: client)
        delegate = nil

        XCTAssertNil(weakDelegate)
        load([movie()], factory: factory, loader: loader)
        factory.requestNextQuestion()
        client.requests[0].handler(.success(imageData()))
        drainMainQueue()

        XCTAssertNil(weakDelegate)
    }

    func testPendingListCallbackDoesNotRetainFactory() {
        let loader = MoviesLoaderStub()
        let delegate = DelegateSpy()
        var factory: QuestionFactory? = QuestionFactory(moviesLoader: loader, delegate: delegate, networkClient: NetworkClientStub())
        weak var weakFactory = factory
        factory?.loadData()
        factory = nil

        XCTAssertNil(weakFactory)
        loader.requests[0](.success(MostPopularMovies(errorMessage: "", items: [movie()])))
        drainMainQueue()

        XCTAssertEqual(delegate.loadedCount, 0)
        XCTAssertTrue(delegate.errors.isEmpty)
    }

    func testPendingPosterCallbackDoesNotRetainFactory() throws {
        let loader = MoviesLoaderStub()
        let client = NetworkClientStub()
        let delegate = DelegateSpy()
        var factory: QuestionFactory? = QuestionFactory(moviesLoader: loader, delegate: delegate, networkClient: client)
        weak var weakFactory = factory
        load([movie()], factory: try XCTUnwrap(factory), loader: loader)
        factory?.requestNextQuestion()
        factory = nil

        XCTAssertNil(weakFactory)
        client.requests[0].handler(.success(imageData()))
        drainMainQueue()

        XCTAssertNil(weakFactory)
        XCTAssertTrue(delegate.receivedQuestions.isEmpty)
        XCTAssertTrue(delegate.errors.isEmpty)
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
