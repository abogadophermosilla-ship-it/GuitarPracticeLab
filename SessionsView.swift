import SwiftUI
import SwiftData

struct SessionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppNavigator.self) private var navigator
    @Query(sort: \PracticeSession.date, order: .reverse) private var sessions: [PracticeSession]
    @State private var showingNewSession = false
    @State private var sessionToEdit: PracticeSession?
    @State private var searchText = ""
    @State private var selectedDate: Date?
    @State private var showingDatePicker = false

    private var filteredSessions: [PracticeSession] {
        var result = sessions
        if let selectedDate {
            result = result.filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
        }
        guard !searchText.isEmpty else { return result }
        return result.filter {
            $0.exerciseTitle.localizedCaseInsensitiveContains(searchText) ||
            $0.sourceTitle.localizedCaseInsensitiveContains(searchText) ||
            $0.instrumentName.localizedCaseInsensitiveContains(searchText) ||
            $0.categoryRaw.localizedCaseInsensitiveContains(searchText) ||
            $0.notes.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Sesiones")
                        .font(.largeTitle.bold())
                    Text("Historial completo de tu práctica")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showingDatePicker = true
                } label: {
                    Image(systemName: selectedDate == nil ? "calendar" : "calendar.badge.checkmark")
                }
                .buttonStyle(.bordered)
                .help("Filtrar por día")
                Button("Nueva sesión", systemImage: "plus") { showingNewSession = true }
                    .buttonStyle(.borderedProminent)
            }
            .padding(24)

            if let selectedDate {
                HStack {
                    StatusPill(text: selectedDate.formatted(date: .abbreviated, time: .omitted), tint: .blue)
                    Button {
                        self.selectedDate = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }

            if filteredSessions.isEmpty {
                EmptyStateView(
                    icon: "clock",
                    title: "No hay sesiones",
                    message: selectedDate == nil && searchText.isEmpty
                        ? "Registra tu primera sesión de práctica."
                        : "Ninguna sesión coincide con el filtro."
                )
            } else {
                List {
                    ForEach(PracticeBucket.allCases) { bucket in
                        let items = filteredSessions.filter { PracticeBucket.bucket(for: $0.category) == bucket }
                        if !items.isEmpty {
                            Section(bucket.rawValue) {
                                ForEach(items) { session in
                                    SessionRow(
                                        session: session,
                                        onOpenSource: session.sourceKind == .manual ? nil : {
                                            navigator.go(to: session.sourceKind, id: session.sourceID)
                                        }
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture { sessionToEdit = session }
                                    .contextMenu {
                                        Button("Editar", systemImage: "pencil") { sessionToEdit = session }
                                        Button("Eliminar", systemImage: "trash", role: .destructive) {
                                            SkillEvidenceService.removeEvidence(for: session, in: modelContext)
                                            modelContext.delete(session)
                                        }
                                    }
                                }
                                .onDelete { offsets in delete(items: items, at: offsets) }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .searchable(text: $searchText, prompt: "Buscar sesiones")
        .sheet(isPresented: $showingNewSession) {
            NewSessionView()
                .frame(minWidth: 540, idealWidth: 660, minHeight: 540)
        }
        .sheet(item: $sessionToEdit) { session in
            NewSessionView(sessionToEdit: session)
                .frame(minWidth: 540, idealWidth: 660, minHeight: 540)
        }
        .sheet(isPresented: $showingDatePicker) {
            VStack(spacing: 16) {
                Text("Filtrar por día")
                    .font(.headline)
                DatePicker(
                    "Fecha",
                    selection: Binding(get: { selectedDate ?? .now }, set: { selectedDate = $0 }),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                HStack {
                    Button("Quitar filtro", role: .destructive) {
                        selectedDate = nil
                        showingDatePicker = false
                    }
                    .disabled(selectedDate == nil)
                    Spacer()
                    Button("Listo") { showingDatePicker = false }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
            .frame(minWidth: 360)
        }
    }

    private func delete(items: [PracticeSession], at offsets: IndexSet) {
        for index in offsets {
            SkillEvidenceService.removeEvidence(for: items[index], in: modelContext)
            modelContext.delete(items[index])
        }
    }
}

private struct SessionRow: View {
    let session: PracticeSession
    var onOpenSource: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 14) {
            VStack {
                Text(session.date.formatted(.dateTime.day()))
                    .font(.title2.bold())
                Text(session.date.formatted(.dateTime.month(.abbreviated)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 48)

            Image(systemName: session.category.icon)
                .font(.title3)
                .foregroundStyle(session.category.color)
                .frame(width: 38, height: 38)
                .background(session.category.color.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(session.exerciseTitle.isEmpty ? session.category.rawValue : session.exerciseTitle)
                    .font(.headline)
                Text([session.sourceTitle, session.instrumentName].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !session.notes.isEmpty {
                    Text(session.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if session.rhythmicFigure.isSpecified {
                StatusPill(text: session.rhythmicFigure.displayName, tint: session.category.color)
            }
            if let dimension = session.evidenceDimension {
                StatusPill(text: dimension.rawValue, tint: dimension.color)
            }
            if session.endBPM > 0 {
                StatusPill(text: "\(session.startBPM) → \(session.endBPM) BPM", tint: session.category.color)
            }
            VStack(alignment: .trailing, spacing: 4) {
                Text(session.formattedDuration)
                    .font(.headline.monospacedDigit())
                if session.repertoireRepetitions > 0 {
                    Text("\(session.repertoireRepetitions) pasada\(session.repertoireRepetitions == 1 ? "" : "s")")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(session.result.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let onOpenSource {
                Button { onOpenSource() } label: {
                    Image(systemName: session.sourceKind.icon)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(session.sourceKind.label)
            }
        }
        .padding(.vertical, 7)
    }
}
