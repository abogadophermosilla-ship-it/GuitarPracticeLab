import SwiftUI
import SwiftData

/// Elige `count` preguntas al azar de `pool`. El resultado se guarda en `SkillTopic.activeRotationQuestions`
/// apenas se calcula (una vez por sesión de revisión), así que no hace falta que el sorteo sea
/// reproducible entre relanzamientos de la app — no se vuelve a recalcular hasta la próxima revisión.
enum RotationSampler {
    static func sample(from pool: [AssessmentQuestion], count: Int) -> [AssessmentQuestion] {
        guard pool.count > count else { return pool }
        return Array(pool.shuffled().prefix(count))
    }
}

/// Sesión mensual de revisión: genera una candidata por habilidad con Gemini pagado y respaldo local
/// (una llamada por pregunta, secuencial, nunca un lote — ver `SkillAssessmentQuestionDraftService`), y deja que el
/// usuario apruebe, edite o descarte cada una antes de que cuente. Al terminar, recalcula la muestra
/// rotativa de cada habilidad a partir de todo lo aprobado hasta ahora (`approvedRotationPool`).
struct SkillAssessmentQuestionReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SkillTopic.name) private var topics: [SkillTopic]
    @StateObject private var orchestrator = AIOrchestrator()
    @AppStorage("lastQuestionRefreshDate") private var lastQuestionRefreshDate: Double = 0

    @State private var isGenerating = false
    @State private var generatedCount = 0
    @State private var totalCount = 0
    @State private var failedTopicNames: [String] = []
    @State private var errorMessage = ""
    /// Habilidades donde se aprobó al menos una candidata en esta sesión — solo esas se resortean
    /// al terminar, para no borrar respuestas ya marcadas en el resto (ver `finishReview`).
    @State private var approvedTopicIDs: Set<UUID> = []

    private var topicsWithCandidates: [SkillTopic] {
        topics.filter { !$0.pendingCandidateQuestions.isEmpty }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Gemini redacta una pregunta nueva por habilidad y la IA local queda como respaldo. Revisa cada una: aprueba las que sirvan o descarta las que no, y edita el enunciado antes de aprobar si hace falta.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                if isGenerating {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: Double(generatedCount), total: Double(max(totalCount, 1)))
                        Text("Generando \(generatedCount)/\(totalCount)… \(orchestrator.currentStatus)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                } else {
                    Button("Generar candidatas para las \(topics.count) habilidades", systemImage: "sparkles") {
                        Task { await generateAllCandidates() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.horizontal)
                }

                if !failedTopicNames.isEmpty {
                    Text("No se pudo generar para: \(failedTopicNames.joined(separator: ", ")). Puedes reintentar con el botón de arriba: solo se generarán las que falten.")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .padding(.horizontal)
                }
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                if topicsWithCandidates.isEmpty {
                    ContentUnavailableView(
                        "Sin candidatas pendientes",
                        systemImage: "checkmark.circle",
                        description: Text("Genera candidatas nuevas con el botón de arriba, o cierra esta pantalla si ya terminaste.")
                    )
                } else {
                    List {
                        ForEach(topicsWithCandidates) { topic in
                            Section {
                                ForEach(topic.pendingCandidateQuestions.indices, id: \.self) { index in
                                    CandidateQuestionRow(topic: topic, index: index, approvedTopicIDs: $approvedTopicIDs)
                                }
                            } header: {
                                Text(topic.name)
                                    .font(.headline)
                                    .textCase(nil)
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .padding(.top, 12)
            .interactiveDismissDisabled(isGenerating)
            .frame(minWidth: 760, idealWidth: 940, minHeight: 640, idealHeight: 820)
            .navigationTitle("Revisar preguntas nuevas")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminar revisión") {
                        finishReview()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isGenerating)
                }
                ToolbarItem(placement: .cancellationAction) {
                    // Deshabilitado mientras genera: al cerrar y reabrir, la hoja se reconstruye con
                    // `@State` limpio (`isGenerating == false`), así que el botón de generar volvía a
                    // quedar disponible y se podían lanzar dos tandas sobre las mismas 38
                    // habilidades — con candidatas duplicadas y una tanda descargando el modelo que
                    // la otra estaba usando.
                    Button("Cerrar") { dismiss() }
                        .disabled(isGenerating)
                }
            }
        }
    }

    @MainActor
    private func generateAllCandidates() async {
        errorMessage = ""
        failedTopicNames = []
        isGenerating = true
        generatedCount = 0
        totalCount = topics.count
        defer { isGenerating = false }

        do {
            // .light (no .medium): redactar una sola pregunta de opción múltiple a partir de un
            // nombre/detalle de habilidad ya conocido no necesita el modelo grande — a diferencia de
            // AcademyQuestionDraftService, que sí lo usa porque parte de texto OCR crudo. Además el
            // usuario revisa/descarta cada candidata igual, así que un modelo más chico es aceptable
            // y entra dentro del margen de RAM libre típico de esta máquina (los tiers de `.medium`
            // piden 39-51 GB libres con el margen de seguridad 1.5×, poco realista en uso normal).
            // isBatch: mantiene el modelo cargado entre las 38 llamadas. Recargarlo en cada vuelta
            // sería carísimo porque los modelos viven en un volumen externo.
            let backend = try await orchestrator.backend(for: .light, isBatch: true)
            for topic in topics {
                // Si ya tiene una candidata pendiente de una corrida anterior, no se vuelve a
                // generar — así, volver a tocar el botón reintenta solo lo que faltó o falló,
                // en lugar de repetir las 38 llamadas cada vez.
                guard topic.pendingCandidateQuestions.isEmpty else {
                    generatedCount += 1
                    continue
                }
                do {
                    let draft = try await SkillAssessmentQuestionDraftService.draftQuestion(for: topic, backend: backend)
                    topic.pendingCandidateQuestions.append(draft)
                } catch {
                    failedTopicNames.append(topic.name)
                }
                generatedCount += 1
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        // Libera el modelo apenas termina la tanda, en vez de dejarlo ocupando memoria hasta que
        // expire el keep-alive. Va fuera del `do` a propósito: tiene que correr también cuando la
        // generación falló a medio camino. No puede ir en un `defer` porque es asíncrono.
        await orchestrator.releaseLocalModels()
    }

    /// Recalcula la muestra rotativa de cada habilidad con candidatas aprobadas (en esta sesión o en
    /// alguna anterior) y marca el ciclo como cumplido. Las habilidades sin nada aprobado todavía
    /// conservan su `activeRotationQuestions` tal cual estaba (vacío en el primer mes).
    private func finishReview() {
        for topic in topics {
            // Solo se resortea donde efectivamente se aprobó algo en ESTA sesión. Antes se rehacía
            // la muestra de todas las habilidades con pool, lo que borraba las respuestas que el
            // usuario ya había marcado en la rotación vigente: como el botón "Preguntas nuevas" está
            // siempre disponible, bastaba entrar acá a mitad de una autoevaluación y salir para
            // perder lo respondido.
            guard approvedTopicIDs.contains(topic.id), !topic.approvedRotationPool.isEmpty else { continue }
            topic.activeRotationQuestions = RotationSampler.sample(
                from: topic.approvedRotationPool,
                count: topic.assessmentQuestions.count
            )
        }
        approvedTopicIDs.removeAll()
        lastQuestionRefreshDate = Date().timeIntervalSince1970
    }
}

private struct CandidateQuestionRow: View {
    @Bindable var topic: SkillTopic
    let index: Int
    @Binding var approvedTopicIDs: Set<UUID>

    /// `nil` en el instante entre borrar/aprobar una fila y que SwiftUI vuelva a evaluar `ForEach`
    /// sobre los índices ya actualizados — evita un crash por índice fuera de rango en ese hueco.
    private var candidate: AssessmentQuestion? {
        topic.pendingCandidateQuestions.indices.contains(index) ? topic.pendingCandidateQuestions[index] : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(
                "Enunciado",
                text: Binding(
                    get: { candidate?.question ?? "" },
                    set: { newValue in
                        guard topic.pendingCandidateQuestions.indices.contains(index) else { return }
                        topic.pendingCandidateQuestions[index].question = newValue
                    }
                ),
                axis: .vertical
            )
            .font(.body.weight(.medium))
            .textFieldStyle(.roundedBorder)
            .lineLimit(1...4)

            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array((candidate?.options ?? []).enumerated()), id: \.offset) { position, option in
                    HStack(alignment: .top, spacing: 8) {
                        // El puntaje se muestra explícitamente porque es lo que hay que revisar: en
                        // Técnica las 5 opciones deben ir de menor a mayor dominio (0→4), y en
                        // Teoría solo una debe valer 1. Sin verlo no se puede juzgar la candidata.
                        Text("\(option.points)")
                            .font(.caption.monospaced().weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 18, alignment: .trailing)
                        Text(option.text)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .accessibilityLabel("Opción \(position + 1), \(option.points) puntos: \(option.text)")
                }
            }
            .padding(.leading, 4)

            HStack {
                Button("Descartar", role: .destructive) {
                    guard topic.pendingCandidateQuestions.indices.contains(index) else { return }
                    topic.pendingCandidateQuestions.remove(at: index)
                }
                Spacer()
                Button("Aprobar") {
                    guard topic.pendingCandidateQuestions.indices.contains(index) else { return }
                    let approved = topic.pendingCandidateQuestions.remove(at: index)
                    topic.approvedRotationPool.append(approved)
                    approvedTopicIDs.insert(topic.id)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 8)
    }
}
