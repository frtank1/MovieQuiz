import Foundation

struct MostPopularMovies: Codable {
    let errorMessage: String
    let items: [MostPopularMovie]
    let success: Bool?

    init(errorMessage: String, items: [MostPopularMovie], success: Bool? = nil) {
        self.errorMessage = errorMessage
        self.items = items
        self.success = success
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage) ?? ""
        success = try container.decodeIfPresent(Bool.self, forKey: .success)
        items = try container.decodeIfPresent([MostPopularMovie].self, forKey: .items) ?? []
    }
}

struct MostPopularMovie: Codable {
    let title: String
    let rating: String
    let imageURL: URL

    private enum CodingKeys: String, CodingKey {
        case title = "fullTitle"
        case fallbackTitle = "title"
        case rating = "imDbRating"
        case imageURL = "image"
    }

    init(title: String, rating: String, imageURL: URL) {
        self.title = title
        self.rating = rating
        self.imageURL = imageURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
            ?? container.decode(String.self, forKey: .fallbackTitle)
        if let string = try? container.decode(String.self, forKey: .rating) {
            rating = string
        } else {
            rating = String(try container.decode(Double.self, forKey: .rating))
        }
        imageURL = try container.decode(URL.self, forKey: .imageURL)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(rating, forKey: .rating)
        try container.encode(imageURL, forKey: .imageURL)
    }

    var resizedImageURL: URL {
        guard
            let host = imageURL.host?.lowercased(),
            host == "media-amazon.com" || host.hasSuffix(".media-amazon.com"),
            let range = imageURL.absoluteString.range(of: "._")
        else {
            return imageURL
        }
        return URL(string: String(imageURL.absoluteString[..<range.lowerBound]) + "._V0_UX600_.jpg") ?? imageURL
    }
}
