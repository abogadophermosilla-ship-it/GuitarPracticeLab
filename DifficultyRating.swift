import Foundation
import SwiftUI

/// Dificultad en la escala de 10 estrellas con medias estrellas (0,5★ a 10★) que reemplaza en toda
/// la app al antiguo `SkillLevel` de tres escalones (Básico / Intermedio / Avanzado).
///
/// El motivo del cambio es de precisión: en el catálogo real de la Biblioteca, 1.792 de 2.242
/// ejercicios caían en "intermedio", así que la etiqueta no distinguía un patrón de dos notas por
/// cuerda de un barrido de cinco cuerdas. Veinte escalones sí alcanzan para ordenar el material y
/// para comparar un ejercicio contra el nivel real del alumno (ver `DifficultyFit`).
///
/// Se guarda como texto decimal invariante ("6.5") en las mismas columnas que antes tenían el nivel
/// (`LibraryExercise.difficultyRaw`, `LibraryConcept.levelRaw`, `SkillTopic.levelRaw`), así que no
/// hace falta una `SchemaV2`: `parse(_:)` sigue entendiendo los valores viejos en español y los
/// convierte al centro de su banda.
struct DifficultyRating: Hashable, Comparable, Codable, Identifiable {
    static let minimumHalfStars = 1
    static let maximumHalfStars = 20

    /// Cantidad de medias estrellas (1...20). Es la unidad interna para que comparar y ordenar sea
    /// exacto: con `Double` puro, 6,5 podría no ser igual a 6,5 tras un par de operaciones.
    let halfStars: Int

    init(halfStars: Int) {
        self.halfStars = min(max(halfStars, Self.minimumHalfStars), Self.maximumHalfStars)
    }

    /// Redondea a la media estrella más cercana y recorta al rango 0,5-10.
    init(stars: Double) {
        self.init(halfStars: Int((stars * 2).rounded()))
    }

    /// Para una proporción 0-1, como el porcentaje del Test Integral: 45,5% → 4,5★.
    init(ratio: Double) {
        self.init(stars: ratio * 10)
    }

    var id: Int { halfStars }
    var stars: Double { Double(halfStars) / 2 }
    /// Estrellas completamente pintadas (0...10).
    var fullStars: Int { halfStars / 2 }
    var hasHalfStar: Bool { halfStars % 2 == 1 }

    /// "6,5" con la coma decimal del sistema, sin decimal cuando el valor es entero.
    var formatted: String {
        stars.formatted(.number.precision(.fractionLength(0...1)))
    }

    /// Texto corto para píldoras, filas y prompts: "6,5★/10".
    var label: String { "\(formatted)★/10" }

    static func < (lhs: DifficultyRating, rhs: DifficultyRating) -> Bool {
        lhs.halfStars < rhs.halfStars
    }

    // MARK: - Persistencia

    /// Siempre con punto decimal, independiente del idioma del sistema, para que un respaldo hecho
    /// en español se pueda restaurar en cualquier otro idioma.
    var storedValue: String {
        String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), stars)
    }

    /// Lee el valor guardado. Acepta el formato nuevo ("6.5", y también "6,5" por si algún respaldo
    /// viejo quedó con coma) y los tres niveles en texto que usaba la app antes de la escala de 10.
    static func parse(_ raw: String?) -> DifficultyRating? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        if let value = Double(trimmed.replacingOccurrences(of: ",", with: ".")) {
            return DifficultyRating(stars: value)
        }
        return legacy(trimmed)
    }

    /// Centro de la banda que ocupaba cada nivel viejo dentro de la escala nueva. Solo se usa al
    /// abrir datos anteriores al cambio; el clasificador vuelve a evaluarlos con criterio real.
    private static func legacy(_ raw: String) -> DifficultyRating? {
        switch raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) {
        case "principiante", "basico", "inicial": DifficultyRating(stars: 2.5)
        case "intermedio": DifficultyRating(stars: 5)
        case "avanzado": DifficultyRating(stars: 8)
        default: nil
        }
    }

    // MARK: - Banda

    var band: DifficultyBand {
        DifficultyBand(rawValue: max(1, Int(stars.rounded(.up)))) ?? .elite
    }

    var color: Color { band.color }
}

/// Los 10 peldaños descriptivos de la escala, uno por estrella entera. Las medias estrellas se
/// mantienen en la nota exacta; para agrupar, 4,5★ pertenece al peldaño 5.
enum DifficultyBand: Int, CaseIterable, Identifiable, Codable {
    case firstContact = 1
    case foundations = 2
    case solidBeginner = 3
    case earlyIntermediate = 4
    case intermediate = 5
    case upperIntermediate = 6
    case earlyAdvanced = 7
    case advanced = 8
    case veryAdvanced = 9
    case elite = 10

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .firstContact: "Primer contacto"
        case .foundations: "Fundamentos"
        case .solidBeginner: "Base sólida"
        case .earlyIntermediate: "Desarrollo técnico I"
        case .intermediate: "Desarrollo técnico II"
        case .upperIntermediate: "Control y fluidez"
        case .earlyAdvanced: "Ejecución exigente"
        case .advanced: "Alta exigencia"
        case .veryAdvanced: "Virtuosismo"
        case .elite: "Referencia profesional"
        }
    }

    /// Criterio de profesor para cada peldaño: qué tiene que poder hacer alguien para estar ahí.
    var criteria: String {
        switch self {
        case .firstContact:
            "Primeras semanas con la guitarra: cuerdas al aire, notas sueltas, un acorde a la vez sin exigencia de tempo."
        case .foundations:
            "Acordes abiertos y power chords con cambios lentos, rasgueo de negras y corcheas, pulso sostenido con metrónomo lento."
        case .solidBeginner:
            "Riffs de una guitarra completa, cejilla, palm mute básico, pentatónica en una posición y corcheas parejas a tempo medio."
        case .earlyIntermediate:
            "Corcheas rápidas o semicorcheas lentas con púa alterna, bends de un tono afinados, vibrato voluntario y cambios de posición limpios."
        case .intermediate:
            "Solos completos de rock clásico, dos o tres posiciones conectadas, síncopa y galope estables, arpegios sencillos con púa."
        case .upperIntermediate:
            "Semicorcheas sostenidas, tres notas por cuerda, saltos de cuerda controlados, armónicos y frases con fraseo propio."
        case .earlyAdvanced:
            "Solos exigentes a tempo real, legato parejo, economía de púa, modos aplicados sobre la armonía y muting impecable."
        case .advanced:
            "Barridos de cuatro o cinco cuerdas, tapping melódico, tresillos de semicorchea a tempo alto y material no diatónico."
        case .veryAdvanced:
            "Repertorio virtuoso: barridos extendidos, sextillos sostenidos, cambios de métrica y velocidad sin pérdida de tono."
        case .elite:
            "Piezas de referencia del instrumento, al límite de lo que se toca en disco, con exigencia técnica y musical simultánea."
        }
    }

    var color: Color {
        switch self {
        case .firstContact, .foundations: .green
        case .solidBeginner: .mint
        case .earlyIntermediate: .teal
        case .intermediate: .blue
        case .upperIntermediate: .indigo
        case .earlyAdvanced: .purple
        case .advanced: .orange
        case .veryAdvanced: .pink
        case .elite: .red
        }
    }
}

// MARK: - Ajuste al nivel del alumno

/// Qué tan bien le calza al alumno un material de dificultad dada. Es la parte de "adecuarlo a mi
/// nivel": la dificultad de un ejercicio es absoluta, esto es la lectura relativa contra el nivel
/// que arrojó el Test Integral (ver `StudentLevelService`).
enum DifficultyFit: Int, CaseIterable, Identifiable, Codable {
    case mastered
    case review
    case onLevel
    case stretch
    case tooHard

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .mastered: "Ya lo superaste"
        case .review: "Repaso"
        case .onLevel: "A tu nivel"
        case .stretch: "Desafío"
        case .tooHard: "Te queda grande"
        }
    }

    var advice: String {
        switch self {
        case .mastered:
            "Está bastante por debajo de tu nivel. Sirve como calentamiento o para pulir tono, no para avanzar."
        case .review:
            "Un poco por debajo de tu nivel: ideal para consolidar y subir tempo sin pelear con las notas."
        case .onLevel:
            "Justo en tu zona de trabajo. Acá es donde rinde la práctica diaria."
        case .stretch:
            "Por encima de tu nivel actual, pero alcanzable a tempo reducido. Un desafío por vez, no la rutina completa."
        case .tooHard:
            "Muy por encima de tu nivel. Sin los pasos previos solo consolida tensión y errores."
        }
    }

    var icon: String {
        switch self {
        case .mastered: "checkmark.seal.fill"
        case .review: "arrow.counterclockwise"
        case .onLevel: "target"
        case .stretch: "flame.fill"
        case .tooHard: "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .mastered: .secondary
        case .review: .teal
        case .onLevel: .green
        case .stretch: .orange
        case .tooHard: .red
        }
    }
}

extension DifficultyRating {
    /// Los cortes son asimétricos a propósito: practicar medio punto por encima del nivel propio es
    /// lo normal y deseable, mientras que medio punto por debajo ya no enseña nada nuevo.
    func fit(forStudentLevel level: DifficultyRating) -> DifficultyFit {
        let delta = stars - level.stars
        switch delta {
        case ..<(-2.0): return .mastered
        case (-2.0)..<(-0.5): return .review
        case (-0.5)...1.0: return .onLevel
        case 1.0...2.5: return .stretch
        default: return .tooHard
        }
    }
}

// MARK: - Nivel actual y presentación común

/// Única traducción del resultado del Test Integral a la escala de la aplicación. El porcentaje se
/// conserva porque es el dato exacto del test; 45,5 % se presenta y se compara como 4,5★/10.
enum StudentLevelService {
    static func rating(forPercentage percentage: Double) -> DifficultyRating? {
        guard percentage > 0 else { return nil }
        return DifficultyRating(ratio: min(max(percentage, 0), 100) / 100)
    }

    static var currentRating: DifficultyRating? {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "hasCompletedSkillAssessment") else { return nil }
        return rating(forPercentage: defaults.double(forKey: "overallLevelPercentage"))
    }
}

/// Migra únicamente la frase numérica del resumen que ya había redactado el asistente. No vuelve a
/// llamar a IA ni toca fortalezas/debilidades: cambia "45% (Básico)" por "4,5★/10" para que el
/// texto cacheado tampoco contradiga la escala nueva.
enum DifficultyScaleMigration {
    private static let summaryKey = "overallGuitaristLevel"

    static func migrateCachedAssessmentSummary(defaults: UserDefaults = .standard) {
        guard let rating = StudentLevelService.rating(
            forPercentage: defaults.double(forKey: "overallLevelPercentage")
        ), let summary = defaults.string(forKey: summaryKey) else { return }
        let migrated = rewrittenSummary(summary, rating: rating)
        if migrated != summary { defaults.set(migrated, forKey: summaryKey) }
    }

    static func rewrittenSummary(_ summary: String, rating: DifficultyRating) -> String {
        let pattern = #"\d+(?:[\.,]\d+)?%\s*(?:—\s*)?\((?:Inicial|Principiante|Básico|Intermedio(?: alto)?|Avanzado(?: consolidado)?)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return summary }
        let range = NSRange(summary.startIndex..<summary.endIndex, in: summary)
        return regex.stringByReplacingMatches(in: summary, range: range, withTemplate: rating.label)
    }
}

/// Las diez estrellas completas (incluida la media estrella) para fichas y cabeceras. En filas
/// estrechas se usa `DifficultyBadge`, que conserva exactamente la misma información como número.
struct DifficultyStarsView: View {
    let rating: DifficultyRating
    var size: CGFloat = 11

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<10, id: \.self) { index in
                Image(systemName: symbol(at: index))
                    .font(.system(size: size, weight: .medium))
            }
        }
        .foregroundStyle(rating.color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dificultad: \(rating.formatted) de 10 estrellas")
    }

    private func symbol(at index: Int) -> String {
        let starStart = index * 2
        if rating.halfStars >= starStart + 2 { return "star.fill" }
        if rating.halfStars == starStart + 1 { return "star.leadinghalf.filled" }
        return "star"
    }
}

struct DifficultyBadge: View {
    let rating: DifficultyRating

    var body: some View {
        Label(rating.label, systemImage: rating.hasHalfStar ? "star.leadinghalf.filled" : "star.fill")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(rating.color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(rating.color.opacity(0.12), in: Capsule())
            .fixedSize()
            .accessibilityLabel("Dificultad: \(rating.formatted) de 10 estrellas")
    }
}

struct DifficultyFitBadge: View {
    let fit: DifficultyFit

    var body: some View {
        Label(fit.name, systemImage: fit.icon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(fit.color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(fit.color.opacity(0.12), in: Capsule())
            .fixedSize()
    }
}

struct DifficultySummaryView: View {
    let assessment: DifficultyAssessment
    var studentLevel: DifficultyRating? = StudentLevelService.currentRating
    var showsExplanation = true
    @State private var showsCalculation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                DifficultyStarsView(rating: assessment.rating, size: 13)
                Text(assessment.rating.label)
                    .font(.headline.monospacedDigit())
                Text(assessment.rating.band.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let studentLevel {
                    DifficultyFitBadge(fit: assessment.rating.fit(forStudentLevel: studentLevel))
                }
            }
            if showsExplanation {
                if assessment.summary.isEmpty {
                    Text(assessment.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("Resumen del profesor", systemImage: "person.fill.viewfinder")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(assessment.summary)
                            .font(.callout)
                    }

                    if !assessment.demands.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("QUÉ EXIGE")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                            ForEach(Array(assessment.demands.prefix(3).enumerated()), id: \.offset) { _, demand in
                                HStack(alignment: .firstTextBaseline, spacing: 7) {
                                    Image(systemName: "circle.fill")
                                        .font(.system(size: 4))
                                        .foregroundStyle(assessment.rating.color)
                                    Text(demand)
                                        .font(.caption)
                                }
                            }
                        }
                    }

                    if !assessment.prerequisites.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("ANTES CONVIENE DOMINAR")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                            Text(assessment.prerequisites.prefix(3).joined(separator: " "))
                                .font(.caption)
                        }
                    }

                    if !assessment.practiceFocus.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(studentLevel == nil ? "CÓMO TRABAJARLO" : "PLAN PARA TU NIVEL")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                            if let studentLevel {
                                Text("\(assessment.rating.fit(forStudentLevel: studentLevel).advice) \(assessment.practiceFocus)")
                                    .font(.caption)
                            } else {
                                Text(assessment.practiceFocus)
                                    .font(.caption)
                            }
                        }
                    }

                    if !assessment.factors.isEmpty {
                        DisclosureGroup(isExpanded: $showsCalculation) {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(assessment.factors.enumerated()), id: \.offset) { _, factor in
                                    Text("• \(factor)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.top, 4)
                        } label: {
                            Text("Cómo se calculó · \(assessment.factors.count) señales")
                                .font(.caption2.weight(.semibold))
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}
