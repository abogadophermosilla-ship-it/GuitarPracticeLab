import Foundation
import SwiftData

enum SongGuitarRole: String, CaseIterable, Codable, Identifiable {
    case fullArrangement = "Arreglo completo"
    case rhythm = "Guitarra rítmica"
    case lead = "Guitarra líder"

    var id: String { rawValue }
}

enum SongDifficultySource: String, Codable {
    case curatedCatalog
    case evolvingCatalog
    case gemini
    case localAI
    case artistProfile
    case legacyHeuristic
    case manual

    var displayName: String {
        switch self {
        case .curatedCatalog: "Catálogo verificado"
        case .evolvingCatalog: "Catálogo aprendido"
        case .gemini: "Gemini pagado"
        case .localAI: "IA local"
        case .artistProfile: "Perfil del artista"
        case .legacyHeuristic: "Estimación provisional"
        case .manual: "Confirmada manualmente"
        }
    }

    var isCatalogWorthy: Bool {
        switch self {
        case .curatedCatalog, .evolvingCatalog, .gemini, .localAI, .manual: true
        case .artistProfile, .legacyHeuristic: false
        }
    }
}

enum SongDifficultyConfidence: String, Codable {
    case high
    case medium
    case low

    var displayName: String {
        switch self {
        case .high: "Confianza alta"
        case .medium: "Confianza media"
        case .low: "Confianza baja"
        }
    }
}

struct SongDifficultyDimensions: Codable, Equatable {
    let technique: Double
    let speed: Double
    let rhythm: Double
    let endurance: Double
    let solo: Double
    let form: Double

    init(technique: Double, speed: Double, rhythm: Double, endurance: Double, solo: Double, form: Double) {
        self.technique = Self.clamped(technique)
        self.speed = Self.clamped(speed)
        self.rhythm = Self.clamped(rhythm)
        self.endurance = Self.clamped(endurance)
        self.solo = Self.clamped(solo)
        self.form = Self.clamped(form)
    }

    /// La IA describe dimensiones observables; la nota final se calcula acá para que el modelo no
    /// pueda inventar una cifra sin relación con su propio análisis.
    var weightedRating: DifficultyRating {
        DifficultyRating(stars:
            technique * 0.25 +
            speed * 0.15 +
            rhythm * 0.20 +
            endurance * 0.10 +
            solo * 0.20 +
            form * 0.10
        )
    }

    var labeledValues: [(String, Double)] {
        [
            ("Técnica", technique), ("Velocidad", speed), ("Ritmo", rhythm),
            ("Resistencia", endurance), ("Solo/lead", solo), ("Forma completa", form)
        ]
    }

    private static func clamped(_ value: Double) -> Double { min(max(value, 0.5), 10) }
}

struct SongDifficultyProfile: Equatable {
    static let currentAnalysisVersion = 1

    let title: String
    let artist: String
    let role: SongGuitarRole
    let rating: DifficultyRating
    let dimensions: SongDifficultyDimensions
    let source: SongDifficultySource
    let confidence: SongDifficultyConfidence
    let summary: String
    let factors: [String]
    let demands: [String]
    let prerequisites: [String]
    let practiceFocus: String
    let suggestedSections: [String]
    let analyzedAt: Date
    let analysisVersion: Int

    var catalogKey: String { SongDifficultyIdentity.key(title: title, artist: artist, role: role) }
    var hasObjectiveDimensions: Bool {
        factors.contains { $0.localizedCaseInsensitiveContains("fórmula fija:") }
    }
    var assessment: DifficultyAssessment {
        DifficultyAssessment(
            rating: rating,
            factors: factors,
            summary: summary,
            demands: demands,
            prerequisites: prerequisites,
            practiceFocus: practiceFocus
        )
    }

    func reusedFromCatalog() -> SongDifficultyProfile {
        replacing(source: .evolvingCatalog, factors: factors + ["ficha reutilizada del catálogo evolutivo local"])
    }

    func manuallyAdjusted(to stars: Double) -> SongDifficultyProfile {
        replacing(
            rating: DifficultyRating(stars: stars), source: .manual, confidence: .high,
            factors: factors + ["nota final confirmada manualmente"]
        )
    }

    private func replacing(
        rating: DifficultyRating? = nil,
        source: SongDifficultySource? = nil,
        confidence: SongDifficultyConfidence? = nil,
        factors: [String]? = nil
    ) -> SongDifficultyProfile {
        SongDifficultyProfile(
            title: title, artist: artist, role: role, rating: rating ?? self.rating,
            dimensions: dimensions, source: source ?? self.source,
            confidence: confidence ?? self.confidence, summary: summary,
            factors: factors ?? self.factors, demands: demands, prerequisites: prerequisites,
            practiceFocus: practiceFocus, suggestedSections: suggestedSections,
            analyzedAt: .now, analysisVersion: Self.currentAnalysisVersion
        )
    }
}

enum SongDifficultyIdentity {
    static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .joined(separator: " ")
    }

    static func key(title: String, artist: String, role: SongGuitarRole) -> String {
        "\(normalized(artist))|\(normalized(title))|\(role.rawValue)"
    }
}

/// Fichas reutilizables que no dependen de que la canción siga en Repertorio. Analizar una canción o
/// una banda una vez amplía este catálogo para las altas siguientes.
@Model
final class SongDifficultyRecord {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var catalogKey: String
    var title: String
    var artist: String
    var roleRaw: String
    var stars: Double
    var sourceRaw: String
    var confidenceRaw: String
    var summary: String
    var factors: [String]
    var demands: [String]
    var prerequisites: [String]
    var practiceFocus: String
    var suggestedSections: [String]
    var technique: Double
    var speed: Double
    var rhythm: Double
    var endurance: Double
    var solo: Double
    var form: Double
    var analyzedAt: Date
    var analysisVersion: Int

    init(id: UUID = UUID(), profile: SongDifficultyProfile) {
        self.id = id
        catalogKey = profile.catalogKey
        title = profile.title
        artist = profile.artist
        roleRaw = profile.role.rawValue
        stars = profile.rating.stars
        sourceRaw = profile.source.rawValue
        confidenceRaw = profile.confidence.rawValue
        summary = profile.summary
        factors = profile.factors
        demands = profile.demands
        prerequisites = profile.prerequisites
        practiceFocus = profile.practiceFocus
        suggestedSections = profile.suggestedSections
        technique = profile.dimensions.technique
        speed = profile.dimensions.speed
        rhythm = profile.dimensions.rhythm
        endurance = profile.dimensions.endurance
        solo = profile.dimensions.solo
        form = profile.dimensions.form
        analyzedAt = profile.analyzedAt
        analysisVersion = profile.analysisVersion
    }

    var profile: SongDifficultyProfile {
        SongDifficultyProfile(
            title: title, artist: artist,
            role: SongGuitarRole(rawValue: roleRaw) ?? .fullArrangement,
            rating: DifficultyRating(stars: stars),
            dimensions: SongDifficultyDimensions(
                technique: technique, speed: speed, rhythm: rhythm,
                endurance: endurance, solo: solo, form: form
            ),
            source: SongDifficultySource(rawValue: sourceRaw) ?? .evolvingCatalog,
            confidence: SongDifficultyConfidence(rawValue: confidenceRaw) ?? .medium,
            summary: summary, factors: factors, demands: demands,
            prerequisites: prerequisites, practiceFocus: practiceFocus,
            suggestedSections: suggestedSections, analyzedAt: analyzedAt,
            analysisVersion: analysisVersion
        )
    }

    func update(with profile: SongDifficultyProfile) {
        catalogKey = profile.catalogKey
        title = profile.title
        artist = profile.artist
        roleRaw = profile.role.rawValue
        stars = profile.rating.stars
        sourceRaw = profile.source.rawValue
        confidenceRaw = profile.confidence.rawValue
        summary = profile.summary
        factors = profile.factors
        demands = profile.demands
        prerequisites = profile.prerequisites
        practiceFocus = profile.practiceFocus
        suggestedSections = profile.suggestedSections
        technique = profile.dimensions.technique
        speed = profile.dimensions.speed
        rhythm = profile.dimensions.rhythm
        endurance = profile.dimensions.endurance
        solo = profile.dimensions.solo
        form = profile.dimensions.form
        analyzedAt = profile.analyzedAt
        analysisVersion = profile.analysisVersion
    }
}

enum SongDifficultyStore {
    static func upsert(
        _ profile: SongDifficultyProfile,
        records: [SongDifficultyRecord],
        in context: ModelContext
    ) {
        guard profile.source.isCatalogWorthy else { return }
        guard profile.confidence != .low || profile.source == .manual || profile.source == .curatedCatalog else { return }
        if let existing = records.first(where: { $0.catalogKey == profile.catalogKey }) {
            // Reutilizar una ficha no debe borrar si originalmente vino de Gemini, IA local o del
            // catálogo verificado. Solo una evaluación nueva o corrección manual la reemplaza.
            guard profile.source != .evolvingCatalog else { return }
            existing.update(with: profile)
        } else {
            context.insert(SongDifficultyRecord(profile: profile))
        }
    }
}

/// Clasificación de repertorio en la misma escala de 10 estrellas que la Biblioteca.
///
/// Una canción no se mide como un ejercicio: no importa solo el pasaje más difícil, sino poder
/// sostener la pieza entera —riff, base, solo y arreglo— a tempo de disco. Por eso la nota es del
/// tema completo. "Paranoid" tiene un solo rápido, pero el 90% del tema son dos riffs en E menor:
/// 4★. "Fear of the Dark" no tiene un pasaje imposible, pero son ocho minutos de galope, armonías a
/// dos guitarras y un solo largo: 7★.
///
/// El orden de resolución es: canción conocida → línea base del artista → señales del propio registro
/// (secciones y notas del usuario) → 4★ por defecto. Cualquier valor se puede corregir a mano desde
/// la ficha de la canción, y esa corrección manda.
enum SongDifficultyCatalog {

    struct Entry {
        let artist: String
        let title: String
        let stars: Double
        let summary: String?
        let prerequisites: String?
        let practice: String?

        init(
            artist: String,
            title: String,
            stars: Double,
            summary: String? = nil,
            prerequisites: String? = nil,
            practice: String? = nil
        ) {
            self.artist = artist
            self.title = title
            self.stars = stars
            self.summary = summary
            self.prerequisites = prerequisites
            self.practice = practice
        }
    }

    /// Temas con nota propia. Se prioriza el repertorio de rock, metal y blues, que es de donde sale
    /// la mayor parte de lo que se estudia con estos métodos.
    static let songs: [Entry] = [
        // Iron Maiden
        .init(artist: "Iron Maiden", title: "Wrathchild", stars: 4.5),
        .init(artist: "Iron Maiden", title: "Sanctuary", stars: 5.0),
        .init(artist: "Iron Maiden", title: "Iron Maiden", stars: 5.5),
        .init(artist: "Iron Maiden", title: "Wasted Years", stars: 5.5),
        .init(artist: "Iron Maiden", title: "Run to the Hills", stars: 6.0),
        .init(artist: "Iron Maiden", title: "2 Minutes to Midnight", stars: 6.0),
        .init(artist: "Iron Maiden", title: "The Trooper", stars: 6.0),
        .init(artist: "Iron Maiden", title: "The Number of the Beast", stars: 6.5),
        .init(
            artist: "Iron Maiden", title: "Fear of the Dark", stars: 7.0,
            summary: "Tema largo que combina introducción limpia, cambios dinámicos, melodías armonizadas, galope sostenido y un solo extenso; la dificultad está en mantener precisión y energía durante toda la forma.",
            prerequisites: "Galope relajado, cambios limpio/distorsión controlados, bends afinados y orientación en varias posiciones.",
            practice: "Divide la forma en bloques y ensaya aparte los enlaces; trabaja el galope en ráfagas antes de intentar una pasada completa."
        ),
        .init(artist: "Iron Maiden", title: "Aces High", stars: 7.5),
        .init(artist: "Iron Maiden", title: "Hallowed Be Thy Name", stars: 7.5),
        .init(artist: "Iron Maiden", title: "Powerslave", stars: 7.5),
        .init(artist: "Iron Maiden", title: "Phantom of the Opera", stars: 8.0),

        // Metallica
        .init(artist: "Metallica", title: "Nothing Else Matters", stars: 4.0),
        .init(artist: "Metallica", title: "For Whom the Bell Tolls", stars: 4.0),
        .init(artist: "Metallica", title: "Sad but True", stars: 4.0),
        .init(
            artist: "Metallica", title: "Enter Sandman", stars: 4.5,
            summary: "El riff principal es accesible, pero tocar el tema completo pide palm mute consistente, silencios limpios, cambios de textura y un solo con bends y articulación precisa.",
            prerequisites: "Power chords, palm mute estable y bends de un tono afinados.",
            practice: "Graba primero el riff contra metrónomo para comprobar silencios; estudia el solo por frases y compara cada bend con su nota objetivo."
        ),
        .init(artist: "Metallica", title: "The Unforgiven", stars: 4.5),
        .init(artist: "Metallica", title: "Seek & Destroy", stars: 4.5),
        .init(artist: "Metallica", title: "Creeping Death", stars: 5.5),
        .init(artist: "Metallica", title: "Fade to Black", stars: 6.0),
        .init(artist: "Metallica", title: "Whiplash", stars: 6.5),
        .init(artist: "Metallica", title: "One", stars: 7.0),
        .init(artist: "Metallica", title: "Master of Puppets", stars: 7.5),
        .init(artist: "Metallica", title: "Battery", stars: 7.5),
        .init(artist: "Metallica", title: "Blackened", stars: 8.0),

        // Black Sabbath
        .init(artist: "Black Sabbath", title: "Iron Man", stars: 3.0),
        .init(artist: "Black Sabbath", title: "Sweet Leaf", stars: 3.5),
        .init(
            artist: "Black Sabbath", title: "Paranoid", stars: 4.0,
            summary: "La base usa pocas formas, pero exige corcheas continuas, entradas compactas y groove estable; el solo añade fraseo pentatónico rápido, ligados y bends.",
            prerequisites: "Power chords limpios, corcheas estables y pentatónica menor en una posición.",
            practice: "Consolida primero una pasada completa de la rítmica sin acelerar; después estudia el solo en fragmentos de uno o dos compases."
        ),
        .init(artist: "Black Sabbath", title: "War Pigs", stars: 4.5),
        .init(artist: "Black Sabbath", title: "N.I.B.", stars: 4.5),
        .init(artist: "Black Sabbath", title: "Children of the Grave", stars: 4.5),
        .init(artist: "Black Sabbath", title: "Symptom of the Universe", stars: 5.0),

        // Guns N' Roses
        .init(artist: "Guns N' Roses", title: "Don't Cry", stars: 4.5),
        .init(artist: "Guns N' Roses", title: "Nightrain", stars: 5.0),
        .init(artist: "Guns N' Roses", title: "Welcome to the Jungle", stars: 5.5),
        .init(artist: "Guns N' Roses", title: "Paradise City", stars: 5.5),
        .init(artist: "Guns N' Roses", title: "November Rain", stars: 6.0),
        .init(
            artist: "Guns N' Roses", title: "Sweet Child O' Mine", stars: 6.5,
            summary: "La introducción cruza cuerdas con un patrón continuo y expone cualquier ruido; el tema suma acompañamiento con cambios de posición y un solo largo donde bends, vibrato y fraseo deben conservar afinación.",
            prerequisites: "Púa alterna con saltos de cuerda, muting de ambas manos y bends con vibrato controlado.",
            practice: "Practica la introducción por pares de cuerdas y el solo por puntos de llegada; no unas secciones hasta que los bends queden afinados."
        ),

        // AC/DC
        .init(artist: "AC/DC", title: "Back in Black", stars: 3.5),
        .init(artist: "AC/DC", title: "Highway to Hell", stars: 3.5),
        .init(artist: "AC/DC", title: "You Shook Me All Night Long", stars: 4.0),
        .init(artist: "AC/DC", title: "Whole Lotta Rosie", stars: 4.5),
        .init(artist: "AC/DC", title: "Thunderstruck", stars: 6.0),

        // Deep Purple / Rainbow
        .init(artist: "Deep Purple", title: "Smoke on the Water", stars: 2.5),
        .init(artist: "Deep Purple", title: "Child in Time", stars: 6.5),
        .init(artist: "Deep Purple", title: "Burn", stars: 7.0),
        .init(artist: "Deep Purple", title: "Highway Star", stars: 7.0),
        .init(artist: "Rainbow", title: "Man on the Silver Mountain", stars: 5.5),

        // Led Zeppelin
        .init(artist: "Led Zeppelin", title: "Kashmir", stars: 3.5),
        .init(artist: "Led Zeppelin", title: "Whole Lotta Love", stars: 4.0),
        .init(artist: "Led Zeppelin", title: "Rock and Roll", stars: 4.5),
        .init(artist: "Led Zeppelin", title: "Black Dog", stars: 5.0),
        .init(artist: "Led Zeppelin", title: "Heartbreaker", stars: 5.5),
        .init(artist: "Led Zeppelin", title: "Stairway to Heaven", stars: 5.5),

        // UFO / Scorpions / Judas Priest
        .init(artist: "UFO", title: "Lights Out", stars: 5.5),
        .init(
            artist: "UFO", title: "Doctor Doctor", stars: 6.0,
            summary: "La introducción arpegiada necesita limpieza y continuidad; la parte eléctrica combina base sólida con melodías y solo de legato, bends y vibrato al estilo de Michael Schenker.",
            prerequisites: "Arpegios limpios, cambios de posición, legato parejo y bends afinados.",
            practice: "Trabaja la introducción dejando sonar solo las voces previstas y estudia las melodías cantándolas antes de tocarlas."
        ),
        .init(artist: "UFO", title: "Rock Bottom", stars: 6.5),
        .init(artist: "Scorpions", title: "Rock You Like a Hurricane", stars: 4.5),
        .init(artist: "Scorpions", title: "Still Loving You", stars: 5.5),
        .init(artist: "Judas Priest", title: "Breaking the Law", stars: 3.5),
        .init(artist: "Judas Priest", title: "Living After Midnight", stars: 3.5),
        .init(artist: "Judas Priest", title: "Electric Eye", stars: 6.0),
        .init(artist: "Judas Priest", title: "Painkiller", stars: 8.5),

        // Aerosmith
        .init(artist: "Aerosmith", title: "Dream On", stars: 4.0),
        .init(artist: "Aerosmith", title: "Sweet Emotion", stars: 4.0),
        .init(
            artist: "Aerosmith", title: "Eat the Rich", stars: 5.0,
            summary: "Riff de rock con síncopa, acentos y muting que depende más del pocket que de muchas notas; los fills y el solo añaden articulación blues-rock y cambios rápidos de registro.",
            prerequisites: "Semicorcheas con acentos, muting limpio y fraseo pentatónico con bends.",
            practice: "Toca el riff primero sobre una cuerda apagada para fijar acentos y silencios; reincorpora las alturas sin perder el groove."
        ),
        .init(artist: "Aerosmith", title: "Walk This Way", stars: 5.0),

        // Ozzy / Van Halen
        .init(artist: "Ozzy Osbourne", title: "Crazy Train", stars: 6.5),
        .init(artist: "Ozzy Osbourne", title: "Mr. Crowley", stars: 7.0),
        .init(artist: "Ozzy Osbourne", title: "Over the Mountain", stars: 7.5),
        .init(artist: "Van Halen", title: "Ain't Talkin' 'Bout Love", stars: 3.5),
        .init(artist: "Van Halen", title: "Jump", stars: 4.0),
        .init(artist: "Van Halen", title: "Panama", stars: 6.0),
        .init(artist: "Van Halen", title: "Hot for Teacher", stars: 8.5),
        .init(artist: "Van Halen", title: "Eruption", stars: 9.5),

        // Thrash y metal moderno
        .init(artist: "Pantera", title: "Walk", stars: 4.5),
        .init(artist: "Pantera", title: "Cemetery Gates", stars: 6.5),
        .init(artist: "Pantera", title: "Cowboys from Hell", stars: 7.0),
        .init(artist: "Megadeth", title: "Symphony of Destruction", stars: 4.5),
        .init(artist: "Megadeth", title: "Hangar 18", stars: 8.5),
        .init(artist: "Megadeth", title: "Holy Wars", stars: 8.5),
        .init(artist: "Megadeth", title: "Tornado of Souls", stars: 9.0),
        .init(artist: "Slayer", title: "South of Heaven", stars: 5.5),
        .init(artist: "Slayer", title: "Raining Blood", stars: 6.5),
        .init(artist: "Slayer", title: "Angel of Death", stars: 8.0),
        .init(artist: "System of a Down", title: "Chop Suey!", stars: 4.5),
        .init(artist: "Rammstein", title: "Du Hast", stars: 2.5),

        // Punk y rock alternativo
        .init(artist: "Ramones", title: "Blitzkrieg Bop", stars: 2.0),
        .init(artist: "Ramones", title: "I Wanna Be Sedated", stars: 2.0),
        .init(artist: "Nirvana", title: "About a Girl", stars: 2.5),
        .init(artist: "Nirvana", title: "Come as You Are", stars: 2.5),
        .init(artist: "Nirvana", title: "Smells Like Teen Spirit", stars: 2.5),
        .init(artist: "Nirvana", title: "Lithium", stars: 3.0),
        .init(artist: "Green Day", title: "Good Riddance", stars: 2.5),
        .init(artist: "Green Day", title: "Basket Case", stars: 3.0),
        .init(artist: "Green Day", title: "American Idiot", stars: 3.0),
        .init(artist: "The Offspring", title: "Self Esteem", stars: 3.0),
        .init(artist: "The White Stripes", title: "Seven Nation Army", stars: 1.5),
        .init(artist: "Oasis", title: "Wonderwall", stars: 2.5),
        .init(artist: "The Cranberries", title: "Zombie", stars: 2.5),
        .init(artist: "Red Hot Chili Peppers", title: "Californication", stars: 3.5),
        .init(artist: "Red Hot Chili Peppers", title: "Under the Bridge", stars: 4.5),
        .init(artist: "Red Hot Chili Peppers", title: "Can't Stop", stars: 5.5),
        .init(artist: "Red Hot Chili Peppers", title: "Snow", stars: 6.5),

        // Blues y clásicos
        .init(artist: "Cream", title: "Sunshine of Your Love", stars: 3.5),
        .init(artist: "Cream", title: "Crossroads", stars: 6.5),
        .init(artist: "Eric Clapton", title: "Wonderful Tonight", stars: 3.5),
        .init(artist: "Eric Clapton", title: "Layla", stars: 6.0),
        .init(artist: "Eric Clapton", title: "Tears in Heaven", stars: 6.0),
        .init(artist: "B.B. King", title: "The Thrill Is Gone", stars: 4.5),
        .init(artist: "Jimi Hendrix", title: "Hey Joe", stars: 4.0),
        .init(artist: "Jimi Hendrix", title: "Purple Haze", stars: 5.0),
        .init(artist: "Jimi Hendrix", title: "All Along the Watchtower", stars: 6.0),
        .init(artist: "Jimi Hendrix", title: "Little Wing", stars: 6.5),
        .init(artist: "Jimi Hendrix", title: "Voodoo Child", stars: 7.0),
        .init(artist: "Stevie Ray Vaughan", title: "Pride and Joy", stars: 6.5),
        .init(artist: "Stevie Ray Vaughan", title: "Texas Flood", stars: 7.0),
        .init(artist: "Stevie Ray Vaughan", title: "Scuttle Buttin'", stars: 8.5),

        // Rock clásico varios
        .init(artist: "Pink Floyd", title: "Wish You Were Here", stars: 3.5),
        .init(artist: "Pink Floyd", title: "Another Brick in the Wall", stars: 4.0),
        .init(artist: "Pink Floyd", title: "Money", stars: 5.0),
        .init(artist: "Pink Floyd", title: "Shine On You Crazy Diamond", stars: 5.0),
        .init(artist: "Pink Floyd", title: "Comfortably Numb", stars: 5.5),
        .init(artist: "The Beatles", title: "Come Together", stars: 3.0),
        .init(artist: "The Beatles", title: "Day Tripper", stars: 3.0),
        .init(artist: "The Beatles", title: "Here Comes the Sun", stars: 4.0),
        .init(artist: "The Beatles", title: "Blackbird", stars: 4.5),
        .init(artist: "The Beatles", title: "While My Guitar Gently Weeps", stars: 5.0),
        .init(artist: "Queen", title: "We Will Rock You", stars: 2.0),
        .init(artist: "Queen", title: "Crazy Little Thing Called Love", stars: 3.0),
        .init(artist: "Queen", title: "Killer Queen", stars: 5.5),
        .init(artist: "Queen", title: "Bohemian Rhapsody", stars: 6.0),
        .init(artist: "The Rolling Stones", title: "Satisfaction", stars: 2.5),
        .init(artist: "The Rolling Stones", title: "Paint It Black", stars: 3.0),
        .init(artist: "The Rolling Stones", title: "Start Me Up", stars: 3.5),
        .init(artist: "Lynyrd Skynyrd", title: "Sweet Home Alabama", stars: 4.5),
        .init(artist: "Lynyrd Skynyrd", title: "Free Bird", stars: 7.5),
        .init(artist: "Eagles", title: "Hotel California", stars: 6.0),
        .init(artist: "Dire Straits", title: "Money for Nothing", stars: 4.5),
        .init(artist: "Dire Straits", title: "Sultans of Swing", stars: 7.0),
        .init(artist: "Santana", title: "Black Magic Woman", stars: 5.0),
        .init(artist: "Santana", title: "Smooth", stars: 5.5),
        .init(artist: "Santana", title: "Europa", stars: 6.5),
        .init(artist: "Rush", title: "Limelight", stars: 6.5),
        .init(artist: "Rush", title: "Tom Sawyer", stars: 6.5),
        .init(artist: "Rush", title: "YYZ", stars: 8.0),
        .init(artist: "Motörhead", title: "Ace of Spades", stars: 3.5),

        // Instrumental y progresivo
        .init(artist: "Joe Satriani", title: "Always with Me, Always with You", stars: 6.0),
        .init(artist: "Joe Satriani", title: "Surfing with the Alien", stars: 9.0),
        .init(artist: "Steve Vai", title: "Tender Surrender", stars: 9.0),
        .init(artist: "Steve Vai", title: "For the Love of God", stars: 9.0),
        .init(artist: "Dream Theater", title: "Pull Me Under", stars: 8.0),
        .init(artist: "Dream Theater", title: "Metropolis Pt. 1", stars: 9.5),
        .init(artist: "Dream Theater", title: "The Dance of Eternity", stars: 10.0)
    ]

    /// Línea base por artista, para cuando la canción concreta no está en la tabla. Es una media del
    /// catálogo del grupo, no de su tema más difícil.
    static let artists: [String: Double] = [
        // Punk y rock en español (incluye la banda del usuario y su escena)
        "kaos etiliko": 3.0, "kaotiko": 3.0, "la polla records": 2.5, "eskorbuto": 2.5,
        "los violadores": 2.5, "attaque 77": 2.5, "fiskales ad-hok": 2.5, "los prisioneros": 2.5,
        "los bunkers": 3.0, "los tres": 3.5, "sinergia": 3.0, "chancho en piedra": 4.5,
        "extremoduro": 3.5, "marea": 3.5, "platero y tu": 3.5, "heroes del silencio": 4.0,
        "soda stereo": 4.0, "cafe tacvba": 3.5, "los jaivas": 4.5, "dorso": 5.5,
        "criminal": 6.5, "pentagram": 6.5, "baron rojo": 5.0, "angeles del infierno": 5.0,
        "rata blanca": 7.0,

        // Punk y alternativo
        "ramones": 2.0, "sex pistols": 2.5, "the clash": 2.5, "blink-182": 3.0,
        "green day": 3.0, "the offspring": 3.0, "nirvana": 3.0, "the white stripes": 2.5,
        "oasis": 3.0, "radiohead": 4.0, "foo fighters": 4.0, "pearl jam": 4.5,
        "alice in chains": 4.0, "soundgarden": 4.5, "muse": 5.5, "tool": 6.5,
        "red hot chili peppers": 5.0, "rage against the machine": 5.0,

        // Rock clásico
        "the beatles": 3.5, "the rolling stones": 3.5, "ac/dc": 4.0, "queen": 5.0,
        "pink floyd": 5.0, "led zeppelin": 5.5, "deep purple": 6.0, "rainbow": 6.5,
        "eagles": 5.0, "dire straits": 5.5, "santana": 5.5, "lynyrd skynyrd": 5.5,
        "aerosmith": 4.5, "guns n' roses": 5.5, "guns n roses": 5.5, "ufo": 6.0,
        "scorpions": 5.0, "rush": 7.5, "van halen": 7.5,

        // Blues
        "b.b. king": 4.5, "albert king": 5.0, "muddy waters": 4.0, "eric clapton": 5.0,
        "cream": 5.5, "gary moore": 7.0, "stevie ray vaughan": 7.5, "jimi hendrix": 6.5,
        "joe bonamassa": 7.5,

        // Metal
        "black sabbath": 4.0, "motorhead": 4.0, "iron maiden": 6.5, "judas priest": 6.0,
        "metallica": 5.5, "megadeth": 7.5, "slayer": 7.0, "anthrax": 6.0,
        "sepultura": 5.5, "pantera": 6.5, "system of a down": 4.5, "rammstein": 3.0,
        "slipknot": 5.0, "lamb of god": 6.5, "gojira": 7.0, "trivium": 7.0,
        "avenged sevenfold": 7.5, "in flames": 6.0, "arch enemy": 7.5, "opeth": 7.5,
        "children of bodom": 8.5, "death": 8.0, "testament": 7.0, "exodus": 7.0,
        "kreator": 7.0, "helloween": 7.5, "blind guardian": 7.5, "stratovarius": 8.0,
        "sonata arctica": 8.0, "angra": 8.5, "ozzy osbourne": 7.0,

        // Instrumental y progresivo
        "joe satriani": 8.5, "steve vai": 9.0, "yngwie malmsteen": 9.5,
        "paul gilbert": 9.0, "john petrucci": 9.0, "racer x": 9.0, "dream theater": 8.5,
        "marty friedman": 8.5, "jason becker": 9.5
    ]

    /// Señales del propio registro del usuario, cuando ni la canción ni el artista están en tabla.
    private struct Signal {
        let keywords: [String]
        let delta: Double
        let reason: String
    }

    private static let signals: [Signal] = [
        .init(keywords: ["tapping", "barrido", "sweep", "shred"], delta: 2.0,
              reason: "el registro menciona técnica de virtuoso"),
        .init(keywords: ["instrumental"], delta: 1.0,
              reason: "instrumental: la guitarra sostiene el tema entero"),
        .init(keywords: ["solo rapido", "solo largo", "doble bombo", "galope", "gallop"], delta: 1.0,
              reason: "pasajes rápidos declarados en el registro"),
        .init(keywords: ["armonia", "armonias", "dos guitarras", "guitarra 2"], delta: 0.7,
              reason: "armonías a dos guitarras"),
        .init(keywords: ["solo"], delta: 0.5,
              reason: "tiene solo"),
        .init(keywords: ["arpegio", "arpegios", "fingerstyle", "acustica"], delta: 0.5,
              reason: "arpegios o mano derecha sin púa"),
        .init(keywords: ["power chord", "power chords", "acordes abiertos"], delta: -0.5,
              reason: "estructura de acordes simple")
    ]

    /// Nota por defecto cuando no hay ninguna señal: rock de dificultad media.
    static let fallbackStars = 4.0

    // MARK: - Clasificación

    static func assess(title: String, artist: String, sections: String = "", notes: String = "") -> DifficultyAssessment {
        let normalizedArtist = SongDifficultyIdentity.normalized(artist)

        if let entry = exactEntry(title: title, artist: artist) {
            return detailedAssessment(
                stars: entry.stars,
                factors: ["«\(entry.title)» de \(entry.artist): nota del tema completo, no de su pasaje más difícil"],
                title: entry.title,
                artist: entry.artist,
                sections: sections,
                notes: notes,
                authoredSummary: entry.summary,
                authoredPrerequisite: entry.prerequisites,
                authoredPractice: entry.practice
            )
        }

        if !normalizedArtist.isEmpty,
           let match = artists.first(where: { SongDifficultyIdentity.normalized($0.key) == normalizedArtist }) {
            var stars = match.value
            var factors = ["línea base de \(artist): \(format(match.value))★ de promedio en su repertorio"]
            let (delta, reasons) = signalDelta(sections: sections, notes: notes)
            stars += delta
            factors.append(contentsOf: reasons)
            return detailedAssessment(
                stars: stars, factors: factors, title: title, artist: artist,
                sections: sections, notes: notes
            )
        }

        var stars = fallbackStars
        var factors = ["sin datos del tema ni del artista: se parte de \(format(fallbackStars))★ y manda lo que anotaste"]
        let (delta, reasons) = signalDelta(sections: sections, notes: notes)
        stars += delta
        factors.append(contentsOf: reasons)
        return detailedAssessment(
            stars: stars, factors: factors, title: title, artist: artist,
            sections: sections, notes: notes
        )
    }

    static func assess(_ song: Song) -> DifficultyAssessment {
        song.persistedDifficultyProfile?.assessment ?? assess(
            title: song.title, artist: song.artist, sections: song.sections, notes: song.notes
        )
    }

    /// Una coincidencia de catálogo debe ser exacta una vez normalizados mayúsculas, tildes y signos.
    /// Con artista vacío solo se acepta un título único; así escribir parcialmente ya no toma la
    /// primera entrada que casualmente contenga esas letras.
    static func exactEntry(title: String, artist: String) -> Entry? {
        let normalizedTitle = SongDifficultyIdentity.normalized(title)
        let normalizedArtist = SongDifficultyIdentity.normalized(artist)
        guard !normalizedTitle.isEmpty else { return nil }
        let titleMatches = songs.filter { SongDifficultyIdentity.normalized($0.title) == normalizedTitle }
        if normalizedArtist.isEmpty { return titleMatches.count == 1 ? titleMatches[0] : nil }
        return titleMatches.first { SongDifficultyIdentity.normalized($0.artist) == normalizedArtist }
    }

    static func artistBaseline(named artist: String) -> Double? {
        let normalizedArtist = SongDifficultyIdentity.normalized(artist)
        guard !normalizedArtist.isEmpty else { return nil }
        return artists.first { SongDifficultyIdentity.normalized($0.key) == normalizedArtist }?.value
    }

    private static func signalDelta(sections: String, notes: String) -> (Double, [String]) {
        let haystack = normalized([sections, notes].joined(separator: " "))
        guard !haystack.isEmpty else { return (0, []) }
        var total = 0.0
        var reasons: [String] = []
        for signal in signals where signal.keywords.contains(where: { haystack.contains($0) }) {
            total += signal.delta
            reasons.append("\(signal.delta > 0 ? "+" : "")\(format(signal.delta)) \(signal.reason)")
        }
        return (min(max(total, -1.5), 2.5), reasons)
    }

    private static func detailedAssessment(
        stars: Double,
        factors: [String],
        title: String,
        artist: String,
        sections: String,
        notes: String,
        authoredSummary: String? = nil,
        authoredPrerequisite: String? = nil,
        authoredPractice: String? = nil
    ) -> DifficultyAssessment {
        let rating = DifficultyRating(stars: stars)
        let haystack = normalized([sections, notes].joined(separator: " "))
        let parsedSections = sections
            .split(whereSeparator: { [",", ";", "|", "/"].contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var demands: [String] = []
        if haystack.contains("sweep") || haystack.contains("barrido") || haystack.contains("tapping") || haystack.contains("shred") {
            demands.append("Resolver el pasaje virtuoso con muting, sincronía y articulación pareja, no solo alcanzar sus notas.")
        }
        if haystack.contains("solo") {
            demands.append("Integrar el solo con bends, vibrato y fraseo afinados dentro del tempo del tema.")
        }
        if haystack.contains("galope") || haystack.contains("gallop") || haystack.contains("solo rapido") || haystack.contains("solo largo") {
            demands.append("Sostener velocidad y resistencia sin que la tensión cambie el ataque ni el tempo.")
        }
        if haystack.contains("armonia") || haystack.contains("dos guitarras") || haystack.contains("guitarra 2") {
            demands.append("Mantener afinación, tiempo y balance al tocar una voz que debe encajar con otra guitarra.")
        }
        if haystack.contains("arpegio") || haystack.contains("fingerstyle") || haystack.contains("acustica") {
            demands.append("Conservar separación y volumen parejo entre las voces del arpegio.")
        }
        if parsedSections.count >= 5 {
            demands.append("Recordar una forma de \(parsedSections.count) secciones y recuperar el pulso al pasar de una a otra.")
        }
        if demands.isEmpty {
            demands.append(defaultSongDemand(for: rating))
        }

        let sourceSummary: String
        if let authoredSummary {
            sourceSummary = authoredSummary
        } else {
            let byline = artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "«\(title)»"
                : "«\(title)» de \(artist)"
            let formDetail = parsedSections.isEmpty
                ? ""
                : " El registro contempla una forma de \(parsedSections.count) secciones —\(naturalList(parsedSections))—, así que la nota evalúa la ejecución completa."
            sourceSummary = "\(byline) queda en \(rating.label) por la suma de continuidad, tiempo, limpieza y exigencia de sus pasajes.\(formDetail)"
        }

        return DifficultyAssessment(
            rating: rating,
            factors: factors,
            summary: sourceSummary,
            demands: Array(demands.prefix(3)),
            prerequisites: [authoredPrerequisite ?? defaultSongPrerequisite(for: rating)],
            practiceFocus: authoredPractice ?? defaultSongPractice(for: rating, sections: parsedSections)
        )
    }

    private static func defaultSongDemand(for rating: DifficultyRating) -> String {
        switch rating.stars {
        case ..<3.5:
            "Mantener pulso, cambios de acorde y silencios limpios durante el tema completo."
        case ..<5.5:
            "Coordinar riff, acompañamiento y posibles fills sin perder groove al cambiar de sección."
        case ..<7.5:
            "Sostener articulación, dinámica y control técnico a tempo real durante una forma completa."
        default:
            "Combinar velocidad, precisión y expresión de nivel avanzado sin que una exigencia deteriore las otras."
        }
    }

    private static func defaultSongPrerequisite(for rating: DifficultyRating) -> String {
        switch rating.stars {
        case ..<3.5:
            "Acordes o riffs básicos y capacidad de seguir una forma sencilla con metrónomo."
        case ..<5.5:
            "Ritmo de corcheas estable, muting y cambios de posición sin detener el pulso."
        case ..<7.5:
            "Riffs completos a tempo moderado, fraseo con bends y vibrato, y autonomía para estudiar por secciones."
        default:
            "Técnicas avanzadas ya consolidadas por separado, resistencia a tempo alto y control musical bajo presión."
        }
    }

    private static func defaultSongPractice(for rating: DifficultyRating, sections: [String]) -> String {
        if sections.count >= 3 {
            return "Marca un tempo de control para cada sección, practica los enlaces y haz una pasada completa sin detenerte antes de acercarte al tempo de disco."
        }
        if rating.stars >= 6.0 {
            return "Identifica el pasaje límite, practícalo en bloques cortos y reserva las pasadas completas para comprobar continuidad, no para aprender las notas."
        }
        return "Graba una pasada a tempo reducido, corrige primero pulso y silencios y aumenta velocidad solo cuando la forma sea continua."
    }

    private static func naturalList(_ values: [String]) -> String {
        switch values.count {
        case 0: ""
        case 1: values[0]
        case 2: "\(values[0]) y \(values[1])"
        default: values.dropLast().joined(separator: ", ") + " y " + (values.last ?? "")
        }
    }

    /// Coincidencia tolerante en ambas direcciones: "Satisfaction" encuentra "(I Can't Get No)
    /// Satisfaction" y "Metropolis Pt. 1 (The Miracle and the Sleeper)" encuentra "Metropolis Pt. 1".
    private static func matches(_ value: String, _ candidate: String) -> Bool {
        guard !value.isEmpty, !candidate.isEmpty else { return false }
        return value == candidate || value.contains(candidate) || candidate.contains(value)
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}

enum SongDifficultyResolver {
    static func profile(
        title: String,
        artist: String,
        sections: String = "",
        notes: String = "",
        role: SongGuitarRole = .fullArrangement,
        records: [SongDifficultyRecord] = [],
        songs: [Song] = [],
        excludingSongID: UUID? = nil
    ) -> SongDifficultyProfile {
        let key = SongDifficultyIdentity.key(title: title, artist: artist, role: role)

        if let learned = records.first(where: { $0.catalogKey == key }) {
            return learned.profile.reusedFromCatalog()
        }

        if let learnedSong = songs.first(where: {
            $0.id != excludingSongID &&
            $0.persistedDifficultyProfile?.catalogKey == key
        }), let profile = learnedSong.persistedDifficultyProfile {
            return profile.reusedFromCatalog()
        }

        if SongDifficultyCatalog.exactEntry(title: title, artist: artist) != nil {
            let assessment = SongDifficultyCatalog.assess(
                title: title, artist: artist, sections: sections, notes: notes
            )
            return profileFromAssessment(
                assessment, title: title, artist: artist, role: role,
                source: .curatedCatalog, confidence: .high, sections: sections
            )
        }

        let normalizedArtist = SongDifficultyIdentity.normalized(artist)
        var learnedRatingsByKey: [String: Double] = [:]
        for record in records {
            guard SongDifficultyIdentity.normalized(record.artist) == normalizedArtist,
                  record.roleRaw == role.rawValue,
                  record.confidenceRaw != SongDifficultyConfidence.low.rawValue else { continue }
            learnedRatingsByKey[record.catalogKey] = record.stars
        }
        for song in songs {
            guard song.id != excludingSongID,
                  SongDifficultyIdentity.normalized(song.artist) == normalizedArtist,
                  let profile = song.persistedDifficultyProfile,
                  profile.role == role,
                  profile.confidence != .low else { continue }
            learnedRatingsByKey[profile.catalogKey, default: profile.rating.stars] = profile.rating.stars
        }
        let learnedArtistRatings = Array(learnedRatingsByKey.values)

        if !normalizedArtist.isEmpty, !learnedArtistRatings.isEmpty {
            let median = median(learnedArtistRatings)
            let assessment = provisionalAssessment(
                title: title, artist: artist, sections: sections, notes: notes,
                baseStars: median,
                firstFactor: "mediana de \(learnedArtistRatings.count) canción(es) analizada(s) de \(artist): \(DifficultyRating(stars: median).label)"
            )
            return profileFromAssessment(
                assessment, title: title, artist: artist, role: role,
                source: .artistProfile,
                confidence: learnedArtistRatings.count >= 3 ? .medium : .low,
                sections: sections
            )
        }

        let assessment = SongDifficultyCatalog.assess(
            title: title, artist: artist, sections: sections, notes: notes
        )
        let hasArtistBaseline = SongDifficultyCatalog.artistBaseline(named: artist) != nil
        return profileFromAssessment(
            assessment, title: title, artist: artist, role: role,
            source: hasArtistBaseline ? .artistProfile : .legacyHeuristic,
            confidence: .low, sections: sections
        )
    }

    static func profile(for song: Song, records: [SongDifficultyRecord] = []) -> SongDifficultyProfile {
        if let persisted = song.persistedDifficultyProfile { return persisted }
        return profile(
            title: song.title, artist: song.artist, sections: song.sections, notes: song.notes,
            role: song.guitarRole, records: records, songs: [], excludingSongID: song.id
        )
    }

    private static func profileFromAssessment(
        _ assessment: DifficultyAssessment,
        title: String,
        artist: String,
        role: SongGuitarRole,
        source: SongDifficultySource,
        confidence: SongDifficultyConfidence,
        sections: String
    ) -> SongDifficultyProfile {
        let stars = assessment.rating.stars
        return SongDifficultyProfile(
            title: title, artist: artist, role: role, rating: assessment.rating,
            dimensions: SongDifficultyDimensions(
                technique: stars, speed: stars, rhythm: stars,
                endurance: stars, solo: stars, form: stars
            ),
            source: source, confidence: confidence, summary: assessment.summary,
            factors: assessment.factors, demands: assessment.demands,
            prerequisites: assessment.prerequisites, practiceFocus: assessment.practiceFocus,
            suggestedSections: parsedSections(sections), analyzedAt: .now,
            analysisVersion: SongDifficultyProfile.currentAnalysisVersion
        )
    }

    private static func provisionalAssessment(
        title: String,
        artist: String,
        sections: String,
        notes: String,
        baseStars: Double,
        firstFactor: String
    ) -> DifficultyAssessment {
        let original = SongDifficultyCatalog.assess(
            title: title, artist: "", sections: sections, notes: notes
        )
        // Conserva solo el ajuste que la heurística aplicó sobre su base de 4★ y lo traslada a la
        // mediana aprendida del artista.
        let signalDelta = original.rating.stars - SongDifficultyCatalog.fallbackStars
        let rating = DifficultyRating(stars: baseStars + signalDelta)
        return DifficultyAssessment(
            rating: rating,
            factors: [firstFactor] + original.factors.dropFirst(),
            summary: "«\(title)» de \(artist) tiene una estimación provisional basada en las canciones ya analizadas del artista; conviene confirmarla con el análisis por dimensiones.",
            demands: original.demands,
            prerequisites: original.prerequisites,
            practiceFocus: original.practiceFocus
        )
    }

    private static func parsedSections(_ value: String) -> [String] {
        value.split(whereSeparator: { [",", ";", "|", "/"].contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) { return (sorted[middle - 1] + sorted[middle]) / 2 }
        return sorted[middle]
    }
}

enum SongDifficultyAIError: LocalizedError {
    case invalidResponse
    case unavailable(cloud: String, local: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "La IA no devolvió las seis dimensiones de dificultad en el formato esperado."
        case .unavailable(let cloud, let local):
            "No se pudo analizar con Gemini ni con la IA local. Gemini: \(cloud) IA local: \(local)"
        }
    }
}

enum SongDifficultyAIService {
    @MainActor
    static func analyzeSongBestAvailable(
        title: String,
        artist: String,
        role: SongGuitarRole,
        sections: String,
        notes: String,
        orchestrator: AIOrchestrator
    ) async throws -> SongDifficultyProfile {
        var cloudMessage = "no configurado."
        do {
            let backend = try orchestrator.paidCloudBackend()
            return try await analyzeSong(
                title: title, artist: artist, role: role, sections: sections, notes: notes,
                source: .gemini, backend: backend
            )
        } catch {
            cloudMessage = error.localizedDescription
        }

        do {
            let backend = try await orchestrator.localBackend(for: .medium)
            return try await analyzeSong(
                title: title, artist: artist, role: role, sections: sections, notes: notes,
                source: .localAI, backend: backend
            )
        } catch {
            throw SongDifficultyAIError.unavailable(cloud: cloudMessage, local: error.localizedDescription)
        }
    }

    static func analyzeSong(
        title: String,
        artist: String,
        role: SongGuitarRole,
        sections: String,
        notes: String,
        source: SongDifficultySource,
        backend: JSONCompletionBackend
    ) async throws -> SongDifficultyProfile {
        let prompt = """
        Eres un profesor de guitarra y catalogador musical. Evalúa la dificultad ABSOLUTA de tocar la
        siguiente canción a tempo de disco, de principio a fin, en el rol indicado. No evalúes el nivel
        del alumno. Si no reconoces con seguridad la versión, declara confianza baja y evita inventar.

        Canción: \(title)
        Artista: \(artist)
        Rol: \(role.rawValue)
        Secciones aportadas: \(sections.isEmpty ? "ninguna" : sections)
        Notas aportadas: \(notes.isEmpty ? "ninguna" : notes)

        Puntúa cada dimensión de 0.5 a 10 usando medios puntos:
        - technique: coordinación, articulación, bends, muting y técnicas especiales.
        - speed: velocidad pico y precisión requerida.
        - rhythm: síncopas, métricas, subdivisión, cambios y groove.
        - endurance: duración, repetición y tensión sostenida.
        - solo: dificultad de solos y partes melódicas; 1 si el rol no tiene ninguna.
        - form: memoria, cantidad de secciones, transiciones y dinámica del tema completo.

        No entregues una nota final: la aplicación la calcula con una fórmula fija. Responde SOLO JSON:
        {
          "confidence": "high|medium|low",
          "dimensions": {"technique": 5.0, "speed": 5.0, "rhythm": 5.0, "endurance": 5.0, "solo": 5.0, "form": 5.0},
          "summary": "explicación específica y verificable, máximo 45 palabras",
          "evidence": ["2 a 5 hechos musicales concretos"],
          "demands": ["2 a 4 exigencias observables"],
          "prerequisites": ["1 a 3 bases previas"],
          "practice_focus": "primera estrategia concreta, máximo 35 palabras",
          "sections": ["estructura real, 4 a 10 nombres cortos; vacío si no hay certeza"]
        }
        """

        let raw = try await backend.completeJSON(prompt: prompt)
        let object = try JSONAIParser.object(from: raw)
        return try profile(from: object, title: title, artist: artist, role: role, source: source)
    }

    @MainActor
    static func analyzeBandBestAvailable(
        artist: String,
        orchestrator: AIOrchestrator
    ) async throws -> [SongDifficultyProfile] {
        var cloudMessage = "no configurado."
        do {
            let backend = try orchestrator.paidCloudBackend()
            return try await analyzeBand(artist: artist, source: .gemini, backend: backend)
        } catch {
            cloudMessage = error.localizedDescription
        }

        do {
            let backend = try await orchestrator.localBackend(for: .medium)
            return try await analyzeBand(artist: artist, source: .localAI, backend: backend)
        } catch {
            throw SongDifficultyAIError.unavailable(cloud: cloudMessage, local: error.localizedDescription)
        }
    }

    static func analyzeBand(
        artist: String,
        source: SongDifficultySource,
        backend: JSONCompletionBackend
    ) async throws -> [SongDifficultyProfile] {
        let prompt = """
        Eres un profesor de guitarra y catalogador musical. Amplía el catálogo para la banda o artista
        "\(artist)" con entre 5 y 8 canciones reales, conocidas y representativas para guitarra.
        Evalúa el ARREGLO COMPLETO a tempo de disco. No inventes títulos: si no conoces al artista con
        certeza, devuelve songs vacío. Usa la misma escala objetiva de 0.5 a 10 por medios puntos.

        Responde SOLO JSON:
        {"songs":[{
          "title":"título exacto", "confidence":"high|medium|low",
          "dimensions":{"technique":5.0,"speed":5.0,"rhythm":5.0,"endurance":5.0,"solo":5.0,"form":5.0},
          "summary":"máximo 35 palabras", "evidence":["hechos concretos"],
          "demands":["exigencias"], "prerequisites":["bases previas"],
          "practice_focus":"máximo 30 palabras", "sections":[]
        }]}
        """
        let raw = try await backend.completeJSON(prompt: prompt)
        let object = try JSONAIParser.object(from: raw)
        guard let items = object["songs"] as? [[String: Any]] else { throw SongDifficultyAIError.invalidResponse }
        var seenKeys: Set<String> = []
        return items.compactMap { item in
            guard let title = string(item["title"]), !title.isEmpty else { return nil }
            guard let profile = try? profile(
                from: item, title: title, artist: artist, role: .fullArrangement, source: source
            ), profile.confidence != .low, seenKeys.insert(profile.catalogKey).inserted else { return nil }
            return profile
        }
    }

    private static func profile(
        from object: [String: Any],
        title: String,
        artist: String,
        role: SongGuitarRole,
        source: SongDifficultySource
    ) throws -> SongDifficultyProfile {
        guard let rawDimensions = object["dimensions"] as? [String: Any],
              let technique = number(rawDimensions["technique"]),
              let speed = number(rawDimensions["speed"]),
              let rhythm = number(rawDimensions["rhythm"]),
              let endurance = number(rawDimensions["endurance"]),
              let solo = number(rawDimensions["solo"]),
              let form = number(rawDimensions["form"]) else {
            throw SongDifficultyAIError.invalidResponse
        }
        let dimensions = SongDifficultyDimensions(
            technique: technique, speed: speed, rhythm: rhythm,
            endurance: endurance, solo: solo, form: form
        )
        let evidence = strings(object["evidence"])
        let formula = "fórmula fija: técnica 25%, velocidad 15%, ritmo 20%, resistencia 10%, solo 20% y forma 10%"
        return SongDifficultyProfile(
            title: title, artist: artist, role: role, rating: dimensions.weightedRating,
            dimensions: dimensions, source: source,
            confidence: confidence(object["confidence"]),
            summary: string(object["summary"]) ?? "Evaluación por seis dimensiones observables del arreglo completo.",
            factors: evidence + [formula], demands: strings(object["demands"]),
            prerequisites: strings(object["prerequisites"]),
            practiceFocus: string(object["practice_focus"]) ?? "Practica primero el pasaje que limita el tempo y valida luego una pasada completa.",
            suggestedSections: strings(object["sections"]), analyzedAt: .now,
            analysisVersion: SongDifficultyProfile.currentAnalysisVersion
        )
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text.replacingOccurrences(of: ",", with: ".")) }
        return nil
    }

    private static func string(_ value: Any?) -> String? {
        (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func strings(_ value: Any?) -> [String] {
        (value as? [Any] ?? []).compactMap(string).filter { !$0.isEmpty }
    }

    private static func confidence(_ value: Any?) -> SongDifficultyConfidence {
        switch string(value)?.lowercased() {
        case "high", "alta": .high
        case "medium", "media": .medium
        default: .low
        }
    }
}
