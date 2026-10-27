import UIKit

enum QuestionFactoryError: LocalizedError {
    case noMovies
    case invalidRating
    case invalidPosterURL
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .noMovies:
            return "Не удалось найти фильмы для викторины."
        case .invalidRating:
            return "У фильма указан некорректный рейтинг."
        case .invalidPosterURL:
            return "У фильма указан некорректный адрес постера."
        case .invalidImage:
            return "Не удалось загрузить постер фильма. Попробуйте ещё раз."
        }
    }
}

final class QuestionFactory: QuestionFactoryProtocol {
    private let moviesLoader: MoviesLoading
    private let networkClient: NetworkClientProtocol
    private weak var delegate: QuestionFactoryDelegate?
    private var movies: [MostPopularMovie] = []
    private var loadID: UUID?
    private var questionID: UUID?

    init(
        moviesLoader: MoviesLoading,
        delegate: QuestionFactoryDelegate,
        networkClient: NetworkClientProtocol = NetworkClient()
    ) {
        self.moviesLoader = moviesLoader
        self.delegate = delegate
        self.networkClient = networkClient
    }

    func loadData() {
        precondition(Thread.isMainThread)
        let id = UUID()
        loadID = id
        questionID = nil
        movies = []
        moviesLoader.loadMovies { [weak self] result in
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.loadID == id else { return }
                self.loadID = nil
                switch result {
                case .success(let response):
                    guard !response.items.isEmpty else {
                        self.delegate?.didFailToLoadData(with: QuestionFactoryError.noMovies)
                        return
                    }
                    self.movies = response.items
                    self.delegate?.didLoadDataFromServer()
                case .failure(let error):
                    self.delegate?.didFailToLoadData(with: error)
                }
            }
        }
    }

    func requestNextQuestion() {
        precondition(Thread.isMainThread)
        let id = UUID()
        questionID = id
        guard let movie = movies.randomElement() else {
            questionID = nil
            delegate?.didFailToLoadData(with: QuestionFactoryError.noMovies)
            return
        }
        guard let rating = Float(movie.rating), rating.isFinite, (0...10).contains(rating) else {
            questionID = nil
            delegate?.didFailToLoadData(with: QuestionFactoryError.invalidRating)
            return
        }
        let posterURL = movie.resizedImageURL
        guard
            let scheme = posterURL.scheme?.lowercased(),
            ["https", "http"].contains(scheme),
            posterURL.host != nil
        else {
            questionID = nil
            delegate?.didFailToLoadData(with: QuestionFactoryError.invalidPosterURL)
            return
        }
        networkClient.fetch(url: posterURL) { [weak self] result in
            let questionResult: Result<QuizQuestion, Error> = result.flatMap { data in
                guard UIImage(data: data) != nil else {
                    return .failure(QuestionFactoryError.invalidImage)
                }
                return .success(QuizQuestion(
                    image: data,
                    text: "Рейтинг этого фильма больше, чем 7?",
                    correctAnswer: rating > 7
                ))
            }
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.questionID == id else { return }
                self.questionID = nil
                switch questionResult {
                case .success(let question):
                    self.delegate?.didReceiveNextQuestion(question: question)
                case .failure(let error):
                    self.delegate?.didFailToLoadData(with: error)
                }
            }
        }
    }
}
