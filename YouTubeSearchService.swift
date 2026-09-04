import Foundation

struct YouTubeVideoResult: Identifiable, Codable {
    let id: String
    let title: String
    let channelTitle: String
    let summary: String
    let thumbnailURLString: String

    var videoURL: URL? {
        URL(string: "https://www.youtube.com/watch?v=\(id)")
    }

    var thumbnailURL: URL? {
        URL(string: thumbnailURLString)
    }
}

enum YouTubeSearchError: LocalizedError {
    case missingAPIKey
    case invalidRequest
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Guarda una clave de YouTube Data API en Configuración."
        case .invalidRequest:
            "No fue posible construir la búsqueda de videos."
        case .invalidResponse:
            "YouTube devolvió una respuesta que la app no pudo interpretar."
        case .server(let message):
            message
        }
    }
}

enum YouTubeSearchService {
    static func search(query: String, apiKey: String, limit: Int = 8) async throws -> [YouTubeVideoResult] {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw YouTubeSearchError.missingAPIKey }

        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/search")
        components?.queryItems = [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "type", value: "video"),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "maxResults", value: String(min(max(limit, 1), 20))),
            URLQueryItem(name: "relevanceLanguage", value: "es"),
            URLQueryItem(name: "safeSearch", value: "moderate"),
            URLQueryItem(name: "key", value: trimmedKey)
        ]
        guard let url = components?.url else { throw YouTubeSearchError.invalidRequest }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw YouTubeSearchError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = object["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw YouTubeSearchError.server(message)
            }
            throw YouTubeSearchError.server("YouTube respondió con código \(http.statusCode).")
        }

        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        return decoded.items.compactMap { item in
            guard let videoID = item.id.videoId else { return nil }
            return YouTubeVideoResult(
                id: videoID,
                title: item.snippet.title.decodingHTMLEntities,
                channelTitle: item.snippet.channelTitle.decodingHTMLEntities,
                summary: item.snippet.description.decodingHTMLEntities,
                thumbnailURLString: item.snippet.thumbnails.medium?.url
                    ?? item.snippet.thumbnails.default?.url
                    ?? ""
            )
        }
    }
}

private struct SearchResponse: Decodable {
    let items: [SearchItem]
}

private struct SearchItem: Decodable {
    let id: SearchIdentifier
    let snippet: SearchSnippet
}

private struct SearchIdentifier: Decodable {
    let videoId: String?
}

private struct SearchSnippet: Decodable {
    let title: String
    let channelTitle: String
    let description: String
    let thumbnails: SearchThumbnails
}

private struct SearchThumbnails: Decodable {
    let `default`: SearchThumbnail?
    let medium: SearchThumbnail?
}

private struct SearchThumbnail: Decodable {
    let url: String
}

private extension String {
    var decodingHTMLEntities: String {
        guard let data = data(using: .utf8) else { return self }
        return (try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.html],
            documentAttributes: nil
        ).string) ?? self
    }
}
