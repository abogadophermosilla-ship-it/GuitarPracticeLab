import Foundation

/// Un pasaje textual recuperado del índice de libros.
struct BookPassage: Identifiable, Hashable, Sendable {
    let id: Int
    let book: String
    let firstPage: Int
    let lastPage: Int
    let isOCR: Bool
    let citation: String
    let text: String
    let contents: [BookPassageContent]

    var primaryContent: BookPassageContent? {
        contents.first(where: \BookPassageContent.isIntegrativePiece) ?? contents.first
    }
}

/// Ficha estructural fusionada durante la ingesta: combina el catálogo curado con señales del
/// texto real (encabezado de partitura, lección, forma y tonalidad).
struct BookPassageContent: Hashable, Sendable {
    let title: String
    let page: Int
    let technique: String
    let difficulty: String
    let description: String
    let type: String
    let role: String
    let lesson: String?
    let form: String?
    let key: String?
    let prepares: [BookPassageContentReference]

    var isIntegrativePiece: Bool { type == "pieza_aplicacion" }
    var typeLabel: String { isIntegrativePiece ? "Pieza / estudio de aplicación" : "Ejercicio preparatorio" }

    var promptSummary: String {
        let details = [lesson, form, key.map { "Tonalidad \($0)" }].compactMap { $0 }
        let preparation = prepares.isEmpty
            ? ""
            : " Preparación relacionada: \(prepares.map { "\($0.title) (p. \($0.page))" }.joined(separator: ", "))."
        return "\(typeLabel): \(title) (p. \(page)). \(description) Técnica: \(technique). \(role)\(details.isEmpty ? "" : " " + details.joined(separator: " · ") + ".")\(preparation)"
    }
}

struct BookPassageContentReference: Hashable, Sendable {
    let title: String
    let page: Int
}

struct BookPassageHealth: Sendable {
    let chunks: Int
    let vectors: Int
    let books: Int
    let embeddingModel: String
    let lastIngest: String?
    let catalogItems: Int
    let integrativePieces: Int
}

enum BookSearchMode: String, Sendable {
    case hybrid = "hibrido"
    case vector = "vectorial"
    case lexical = "lexico"
}

enum BookPassageError: LocalizedError {
    case serviceUnreachable(String)
    case engineUnavailable(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .serviceUnreachable(let reason):
            "No se pudo conectar con el índice de libros (\(reason)). Verifica que el servicio book-rag esté corriendo."
        case .engineUnavailable(let reason):
            "El índice de libros está disponible pero Ollama no responde (\(reason)); sin él no se puede convertir la pregunta en vector."
        case .invalidResponse:
            "El índice de libros devolvió una respuesta que no pudo interpretarse."
        }
    }
}

/// Cliente del servicio local `book-rag` (Tools/book-rag), que indexa el texto COMPLETO de los 19
/// libros de método en `/Volumes/VST/Clases/Libros`.
///
/// Por qué existe además de `LibraryBook.matchingPages`: ese método hace coincidencia de subcadena
/// y devuelve los primeros 160 caracteres de la página que coincidió, no el fragmento que coincidió
/// — en los libros traducidos de Stetina eso significaba devolver el crédito del traductor en vez
/// del contenido. Además solo ve los PDF ya cargados en memoria y no entiende una pregunta que no
/// comparta literalmente las palabras del libro.
///
/// Este servicio recupera por significado y por término exacto a la vez (fusión RRF), sobre texto
/// ya limpiado de encabezados repetidos y duplicaciones del extractor de PDF, y devuelve el pasaje
/// real con su rango de páginas para citar.
///
/// **Degradación:** si el servicio o el motor de embeddings no están, los llamadores deben tratar
/// el error como "sin pasajes" y seguir. El Profesor IA tiene que funcionar igual que antes cuando
/// el índice no está disponible, nunca romperse por su ausencia.
struct BookPassageService: Sendable {
    static let defaultHost = "http://127.0.0.1:8643"

    /// Cuántos pasajes se piden por consulta. Cada uno ronda los 2.400 caracteres, así que 4 es el
    /// punto donde todavía entra cómodo junto al resto del contexto personal (nivel, habilidades,
    /// clases, sesiones) en los 16.384 tokens que reserva `LocalGatewayService`.
    static let defaultResultCount = 4

    /// Recorte por pasaje al armar el prompt. El texto completo se conserva en `BookPassage.text`
    /// para mostrarlo en pantalla; esto solo acota lo que viaja al modelo.
    static let promptCharacterLimit = 1500

    var host: String = BookPassageService.defaultHost

    private var baseURL: URL? { URL(string: host) }

    func search(
        query: String,
        count: Int = BookPassageService.defaultResultCount,
        book: String? = nil,
        mode: BookSearchMode = .hybrid
    ) async throws -> [BookPassage] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let baseURL else { return [] }

        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("search"),
            resolvingAgainstBaseURL: false
        ) else { return [] }

        var items = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "k", value: String(count)),
            URLQueryItem(name: "modo", value: mode.rawValue)
        ]
        if let book, !book.isEmpty {
            items.append(URLQueryItem(name: "libro", value: book))
        }
        components.queryItems = items

        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw BookPassageError.serviceUnreachable(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let detail = (try? JSONDecoder().decode(ErrorPayload.self, from: data))?.error
                ?? "HTTP \(http.statusCode)"
            // 503 es específicamente "el servicio está, Ollama no": conviene distinguirlo para no
            // mandar al usuario a revisar el servicio equivocado.
            throw http.statusCode == 503
                ? BookPassageError.engineUnavailable(detail)
                : BookPassageError.serviceUnreachable(detail)
        }

        guard let payload = try? JSONDecoder().decode(SearchPayload.self, from: data) else {
            throw BookPassageError.invalidResponse
        }

        return payload.resultados.map {
            BookPassage(
                id: $0.id,
                book: $0.libro,
                firstPage: $0.pagina_inicio,
                lastPage: $0.pagina_fin,
                isOCR: $0.es_ocr,
                citation: $0.cita,
                text: $0.texto,
                contents: ($0.contenidos ?? []).map {
                    BookPassageContent(
                        title: $0.titulo,
                        page: $0.pagina,
                        technique: $0.tecnica,
                        difficulty: $0.dificultad,
                        description: $0.descripcion,
                        type: $0.tipo,
                        role: $0.rol,
                        lesson: $0.leccion,
                        form: $0.forma,
                        key: $0.tonalidad,
                        prepares: $0.prepara.map {
                            BookPassageContentReference(title: $0.titulo, page: $0.pagina)
                        }
                    )
                }
            )
        }
    }

    /// Búsqueda que nunca lanza: devuelve `[]` ante cualquier fallo.
    /// Es la que deben usar las rutas que arman contexto para el modelo.
    func searchQuietly(
        query: String,
        count: Int = BookPassageService.defaultResultCount
    ) async -> [BookPassage] {
        (try? await search(query: query, count: count)) ?? []
    }

    func health() async throws -> BookPassageHealth {
        guard let baseURL else { throw BookPassageError.invalidResponse }
        var request = URLRequest(url: baseURL.appendingPathComponent("health"))
        request.timeoutInterval = 10

        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch {
            throw BookPassageError.serviceUnreachable(error.localizedDescription)
        }

        guard let payload = try? JSONDecoder().decode(HealthPayload.self, from: data) else {
            throw BookPassageError.invalidResponse
        }

        return BookPassageHealth(
            chunks: payload.chunks,
            vectors: payload.vectores,
            books: payload.libros,
            embeddingModel: payload.modelo_embedding,
            lastIngest: payload.ultima_ingesta,
            catalogItems: payload.items_catalogo ?? 0,
            integrativePieces: payload.piezas_aplicacion ?? 0
        )
    }
}

// MARK: - Payloads

private struct ErrorPayload: Decodable {
    let error: String
}

private struct SearchPayload: Decodable {
    let resultados: [Resultado]

    struct Resultado: Decodable {
        let id: Int
        let libro: String
        let pagina_inicio: Int
        let pagina_fin: Int
        let es_ocr: Bool
        let cita: String
        let texto: String
        let contenidos: [Contenido]?

        struct Contenido: Decodable {
            let titulo: String
            let pagina: Int
            let tecnica: String
            let dificultad: String
            let descripcion: String
            let tipo: String
            let rol: String
            let leccion: String?
            let forma: String?
            let tonalidad: String?
            let prepara: [Referencia]

            struct Referencia: Decodable {
                let titulo: String
                let pagina: Int
            }
        }
    }
}

private struct HealthPayload: Decodable {
    let chunks: Int
    let vectores: Int
    let libros: Int
    let modelo_embedding: String
    let ultima_ingesta: String?
    let items_catalogo: Int?
    let piezas_aplicacion: Int?
}
