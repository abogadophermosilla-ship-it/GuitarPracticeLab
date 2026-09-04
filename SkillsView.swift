import SwiftUI
import SwiftData

struct SkillsView: View {
    @Query(sort: \SkillTopic.name) private var topics: [SkillTopic]
    @AppStorage("overallGuitaristLevel") private var overallGuitaristLevel = ""
    @AppStorage("overallLevelBand") private var overallLevelBand = ""
    @AppStorage("overallLevelPercentage") private var overallLevelPercentage = 0.0
    @AppStorage(SkillAudioAssessmentSchedule.completionKey) private var hasCompletedAudioAssessment = false
    @State private var domain: SkillDomain = .technique
    @State private var selectedID: UUID?
    @State private var showingAssessment = false
    @State private var showingAudioAssessment = false
    @State private var showingFlashcards = false

    private var filtered: [SkillTopic] { topics.filter { $0.domain == domain } }

    private func topics(for band: DifficultyBand) -> [SkillTopic] {
        filtered.filter { DifficultyClassifier.assess(skillNamed: $0.name).rating.band == band }
    }

    private var selectedTopic: SkillTopic? {
        topics.first { $0.id == selectedID } ?? filtered.first
    }

    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    skillsTitle
                    Spacer()
                    skillsControls
                }
                VStack(alignment: .leading, spacing: 10) {
                    skillsTitle
                    skillsControls
                }
            }
            .padding(20)

            if let studentRating = StudentLevelService.rating(forPercentage: overallLevelPercentage) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Nivel estimado por el Test Integral")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Spacer()
                        DifficultyBadge(rating: studentRating)
                    }
                    if !overallGuitaristLevel.isEmpty {
                        Text(overallGuitaristLevel)
                            .font(.callout)
                    }
                }
                .padding(10)
                .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }

            // No anidar otro NavigationSplitView dentro del que ya usa ContentView. En ventanas
            // medianas macOS colapsaba automáticamente la barra lateral principal para intentar
            // acomodar las tres columnas (menú de la app + lista de habilidades + detalle).
            HStack(spacing: 0) {
                List(selection: $selectedID) {
                    ForEach(DifficultyBand.allCases) { band in
                        let items = topics(for: band)
                        if !items.isEmpty {
                            Section("\(band.rawValue)★ · \(band.name)") {
                                ForEach(items) { topic in
                                    SkillTopicRow(topic: topic).tag(topic.id)
                                }
                            }
                        }
                    }
                }
                .frame(minWidth: 240, idealWidth: 300, maxWidth: 360)

                Divider()

                Group {
                    if let topic = selectedTopic {
                        SkillTopicDetailView(topic: topic)
                    } else {
                        EmptyStateView(icon: "lightbulb", title: "Sin elementos", message: "No hay técnicas o teoría registradas.")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { selectedID = selectedID ?? filtered.first?.id }
        .onChange(of: domain) { _, _ in selectedID = filtered.first?.id }
        .sheet(isPresented: $showingAssessment) {
            SkillAssessmentView()
                .frame(minWidth: 560, idealWidth: 680, minHeight: 540)
        }
        .sheet(isPresented: $showingAudioAssessment) {
            SkillAudioAssessmentView(mode: hasCompletedAudioAssessment ? .monthly : .initial)
                .frame(minWidth: 620, idealWidth: 760, minHeight: 600)
        }
        .sheet(isPresented: $showingFlashcards) {
            TheoryFlashcardsView()
                .frame(minWidth: 500, idealWidth: 560, minHeight: 520)
        }
    }

    private var skillsTitle: some View {
        VStack(alignment: .leading) {
            Text("Habilidades")
                .font(.largeTitle.bold())
            Text("Mapa de conocimiento, ejecución, aplicación, transferencia y retención")
                .foregroundStyle(.secondary)
        }
    }

    private var skillsControls: some View {
        HStack {
            if domain == .theory {
                Button("Flashcards", systemImage: "rectangle.on.rectangle") { showingFlashcards = true }
            }
            if domain == .technique {
                Button("Evaluación práctica", systemImage: "waveform.badge.mic") {
                    showingAudioAssessment = true
                }
                .accessibilityIdentifier("skills.audioAssessment")
            }
            Button("Autoevaluación", systemImage: "checklist") { showingAssessment = true }
            Picker("Área", selection: $domain) {
                ForEach(SkillDomain.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 190)
        }
    }
}

private struct SkillTopicRow: View {
    let topic: SkillTopic

    private var assessment: DifficultyAssessment { DifficultyClassifier.assess(skillNamed: topic.name) }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(topic.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(topic.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            DifficultyBadge(rating: assessment.rating)
            StatusPill(text: topic.status.rawValue, tint: statusColor(topic.status))
                .fixedSize()
        }
        .padding(.vertical, 3)
    }

    private func statusColor(_ status: SkillMasteryLevel) -> Color {
        switch status {
        case .consolidated: .green
        case .advanced, .intermediate: .blue
        case .basic: .purple
        default: .orange
        }
    }
}

private struct SkillTopicDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var topic: SkillTopic
    @Query(sort: \SkillTopic.name) private var allTopics: [SkillTopic]
    @Query(sort: \SkillEvidence.occurredAt, order: .reverse) private var allEvidence: [SkillEvidence]
    @Query(sort: \Song.title) private var songs: [Song]
    @State private var showingTimer = false
    @State private var timerTaskID: UUID?

    /// Los ejercicios vinculados y la evidencia de catálogo se resuelven contra el catálogo entero.
    private var exercises: [LibraryExercise] {
        LibraryLookup.Catalog.shared.exercises(in: modelContext)
    }

    private var linkedSongs: [Song] {
        songs.filter { $0.linkedSkillIDs.contains(topic.id) }
    }

    private var linkedExercises: [LibraryExercise] {
        SkillAssessmentCoachService.matchingExercises(for: topic, exercises: exercises)
    }

    private var catalogEvidence: (ratio: Double, count: Int)? {
        SkillAssessmentCoachService.practiceEvidence(for: topic, songs: songs, exercises: exercises)
    }

    private var evidence: [SkillEvidence] {
        allEvidence.filter { $0.skillID == topic.id }
    }

    private var profile: SkillProfile {
        SkillMasteryEngine.profile(for: topic, evidence: evidence)
    }

    private var prerequisites: [SkillTopic] {
        SkillGraphService.prerequisites(for: topic, among: allTopics)
    }

    private var difficultyAssessment: DifficultyAssessment {
        DifficultyClassifier.assess(skillNamed: topic.name)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: topic.domain == .technique ? "hand.raised.fingers.spread" : "book.closed.fill")
                        .font(.largeTitle)
                        .foregroundStyle(topic.domain == .technique ? .blue : .indigo)
                        .frame(width: 60, height: 60)
                        .background((topic.domain == .technique ? Color.blue : Color.indigo).opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(topic.domain.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(topic.name)
                            .font(.title2.bold())
                    }
                }

                Divider()
                DifficultySummaryView(assessment: difficultyAssessment)
                    .padding(12)
                    .background(difficultyAssessment.rating.color.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                Text(topic.detail)
                    .font(.callout)

                Picker("Dominio demostrado", selection: Binding(
                    get: { topic.status },
                    set: { newValue in
                        let previous = topic.status
                        topic.status = newValue
                        topic.statusIsManual = true
                        ProgressTracker.recordIfLevelUp(
                            itemName: topic.name,
                            category: topic.domain == .theory ? .theory : .technique,
                            previousLabel: previous.rawValue,
                            previousWeight: previous.progressWeight,
                            newLabel: newValue.rawValue,
                            newWeight: newValue.progressWeight,
                            in: modelContext
                        )
                        BadgeEvaluator.evaluate(context: modelContext)
                    }
                )) {
                    ForEach(SkillMasteryLevel.allCases) { Text($0.rawValue).tag($0) }
                }
                if topic.statusIsManual {
                    Text("Elegido a mano — el perfil conserva las evidencias, pero no cambia esta banda hasta que termines una autoevaluación nueva.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Perfil de dominio")
                            .font(.headline)
                        Spacer()
                        StatusPill(text: "Confianza \(profile.confidence.rawValue.lowercased())", tint: profile.confidence.color)
                    }
                    HStack(spacing: 18) {
                        LabeledContent("Test", value: (topic.testStatus ?? SkillAssessmentCoachService.computeStatus(for: topic))?.rawValue ?? "Sin medir")
                        LabeledContent("Demostrado", value: profile.demonstratedLevel.rawValue)
                    }
                    .font(.callout)

                    ForEach(profile.dimensions) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Label(item.dimension.rawValue, systemImage: item.dimension.icon)
                                    .font(.caption.weight(.medium))
                                Spacer()
                                Text(item.evidenceCount == 0 ? "Sin comprobar" : "\(Int(item.score * 100))% · \(item.evidenceCount) evidencia\(item.evidenceCount == 1 ? "" : "s")")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            ProgressView(value: item.score)
                                .tint(item.dimension.color)
                        }
                    }

                    if !prerequisites.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Prerrequisitos")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            ForEach(prerequisites) { prerequisite in
                                HStack {
                                    Image(systemName: prerequisite.status.progressWeight >= SkillMasteryLevel.intermediate.progressWeight
                                          ? "checkmark.circle.fill" : "exclamationmark.circle")
                                        .foregroundStyle(prerequisite.status.progressWeight >= SkillMasteryLevel.intermediate.progressWeight ? .green : .orange)
                                    Text(prerequisite.name)
                                        .font(.caption)
                                    Spacer()
                                    Text(prerequisite.status.rawValue)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Siguiente evidencia: \(profile.nextDimension.rawValue)")
                                .font(.callout.weight(.medium))
                            Text("La app elegirá un reto breve usando tu biblioteca o repertorio cuando sea posible.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Comprobar ahora", systemImage: "play.circle.fill") {
                            createChallengeAndStart()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(14)
                .background(.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))

                if !topic.resource.isEmpty {
                    Divider()
                    Text("Recurso recomendado")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text(topic.resource)
                        .font(.callout)
                }

                if !topic.concept.isEmpty || !topic.correctExecution.isEmpty || !topic.commonErrors.isEmpty {
                    Divider()
                    if !topic.concept.isEmpty {
                        guideSection(title: "Concepto", text: topic.concept)
                    }
                    if !topic.correctExecution.isEmpty {
                        guideSection(title: "Ejecución correcta", text: topic.correctExecution)
                    }
                    if !topic.commonErrors.isEmpty {
                        guideSection(title: "Errores frecuentes", text: topic.commonErrors)
                    }
                }

                if !linkedSongs.isEmpty || !linkedExercises.isEmpty {
                    Divider()
                    HStack {
                        Text("Evidencia práctica")
                            .font(.headline)
                        Spacer()
                        if let catalogEvidence {
                            StatusPill(text: "\(String(format: "%.0f", catalogEvidence.ratio * 100))%", tint: .green)
                        }
                    }
                    Text("Canciones y ejercicios ya trabajados que refuerzan esta habilidad y ayudan a determinar tu nivel real, junto con el Test Integral.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(linkedSongs) { song in
                        HStack {
                            Image(systemName: "music.note").foregroundStyle(.green)
                            Text(song.title).font(.callout)
                            Spacer()
                            StatusPill(text: song.status.rawValue, tint: .blue).fixedSize()
                        }
                    }
                    ForEach(linkedExercises) { exercise in
                        HStack {
                            Image(systemName: "book.closed.fill").foregroundStyle(.blue)
                            Text(exercise.displayName).font(.callout).lineLimit(1)
                            Spacer()
                            StatusPill(text: exercise.status.rawValue, tint: .blue).fixedSize()
                        }
                    }
                }

                if !topic.assessmentQuestions.isEmpty {
                    Divider()
                    Text("Preguntas de autoevaluación (\(topic.assessmentQuestions.count))")
                        .font(.headline)
                    ForEach(Array(topic.assessmentQuestions.enumerated()), id: \.offset) { index, question in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(question.question)
                                .font(.callout.weight(.medium))
                            MultipleChoiceOptions(
                                options: question.options,
                                selectedIndex: Binding(
                                    get: { topic.assessmentQuestions[index].selectedIndex },
                                    set: { newValue in
                                        topic.assessmentQuestions[index].selectedIndex = newValue
                                        recomputeStatus()
                                    }
                                )
                            )
                        }
                        .padding(.vertical, 6)
                        if index != topic.assessmentQuestions.count - 1 { Divider() }
                    }
                }

                Text("Notas")
                    .font(.headline)
                TextEditor(text: $topic.notes)
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(24)
        }
        .sheet(isPresented: $showingTimer) {
            PracticeTimerView(initialTaskID: timerTaskID)
                .frame(minWidth: 500, idealWidth: 580, minHeight: 540)
        }
    }

    /// Recalcula el nivel al responder una pregunta puntual acá — antes solo se recalculaba al
    /// terminar la Autoevaluación completa, así que reeditar una pregunta desde el detalle de la
    /// habilidad quedaba guardado pero sin mover el pill de estado hasta la próxima vez que se
    /// corriera el test entero. Igual que terminar una autoevaluación completa, responder una
    /// pregunta acá es una señal explícita sobre el Test Integral — vuelve a tomar el control aunque
    /// haya un ajuste manual previo (`statusIsManual`).
    private func recomputeStatus() {
        let testStatus = SkillAssessmentCoachService.computeStatus(for: topic)
        guard testStatus != nil else { return }
        topic.statusIsManual = false
        topic.testStatus = testStatus
        SkillEvidenceService.recordAssessment(for: topic, runID: topic.id, in: modelContext)
        BadgeEvaluator.evaluate(context: modelContext)
    }

    private func createChallengeAndStart() {
        let candidate = SkillChallengeBuilder.makeTask(
            for: topic,
            profile: profile,
            exercises: exercises,
            songs: songs
        )
        let resolution = PracticeTaskDeduplication.resolve(
            candidateTitle: candidate.title,
            candidateExerciseTitle: candidate.exerciseTitle,
            candidateSourceKind: candidate.sourceKind,
            candidateSourceID: candidate.sourceID,
            in: modelContext
        )
        switch resolution {
        case .keepExisting(let existing):
            timerTaskID = existing.id
        case .replaceExisting(let existing):
            modelContext.delete(existing)
            modelContext.insert(candidate)
            timerTaskID = candidate.id
        case .none:
            modelContext.insert(candidate)
            timerTaskID = candidate.id
        }
        try? modelContext.save()
        showingTimer = true
    }

    private func guideSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
        }
    }
}
