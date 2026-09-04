import SwiftUI
import PDFKit

/// Muestra el PDF real de un `LibraryBook` dentro de la app, abierto directamente en una página
/// dada — a diferencia de `PDFPageRenderer` (que solo renderiza una página como imagen estática
/// para recortar), esto es un `PDFView` interactivo: se puede hacer scroll, zoom y navegar el resto
/// del libro sin salir de la app.
struct PDFBookViewerSheet: View {
    let book: LibraryBook
    let initialPage: Int

    @Environment(\.dismiss) private var dismiss
    @State private var resolvedURL: URL?
    @State private var accessGranted = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(book.title)
                        .font(.headline)
                    if initialPage > 0 {
                        Text("Página \(initialPage)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Cerrar") { dismiss() }
            }
            .padding()

            Divider()

            if let resolvedURL {
                PDFKitRepresentedView(url: resolvedURL, page: initialPage)
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    if errorMessage.isEmpty {
                        ProgressView()
                    } else {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    Spacer()
                }
            }
        }
        .frame(minWidth: 760, idealWidth: 900, minHeight: 700, idealHeight: 900)
        .onAppear(perform: resolveAccess)
        .onDisappear(perform: releaseAccess)
    }

    private func resolveAccess() {
        guard let url = SecurityScopedFile.resolve(book.bookmarkData) else {
            errorMessage = "No se pudo abrir el PDF. Verifica que el archivo siga disponible en su ubicación original."
            return
        }
        accessGranted = url.startAccessingSecurityScopedResource()
        resolvedURL = url
    }

    private func releaseAccess() {
        guard accessGranted, let resolvedURL else { return }
        resolvedURL.stopAccessingSecurityScopedResource()
    }
}

private struct PDFKitRepresentedView: NSViewRepresentable {
    let url: URL
    let page: Int

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        applyDocument(to: view)
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        guard nsView.document?.documentURL != url else { return }
        applyDocument(to: nsView)
    }

    private func applyDocument(to view: PDFView) {
        guard let document = PDFDocument(url: url) else { return }
        view.document = document
        if page >= 1, let pdfPage = document.page(at: page - 1) {
            view.go(to: pdfPage)
        }
    }
}
