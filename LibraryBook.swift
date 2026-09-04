import Foundation
import SwiftData
import PDFKit

@Model
final class LibraryBook {
    @Attribute(.unique) var id: UUID
    var title: String
    var author: String
    var fileName: String
    var bookmarkData: Data
    var pageCount: Int
    var pageTexts: [String]

    init(
        id: UUID = UUID(),
        title: String,
        author: String = "",
        fileName: String,
        bookmarkData: Data,
        pageCount: Int = 0,
        pageTexts: [String] = []
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.fileName = fileName
        self.bookmarkData = bookmarkData
        self.pageCount = pageCount
        self.pageTexts = pageTexts
    }

    /// Busca páginas cuyo texto contenga alguna de las palabras clave dadas (sin distinguir
    /// mayúsculas/tildes), para poder citarle a la IA páginas reales en vez de inventadas.
    func matchingPages(for keywords: [String], maxResults: Int = 2) -> [(page: Int, snippet: String)] {
        let needles = keywords.map { $0.normalizedForSearch }.filter { !$0.isEmpty }
        guard !needles.isEmpty else { return [] }

        var matches: [(Int, String)] = []
        for (index, text) in pageTexts.enumerated() {
            let haystack = text.normalizedForSearch
            if needles.contains(where: { haystack.contains($0) }) {
                let snippet = text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160)
                matches.append((index + 1, String(snippet)))
            }
            if matches.count >= maxResults { break }
        }
        return matches
    }

    static func extractPageTexts(from url: URL) -> [String] {
        guard let document = PDFDocument(url: url) else { return [] }
        return (0..<document.pageCount).map { document.page(at: $0)?.string ?? "" }
    }
}

private extension String {
    var normalizedForSearch: String {
        folding(options: .diacriticInsensitive, locale: .current).lowercased()
    }
}
