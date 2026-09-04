import Foundation
import AppKit

/// Encapsula el manejo de bookmarks con alcance de seguridad para archivos externos
/// (PDFs, Guitar Pro) elegidos por el usuario.
enum SecurityScopedFile {
    static func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    static func resolve(_ data: Data) -> URL? {
        var isStale = false
        return try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale)
    }

    /// Ejecuta `body` con acceso concedido al archivo, liberando el acceso al terminar.
    @discardableResult
    static func withAccess<T>(_ data: Data, _ body: (URL) throws -> T) rethrows -> T? {
        guard let url = resolve(data) else { return nil }
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        return try body(url)
    }

    static func open(_ data: Data) {
        withAccess(data) { url in
            NSWorkspace.shared.open(url)
        }
    }
}
