import Foundation

protocol MoviesLoading {
    func loadMovies(handler: @escaping (Result<MostPopularMovies, Error>) -> Void)
}

enum MoviesLoaderError: LocalizedError {
    case serverMessage(String)
    case unsuccessfulResponse
    case emptyMovies

    var errorDescription: String? {
        switch self {
        case .serverMessage(let message):
            return message
        case .unsuccessfulResponse:
            return "Не удалось получить фильмы с сервера."
        case .emptyMovies:
            return "Сервер вернул пустой список фильмов."
        }
    }
}

struct MoviesLoader: MoviesLoading {
    private let networkClient: NetworkRouting
    private let mostPopularMoviesUrl: URL

    init(
        networkClient: NetworkRouting = NetworkClient(),
        url: URL = URL(string: "https://tv-api.com/api/top-250-movies?apikey=juv0ohccyeycmvbwn4du")!
    ) {
        self.networkClient = networkClient
        mostPopularMoviesUrl = url
    }

    func loadMovies(handler: @escaping (Result<MostPopularMovies, Error>) -> Void) {
        networkClient.fetch(url: mostPopularMoviesUrl) { result in
            do {
                let data = try result.get()
                let movies = try JSONDecoder().decode(MostPopularMovies.self, from: data)
                if !movies.errorMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    throw MoviesLoaderError.serverMessage(movies.errorMessage)
                }
                guard movies.success != false else {
                    throw MoviesLoaderError.unsuccessfulResponse
                }
                guard !movies.items.isEmpty else {
                    throw MoviesLoaderError.emptyMovies
                }
                handler(.success(movies))
            } catch {
                handler(.failure(error))
            }
        }
    }
}
