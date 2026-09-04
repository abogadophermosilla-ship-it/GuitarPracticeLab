import SwiftUI

/// Búsqueda directa sobre el índice RAG de libros (`Tools/book-rag`), sin pasar por el Profesor
/// IA. Usa el mismo `BookPassageService` que ya consumen `AdvancedTeacherView`/`AIStudioView`,
/// pero muestra los pasajes crudos con su cita en vez de alimentarlos a un modelo.
struct LibraryBookSearchPane: View {
    let searchText: String

    @State private var passages: [BookPassage] = []
    @State private var selectedID: Int?
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var health: BookPassageHealth?

    private let service = BookPassageService()

    var body: some View {
        HStack(spacing: 0) {
            List(passages, selection: $selectedID) { passage in
                LibraryBookPassageRow(passage: passage)
                    .tag(passage.id)
            }
            .frame(minWidth: 260, idealWidth: 340, maxWidth: 420)
            Divider()
            Group {
                if let errorMessage {
                    EmptyStateView(
                        icon: "exclamationmark.triangle",
                        title: "Índice no disponible",
                        message: errorMessage
                    )
                } else if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    EmptyStateView(
                        icon: "text.book.closed.fill",
                        title: "Busca por significado",
                        message: "Escribe una pregunta o técnica, por ejemplo \"cómo suelto la mano derecha en pasajes rápidos\". No hace falta compartir las palabras exactas del libro."
                    )
                } else if isSearching, passages.isEmpty {
                    ProgressView("Buscando en los libros…")
                } else if let passage = passages.first(where: { $0.id == selectedID }) ?? passages.first {
                    LibraryBookPassageDetailView(passage: passage)
                } else {
                    EmptyStateView(
                        icon: "doc.text.magnifyingglass",
                        title: "Sin resultados",
                        message: "Prueba con otras palabras o una pregunta más específica."
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            if let health {
                Text("\(health.books) libros · \(health.chunks) fragmentos · \(health.integrativePieces) piezas/estudios identificados · modelo \(health.embeddingModel)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(.thinMaterial)
            }
        }
        .task(id: searchText) {
            await runSearch()
        }
        .task {
            health = try? await service.health()
        }
    }

    @MainActor
    private func runSearch() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            passages = []
            errorMessage = nil
            isSearching = false
            return
        }

        // La primera pasada es léxica y no necesita Ollama: aparece rápido. Después se reemplaza
        // por la búsqueda híbrida semántica. Esto evita que Biblioteca parezca congelada durante
        // el cálculo del embedding sin sacrificar la calidad final del RAG.
        try? await Task.sleep(nanoseconds: 180_000_000)
        guard !Task.isCancelled else { return }

        isSearching = true
        errorMessage = nil
        var fastResults: [BookPassage] = []
        do {
            fastResults = try await service.search(query: query, mode: .lexical)
            guard !Task.isCancelled else { return }
            passages = fastResults
            if !fastResults.contains(where: { $0.id == selectedID }) {
                selectedID = fastResults.first?.id
            }

            let results = try await service.search(query: query)
            guard !Task.isCancelled else { return }
            passages = results
            if !results.contains(where: { $0.id == selectedID }) {
                selectedID = results.first?.id
            }
        } catch let error as BookPassageError {
            guard !Task.isCancelled else { return }
            // Si Ollama falló después de la pasada rápida, los resultados léxicos siguen siendo
            // válidos y útiles. Solo se muestra error cuando tampoco hubo respuesta rápida.
            if fastResults.isEmpty {
                passages = []
                errorMessage = error.errorDescription
            }
        } catch {
            guard !Task.isCancelled else { return }
            if fastResults.isEmpty {
                passages = []
                errorMessage = error.localizedDescription
            }
        }
        isSearching = false
    }
}

private struct LibraryBookPassageRow: View {
    let passage: BookPassage

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: passage.isOCR ? "doc.text.viewfinder" : "quote.opening")
                .foregroundStyle(passage.isOCR ? .orange : .indigo)
                .frame(width: 34, height: 34)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(passage.primaryContent?.title ?? passage.book)
                    .font(.headline)
                    .lineLimit(1)
                Text(passage.primaryContent == nil ? passage.citation : "\(passage.book) · \(passage.citation)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }
}

private struct LibraryBookPassageDetailView: View {
    let passage: BookPassage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    Image(systemName: passage.isOCR ? "doc.text.viewfinder" : "quote.opening")
                        .font(.largeTitle)
                        .foregroundStyle(passage.isOCR ? .orange : .indigo)
                        .frame(width: 70, height: 82)
                        .background(
                            (passage.isOCR ? Color.orange : Color.indigo).opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                    VStack(alignment: .leading, spacing: 5) {
                        Text(passage.book)
                            .font(.title2.bold())
                        Text(passage.citation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                if passage.isOCR {
                    Label(
                        "Texto obtenido por OCR — puede tener errores de reconocimiento, sobre todo en tablaturas y diagramas.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }

                if !passage.contents.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Ubicación dentro del método")
                            .font(.headline)
                        ForEach(Array(passage.contents.enumerated()), id: \.offset) { _, content in
                            LibraryPassageContentCard(content: content)
                        }
                    }
                }

                Divider()
                Text("Texto fuente")
                    .font(.headline)
                Text(passage.text)
                    .font(.body)
                    .textSelection(.enabled)
            }
            .padding(24)
        }
    }
}

private struct LibraryPassageContentCard: View {
    let content: BookPassageContent

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Label(
                    content.typeLabel,
                    systemImage: content.isIntegrativePiece ? "music.note.list" : "figure.strengthtraining.traditional"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(content.isIntegrativePiece ? .purple : .blue)
                Spacer()
                Text("p. \(content.page)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(content.title)
                .font(.title3.bold())
            Text(content.description)
                .font(.callout)

            let details = [
                content.lesson,
                content.form,
                content.key.map { "Tonalidad \($0)" },
                content.technique.isEmpty ? nil : "Técnica: \(content.technique)"
            ].compactMap { $0 }
            if !details.isEmpty {
                Text(details.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(content.role)
                .font(.caption)

            if !content.prepares.isEmpty {
                Label(
                    "Preparación: " + content.prepares
                        .map { "\($0.title) (p. \($0.page))" }
                        .joined(separator: ", "),
                    systemImage: "arrow.triangle.branch"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            (content.isIntegrativePiece ? Color.purple : Color.blue).opacity(0.07),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }
}
