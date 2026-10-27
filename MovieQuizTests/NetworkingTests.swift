import Foundation
import XCTest
@testable import MovieQuiz

private final class MovieQuizURLProtocol: URLProtocol {
    struct Stub {
        let response: URLResponse?
        let data: Data?
        let error: Error?
    }

    private static let lock = NSLock()
    private static var stubs: [URL: Stub] = [:]
    private static var requests: [URL: URLRequest] = [:]

    static func register(_ stub: Stub, for url: URL) {
        lock.lock()
        defer { lock.unlock() }
        stubs[url] = stub
    }

    static func recordedRequest(for url: URL) -> URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return requests[url]
    }

    static func remove(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        stubs.removeValue(forKey: url)
        requests.removeValue(forKey: url)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        Self.lock.lock()
        let stub = Self.stubs[url]
        Self.requests[url] = request
        Self.lock.unlock()

        guard let stub else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        if let error = stub.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        if let response = stub.response {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        if let data = stub.data {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class NetworkClientTests: XCTestCase {
    private let url = URL(string: "https://network-client.example.invalid/\(UUID().uuidString)")!
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MovieQuizURLProtocol.self]
        session = URLSession(configuration: configuration)
    }

    override func tearDown() {
        session.invalidateAndCancel()
        session = nil
        MovieQuizURLProtocol.remove(url)
        super.tearDown()
    }

    private func httpResponse(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
    }

    private func fetch() throws -> Result<Data, Error> {
        let completed = expectation(description: "Request completed")
        completed.assertForOverFulfill = true
        var received: Result<Data, Error>?
        NetworkClient(session: session).fetch(url: url) { result in
            received = result
            completed.fulfill()
        }
        wait(for: [completed], timeout: 2)
        return try XCTUnwrap(received)
    }

    func testSuccessfulHTTPResponseReturnsUnmodifiedDataAndUsesGET() throws {
        let expected = Data("movie response".utf8)
        MovieQuizURLProtocol.register(.init(response: httpResponse(200), data: expected, error: nil), for: url)

        XCTAssertEqual(try fetch().get(), expected)
        let request = try XCTUnwrap(MovieQuizURLProtocol.recordedRequest(for: url))
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url, url)
        XCTAssertEqual(request.timeoutInterval, 30, accuracy: 0.001)
    }

    func testLastSuccessfulHTTPStatusIsAccepted() throws {
        let expected = Data([0, 1, 2, 255])
        MovieQuizURLProtocol.register(.init(response: httpResponse(299), data: expected, error: nil), for: url)

        XCTAssertEqual(try fetch().get(), expected)
    }

    func testNoContentIsReturnedAsEmptyData() throws {
        MovieQuizURLProtocol.register(.init(response: httpResponse(204), data: Data(), error: nil), for: url)

        XCTAssertEqual(try fetch().get(), Data())
    }

    func testHTTPClientErrorIsReportedWithItsStatus() throws {
        MovieQuizURLProtocol.register(.init(response: httpResponse(404), data: Data("not found".utf8), error: nil), for: url)

        guard case .failure(let error) = try fetch(),
              case NetworkClientError.httpStatusCode(let code) = error else {
            return XCTFail("Expected HTTP status error")
        }
        XCTAssertEqual(code, 404)
    }

    func testHTTPServerErrorIsReportedWithItsStatus() throws {
        MovieQuizURLProtocol.register(.init(response: httpResponse(503), data: Data(), error: nil), for: url)

        guard case .failure(let error) = try fetch(),
              case NetworkClientError.httpStatusCode(let code) = error else {
            return XCTFail("Expected HTTP status error")
        }
        XCTAssertEqual(code, 503)
    }

    func testTransportErrorIsPreserved() throws {
        MovieQuizURLProtocol.register(.init(response: nil, data: nil, error: URLError(.timedOut)), for: url)

        guard case .failure(let error) = try fetch() else {
            return XCTFail("Expected transport failure")
        }
        XCTAssertEqual((error as NSError).domain, NSURLErrorDomain)
        XCTAssertEqual((error as NSError).code, URLError.timedOut.rawValue)
    }

    func testNonHTTPResponseIsRejected() {
        let response = URLResponse(url: url, mimeType: "application/json", expectedContentLength: 2, textEncodingName: "utf-8")
        let result = NetworkClient.makeResult(data: Data("{}".utf8), response: response, error: nil)

        guard case .failure(let error) = result,
              case NetworkClientError.invalidResponse = error else {
            return XCTFail("Expected invalid response error")
        }
    }

    func testMissingResponseIsRejected() {
        let result = NetworkClient.makeResult(data: Data(), response: nil, error: nil)

        guard case .failure(let error) = result,
              case NetworkClientError.invalidResponse = error else {
            return XCTFail("Expected invalid response error")
        }
    }

    func testNilDataIsRejected() {
        let result = NetworkClient.makeResult(data: nil, response: httpResponse(200), error: nil)

        guard case .failure(let error) = result,
              case NetworkClientError.missingData = error else {
            return XCTFail("Expected missing data error")
        }
    }

    func testTransportFailureTakesPrecedenceOverResponseAndData() {
        let result = NetworkClient.makeResult(
            data: Data("{}".utf8),
            response: httpResponse(500),
            error: URLError(.notConnectedToInternet)
        )

        guard case .failure(let error) = result else {
            return XCTFail("Expected transport failure")
        }
        XCTAssertEqual((error as NSError).domain, NSURLErrorDomain)
        XCTAssertEqual((error as NSError).code, URLError.notConnectedToInternet.rawValue)
    }

    func testNon2xxBoundaryIsRejected() {
        for status in [199, 300] {
            let result = NetworkClient.makeResult(data: Data(), response: httpResponse(status), error: nil)

            guard case .failure(let error) = result,
                  case NetworkClientError.httpStatusCode(let actualStatus) = error else {
                return XCTFail("Expected HTTP error for \(status)")
            }
            XCTAssertEqual(actualStatus, status)
        }
    }
}

final class MoviesLoaderTests: XCTestCase {
    private final class StubNetworkClient: NetworkRouting {
        enum TestError: Error, Equatable {
            case test
        }

        private let emulateError: Bool

        init(emulateError: Bool) {
            self.emulateError = emulateError
        }

        func fetch(url: URL, handler: @escaping (Result<Data, Error>) -> Void) {
            if emulateError {
                handler(.failure(TestError.test))
            } else {
                let json = #"{"errorMessage":"","items":[{"fullTitle":"Prey (2022)","imDbRating":"7.2","image":"https://images.example.invalid/prey.jpg"},{"fullTitle":"The Gray Man (2022)","imDbRating":"6.5","image":"https://images.example.invalid/the-gray-man.jpg"}]}"#
                handler(.success(Data(json.utf8)))
            }
        }
    }

    private final class NetworkClientStub: NetworkRouting {
        let result: Result<Data, Error>
        private(set) var requestedURLs: [URL] = []

        init(result: Result<Data, Error>) {
            self.result = result
        }

        func fetch(url: URL, handler: @escaping (Result<Data, Error>) -> Void) {
            requestedURLs.append(url)
            handler(result)
        }
    }

    private let url = URL(string: "https://movies-loader.example.invalid/catalog")!
    private let item = #"{"fullTitle":"Film (2026)","title":"Film","imDbRating":8.2,"image":"https://images.example.invalid/poster.jpg"}"#

    func testSuccessLoading() {
        let networkClient = StubNetworkClient(emulateError: false)
        let loader = MoviesLoader(networkClient: networkClient, url: url)
        let loaded = expectation(description: "Two movies loaded")

        loader.loadMovies { result in
            switch result {
            case .success(let movies):
                XCTAssertEqual(movies.items.count, 2)
                XCTAssertEqual(movies.errorMessage, "")
                XCTAssertEqual(movies.items.map(\.title), ["Prey (2022)", "The Gray Man (2022)"])
                XCTAssertEqual(movies.items.map(\.rating), ["7.2", "6.5"])
            case .failure(let error):
                XCTFail("Unexpected loading error: \(error)")
            }
            loaded.fulfill()
        }

        wait(for: [loaded], timeout: 1)
    }

    func testFailureLoading() {
        let networkClient = StubNetworkClient(emulateError: true)
        let loader = MoviesLoader(networkClient: networkClient, url: url)
        let failed = expectation(description: "Stub error received")

        loader.loadMovies { result in
            switch result {
            case .success:
                XCTFail("Expected stub failure")
            case .failure(let error):
                XCTAssertEqual(error as? StubNetworkClient.TestError, .test)
            }
            failed.fulfill()
        }

        wait(for: [failed], timeout: 1)
    }

    private func load(_ json: String) throws -> Result<MostPopularMovies, Error> {
        let client = NetworkClientStub(result: .success(Data(json.utf8)))
        var result: Result<MostPopularMovies, Error>?
        var calls = 0
        MoviesLoader(networkClient: client, url: url).loadMovies {
            result = $0
            calls += 1
        }
        XCTAssertEqual(client.requestedURLs, [url])
        XCTAssertEqual(calls, 1)
        return try XCTUnwrap(result)
    }

    func testSuccessfulCurrentAPIResponseDecodesMovies() throws {
        let movies = try load("{\"success\":true,\"errorMessage\":null,\"items\":[\(item)]}").get()

        XCTAssertEqual(movies.items.count, 1)
        XCTAssertEqual(movies.items.first?.title, "Film (2026)")
        XCTAssertEqual(movies.items.first?.rating, "8.2")
        XCTAssertEqual(movies.errorMessage, "")
        XCTAssertEqual(movies.success, true)
    }

    func testLegacyResponseWithoutSuccessIsAccepted() throws {
        let movies = try load("{\"errorMessage\":\"\",\"items\":[\(item)]}").get()

        XCTAssertEqual(movies.items.count, 1)
        XCTAssertNil(movies.success)
    }

    func testWhitespaceOnlyErrorMessageDoesNotRejectSuccess() throws {
        let movies = try load("{\"errorMessage\":\"  \\n \",\"items\":[\(item)]}").get()

        XCTAssertEqual(movies.items.count, 1)
    }

    func testMalformedJSONIsRejected() throws {
        guard case .failure(let error) = try load("{ not json") else {
            return XCTFail("Expected decoding error")
        }
        XCTAssertTrue(error is DecodingError)
    }

    func testWrongMovieFieldTypeIsRejected() throws {
        guard case .failure(let error) = try load(#"{"items":[{"title":"Film","imDbRating":true,"image":"https://images.example.invalid/poster.jpg"}]}"#) else {
            return XCTFail("Expected decoding error")
        }
        XCTAssertTrue(error is DecodingError)
    }

    func testAPIErrorIsReturnedEvenWhenHTTPWasSuccessful() throws {
        guard case .failure(let error) = try load(#"{"success":false,"errorMessage":"Daily limit reached","items":null}"#),
              case MoviesLoaderError.serverMessage(let message) = error else {
            return XCTFail("Expected server message")
        }
        XCTAssertEqual(message, "Daily limit reached")
    }

    func testNonEmptyAPIErrorRejectsAnOtherwiseSuccessfulResponse() throws {
        guard case .failure(let error) = try load("{\"success\":true,\"errorMessage\":\"Error\",\"items\":[\(item)]}"),
              case MoviesLoaderError.serverMessage(let message) = error else {
            return XCTFail("Expected server message")
        }
        XCTAssertEqual(message, "Error")
    }

    func testSuccessFalseWithoutMessageIsRejected() throws {
        guard case .failure(let error) = try load("{\"success\":false,\"errorMessage\":null,\"items\":[\(item)]}"),
              case MoviesLoaderError.unsuccessfulResponse = error else {
            return XCTFail("Expected unsuccessful response error")
        }
    }

    func testEmptyMovieArrayIsRejected() throws {
        guard case .failure(let error) = try load(#"{"success":true,"errorMessage":null,"items":[]}"#),
              case MoviesLoaderError.emptyMovies = error else {
            return XCTFail("Expected empty movies error")
        }
    }

    func testMissingMovieArrayIsRejectedAsEmpty() throws {
        guard case .failure(let error) = try load(#"{"success":true}"#),
              case MoviesLoaderError.emptyMovies = error else {
            return XCTFail("Expected empty movies error")
        }
    }

    func testNetworkFailureIsForwardedUnchanged() throws {
        let expected = NSError(domain: "MovieQuiz.NetworkTests", code: 42)
        let client = NetworkClientStub(result: .failure(expected))
        var result: Result<MostPopularMovies, Error>?
        MoviesLoader(networkClient: client, url: url).loadMovies { result = $0 }

        guard case .failure(let error) = try XCTUnwrap(result) else {
            return XCTFail("Expected transport failure")
        }
        XCTAssertTrue(error as NSError === expected)
        XCTAssertEqual(client.requestedURLs, [url])
    }
}

final class MostPopularMoviesTests: XCTestCase {
    private func decodeMovie(_ json: String) throws -> MostPopularMovie {
        try JSONDecoder().decode(MostPopularMovie.self, from: Data(json.utf8))
    }

    func testLegacyStringRatingAndFullTitleAreDecoded() throws {
        let movie = try decodeMovie(#"{"fullTitle":"Legacy (1994)","title":"Legacy","imDbRating":"9.3","image":"https://images.example.invalid/poster.jpg"}"#)

        XCTAssertEqual(movie.title, "Legacy (1994)")
        XCTAssertEqual(movie.rating, "9.3")
        XCTAssertEqual(movie.imageURL.absoluteString, "https://images.example.invalid/poster.jpg")
    }

    func testCurrentNumericRatingAndNullErrorMessageAreDecoded() throws {
        let json = #"{"success":true,"errorMessage":null,"items":[{"imDbId":"tt0111161","fullTitle":"The Shawshank Redemption (1994)","title":"The Shawshank Redemption","imDbRating":9.3,"image":"https://images.example.invalid/poster.jpg"}]}"#
        let movies = try JSONDecoder().decode(MostPopularMovies.self, from: Data(json.utf8))

        XCTAssertEqual(movies.errorMessage, "")
        XCTAssertEqual(movies.success, true)
        XCTAssertEqual(movies.items.first?.rating, "9.3")
        XCTAssertEqual(movies.items.first?.title, "The Shawshank Redemption (1994)")
    }

    func testIntegerRatingIsDecodedAsNumericText() throws {
        let movie = try decodeMovie(#"{"title":"Film","imDbRating":8,"image":"https://images.example.invalid/poster.jpg"}"#)

        XCTAssertEqual(Double(movie.rating), 8)
    }

    func testTitleIsUsedWhenFullTitleIsMissing() throws {
        let movie = try decodeMovie(#"{"title":"Fallback title","imDbRating":"7.5","image":"https://images.example.invalid/poster.jpg"}"#)

        XCTAssertEqual(movie.title, "Fallback title")
    }

    func testTitleIsUsedWhenFullTitleIsNull() throws {
        let movie = try decodeMovie(#"{"fullTitle":null,"title":"Fallback title","imDbRating":7.5,"image":"https://images.example.invalid/poster.jpg"}"#)

        XCTAssertEqual(movie.title, "Fallback title")
    }

    func testMissingErrorAndItemsDefaultToEmptyValues() throws {
        let movies = try JSONDecoder().decode(MostPopularMovies.self, from: Data("{}".utf8))

        XCTAssertEqual(movies.errorMessage, "")
        XCTAssertTrue(movies.items.isEmpty)
        XCTAssertNil(movies.success)
    }

    func testNullItemsDefaultToEmptyArray() throws {
        let movies = try JSONDecoder().decode(MostPopularMovies.self, from: Data(#"{"errorMessage":null,"items":null,"success":false}"#.utf8))

        XCTAssertTrue(movies.items.isEmpty)
        XCTAssertEqual(movies.success, false)
    }

    func testInvalidMovieFieldTypesAreRejected() {
        let invalidMovies = [
            #"{"title":42,"imDbRating":8,"image":"https://images.example.invalid/poster.jpg"}"#,
            #"{"title":"Film","imDbRating":true,"image":"https://images.example.invalid/poster.jpg"}"#,
            #"{"title":"Film","imDbRating":null,"image":"https://images.example.invalid/poster.jpg"}"#,
            #"{"title":"Film","imDbRating":{"value":8},"image":"https://images.example.invalid/poster.jpg"}"#,
            #"{"title":"Film","imDbRating":8,"image":17}"#,
            #"{"imDbRating":8,"image":"https://images.example.invalid/poster.jpg"}"#
        ]

        for json in invalidMovies {
            XCTAssertThrowsError(try decodeMovie(json)) { error in
                XCTAssertTrue(error is DecodingError)
            }
        }
    }

    func testInvalidRootFieldTypesAreRejected() {
        for json in [#"{"items":{}}"#, #"{"errorMessage":42}"#, #"{"success":"true"}"#, #"[]"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(MostPopularMovies.self, from: Data(json.utf8))) { error in
                XCTAssertTrue(error is DecodingError)
            }
        }
    }

    func testModelInitializerAndCodableRoundTripPreserveValues() throws {
        let movie = MostPopularMovie(title: "Film (2026)", rating: "8.4", imageURL: URL(string: "https://images.example.invalid/poster.jpg")!)
        let original = MostPopularMovies(errorMessage: "", items: [movie], success: true)
        let decoded = try JSONDecoder().decode(MostPopularMovies.self, from: JSONEncoder().encode(original))

        XCTAssertEqual(decoded.errorMessage, original.errorMessage)
        XCTAssertEqual(decoded.success, original.success)
        XCTAssertEqual(decoded.items.first?.title, movie.title)
        XCTAssertEqual(decoded.items.first?.rating, movie.rating)
        XCTAssertEqual(decoded.items.first?.imageURL, movie.imageURL)
    }

    func testAmazonImageSuffixIsResized() {
        let movie = MostPopularMovie(title: "Film", rating: "8", imageURL: URL(string: "https://m.media-amazon.com/images/M/poster._V1_w1200_h1800_AL_.jpg")!)

        XCTAssertEqual(movie.resizedImageURL.absoluteString, "https://m.media-amazon.com/images/M/poster._V0_UX600_.jpg")
    }

    func testApexAmazonImageHostIsResized() {
        let movie = MostPopularMovie(title: "Film", rating: "8", imageURL: URL(string: "https://media-amazon.com/images/poster._V1_.jpg")!)

        XCTAssertEqual(movie.resizedImageURL.absoluteString, "https://media-amazon.com/images/poster._V0_UX600_.jpg")
    }

    func testUnrelatedHostsAndImagesWithoutSuffixRemainUnchanged() {
        for string in [
            "https://images.example.invalid/poster._V1_.jpg",
            "https://media-amazon.com.example.invalid/poster._V1_.jpg",
            "https://notmedia-amazon.com/poster._V1_.jpg",
            "https://m.media-amazon.com/images/poster.jpg"
        ] {
            let url = URL(string: string)!
            let movie = MostPopularMovie(title: "Film", rating: "8", imageURL: url)
            XCTAssertEqual(movie.resizedImageURL, url)
        }
    }
}
