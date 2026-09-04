import AppKit
import PDFKit

enum PDFPageRenderer {
    /// Renderiza una página real del PDF con una resolución suficiente para leer diagramas y
    /// pentagramas. El número de página es el que ve el usuario (empieza en 1).
    static func render(book: LibraryBook, pageNumber: Int, maxDimension: CGFloat = 2200) -> NSImage? {
        guard pageNumber >= 1, pageNumber <= book.pageCount else { return nil }
        return SecurityScopedFile.withAccess(book.bookmarkData) { url in
            guard let document = PDFDocument(url: url),
                  let page = document.page(at: pageNumber - 1) else { return nil }
            let bounds = page.bounds(for: .cropBox)
            guard bounds.width > 0, bounds.height > 0 else { return nil }
            let scale = maxDimension / max(bounds.width, bounds.height)
            return page.thumbnail(
                of: CGSize(width: bounds.width * scale, height: bounds.height * scale),
                for: .cropBox
            )
        } ?? nil
    }

    /// Recorta usando un rectángulo normalizado (0...1) medido sobre la imagen mostrada. AppKit
    /// tiene el origen abajo-izquierda; SwiftUI lo tiene arriba-izquierda, por eso se invierte Y.
    static func crop(_ image: NSImage, normalizedRect: CGRect) -> Data? {
        let bounds = CGRect(origin: .zero, size: image.size)
        let sourceRect = CGRect(
            x: normalizedRect.minX * bounds.width,
            y: (1 - normalizedRect.maxY) * bounds.height,
            width: normalizedRect.width * bounds.width,
            height: normalizedRect.height * bounds.height
        ).intersection(bounds)
        guard sourceRect.width >= 8, sourceRect.height >= 8 else { return nil }

        let output = NSImage(size: sourceRect.size)
        output.lockFocus()
        image.draw(
            in: CGRect(origin: .zero, size: sourceRect.size),
            from: sourceRect,
            operation: .copy,
            fraction: 1
        )
        output.unlockFocus()
        guard let data = output.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}
