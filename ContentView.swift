import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable {
    case today = "Hoy"
    case search = "Buscar"
    case sessions = "Sesiones"
    case tasks = "Tareas"
    case lessons = "Clases"
    case materials = "Materiales"
    case library = "Biblioteca"
    case fretboard = "Mástil"
    case skills = "Habilidades"
    case academy = "Academia"
    case aiCoach = "Profesor IA"
    case repertoire = "Repertorio"
    case instruments = "Instrumentos"
    case studio = "Estudio"
    case recordings = "Grabaciones"
    case progress = "Progreso"
    case settings = "Configuración"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .today: "house.fill"
        case .search: "magnifyingglass"
        case .sessions: "clock.arrow.circlepath"
        case .tasks: "checklist"
        case .lessons: "graduationcap.fill"
        case .materials: "externaldrive.fill"
        case .library: "books.vertical.fill"
        case .fretboard: "guitars.fill"
        case .skills: "lightbulb.fill"
        case .academy: "brain.head.profile"
        case .aiCoach: "person.wave.2.fill"
        case .repertoire: "music.note.list"
        case .instruments: "guitars.fill"
        case .studio: "slider.horizontal.3"
        case .recordings: "waveform"
        case .progress: "chart.xyaxis.line"
        case .settings: "gearshape.fill"
        }
    }

    var group: SidebarGroup {
        switch self {
        case .today, .tasks, .lessons:
            .daily
        case .library, .fretboard, .skills, .academy, .repertoire:
            .learn
        case .aiCoach, .progress:
            .coaching
        case .search, .sessions, .materials, .instruments, .studio, .recordings, .settings:
            .more
        }
    }
}

enum SidebarGroup: String, CaseIterable, Identifiable {
    case daily = "Día a día"
    case learn = "Aprende"
    case coaching = "Acompañamiento"
    case more = "Más"

    var id: String { rawValue }
}

struct ContentView: View {
    @Environment(AppNavigator.self) private var navigator
    @State private var expandedGroups: Set<SidebarGroup> = [.daily, .learn, .coaching]

    private var platformBackground: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    var body: some View {
        @Bindable var navigator = navigator
        let selectionBinding = Binding<SidebarSection?>(
            get: { navigator.selection },
            set: { navigator.selection = $0 ?? .today }
        )
        NavigationSplitView {
            List(selection: selectionBinding) {
                ForEach(SidebarGroup.allCases) { group in
                    let sections = SidebarSection.allCases.filter { $0.group == group }
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { expandedGroups.contains(group) },
                            set: { isExpanded in
                                if isExpanded {
                                    expandedGroups.insert(group)
                                } else {
                                    expandedGroups.remove(group)
                                }
                            }
                        )
                    ) {
                        ForEach(sections) { section in
                            Label(section.rawValue, systemImage: section.icon)
                                .tag(section)
                                .padding(.vertical, 4)
                        }
                    } label: {
                        Text(group.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .top, spacing: 0) {
                SidebarBrand()
            }
            .navigationTitle("Practice Lab")
            .navigationSplitViewColumnWidth(min: 170, ideal: 205)
        } detail: {
            Group {
                switch navigator.selection {
                case .today: DashboardView()
                case .search: GlobalSearchView()
                case .sessions: SessionsView()
                case .tasks: TasksView()
                case .lessons: LessonsView()
                case .materials: LearningMaterialsView()
                case .library: LibraryView()
                case .fretboard: FretboardTrainerView()
                case .skills: SkillsView()
                case .academy: AcademyView()
                case .aiCoach: AIStudioView()
                case .repertoire: RepertoireView()
                case .instruments: InstrumentsView()
                case .studio: StudioView()
                case .recordings: RecordingsView()
                case .progress: ProgressOverviewView()
                case .settings: SettingsView()
                }
            }
            .background {
                LinearGradient(
                    colors: [platformBackground, PracticeTheme.accent.opacity(0.035)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(PracticeTheme.accent)
        // Conteo local de uso por sección — ver `SectionUsageTracker`. Solo cuenta cambios reales
        // de selección, no cada recomposición.
        .onChange(of: navigator.selection) { _, section in
            expandedGroups.insert(section.group)
            SectionUsageTracker.recordOpen(section.rawValue)
        }
        .onAppear {
            expandedGroups.insert(navigator.selection.group)
            SectionUsageTracker.recordInitialOpenIfNeeded(navigator.selection.rawValue)
        }
    }
}

private struct SidebarBrand: View {
    var body: some View {
        HStack(spacing: 10) {
            Image("BrandIcon")
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .aspectRatio(contentMode: .fit)
                .frame(width: 34, height: 34)
                .shadow(color: PracticeTheme.accent.opacity(0.22), radius: 4, y: 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("Practice Lab")
                    .font(.headline.weight(.semibold))
                Text("TU ESPACIO DE PRÁCTICA")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .tracking(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(PracticeTheme.windowSurface.opacity(0.86))
    }
}
