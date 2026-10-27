import Foundation

protocol NetworkClientProtocol {
    func fetch(url: URL, handler: @escaping (Result<Data, Error>) -> Void)
}

enum NetworkClientError: LocalizedError {
    case invalidResponse
    case httpStatusCode(Int)
    case missingData

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Сервер вернул некорректный ответ."
        case .httpStatusCode(let status):
            return "Ошибка сервера: \(status)."
        case .missingData:
            return "Сервер не вернул данные."
        }
    }
}

struct NetworkClient: NetworkClientProtocol {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetch(url: URL, handler: @escaping (Result<Data, Error>) -> Void) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        let task = session.dataTask(with: request) { data, response, error in
            handler(Self.makeResult(data: data, response: response, error: error))
        }
        task.resume()
    }

    static func makeResult(data: Data?, response: URLResponse?, error: Error?) -> Result<Data, Error> {
        if let error = error {
            return .failure(error)
        }
        guard let response = response as? HTTPURLResponse else {
            return .failure(NetworkClientError.invalidResponse)
        }
        guard (200..<300).contains(response.statusCode) else {
            return .failure(NetworkClientError.httpStatusCode(response.statusCode))
        }
        guard let data = data else {
            return .failure(NetworkClientError.missingData)
        }
        return .success(data)
    }
}
