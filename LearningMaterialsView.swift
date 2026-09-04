import SwiftUI

struct LearningMaterialsView: View {
    @AppStorage(LearningMaterialsService.rootPathKey)
    private var configuredRoot = LearningMaterialsService.defaultRootPath

    @State private var topLevelFolders: [LearningMaterialEntry] = []
    @State private var currentFolder = LearningMaterialsService.rootURL
    @State private var entries: [LearningMaterialEntry] = []
    @State private var selectedTopLevelID: String?
    @State private var history: [URL] = []

    private var isConnected: Bool { LearningMaterialsService.isAvailable }

    var body: some View {
        VStack(spacing: 0) {
            responsiveHeader
                .padding(20)

            Divider()

            if isConnected {
                NavigationSplitView {
                    List(topLevelFolders, selection: $selectedTopLevelID) { entry in
                        Label(entry.name, systemImage: entry.icon)
                            .tag(entry.id)
                    }
                    .navigationTitle("Áreas")
                    .navigationSplitViewColumnWidth(min: 190, ideal: 230)
                    .onChange(of: selectedTopLevelID) { _, newValue in
                        guard let folder = topLevelFolders.first(where: { $0.id == newValue }) else { return }
                        history = []
                        show(folder.url)
                    }
                } detail: {
                    folderContents
                }
            } else {
                EmptyStateView(
                    icon: "externaldrive.badge.exclamationmark",
                    title: "Disco externo desconectado",
                    message: "Conecta VST o elige otra raíz en Configuración. Nada fue movido al disco interno."
                )
            }
        }
        .navigationTitle("Materiales")
        .task(id: configuredRoot) { reloadRoot() }
    }

    private var responsiveHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 16) {
                title
                Spacer()
                sourceStatus
                headerActions
            }
            VStack(alignment: .leading, spacing: 12) {
                title
                HStack {
                    sourceStatus
                    Spacer()
                    headerActions
                }
            }
        }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Materiales de aprendizaje")
                .font(.largeTitle.bold())
            Text("Todo permanece en el disco externo; la app solo lo organiza y abre.")
                .foregroundStyle(.secondary)
        }
    }

    private var sourceStatus: some View {
        Label(
            isConnected ? LearningMaterialsService.rootURL.path : "Fuente desconectada",
            systemImage: isConnected ? "externaldrive.fill.badge.checkmark" : "externaldrive.badge.xmark"
        )
        .font(.caption)
        .foregroundStyle(isConnected ? .green : .orange)
        .lineLimit(1)
        .truncationMode(.middle)
    }

    private var headerActions: some View {
        HStack {
            Button("Actualizar", systemImage: "arrow.clockwise") { reloadRoot() }
            Button("Abrir en Finder", systemImage: "folder") {
                LearningMaterialsService.open(LearningMaterialsService.rootURL)
            }
            .disabled(!isConnected)
        }
        .fixedSize()
    }

    private var folderContents: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    goBack()
                } label: {
                    Label("Atrás", systemImage: "chevron.left")
                }
                .disabled(history.isEmpty)

                VStack(alignment: .leading, spacing: 2) {
                    Text(currentFolder.lastPathComponent)
                        .font(.headline)
                    Text(relativePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text("\(entries.count) elementos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Abrir carpeta", systemImage: "folder") {
                    LearningMaterialsService.open(currentFolder)
                }
            }
            .padding(16)

            Divider()

            if entries.isEmpty {
                EmptyStateView(icon: "folder", title: "Carpeta vacía", message: "No hay materiales visibles en esta carpeta.")
            } else {
                List(entries) { entry in
                    Button {
                        if entry.isDirectory {
                            history.append(currentFolder)
                            show(entry.url)
                        } else {
                            LearningMaterialsService.open(entry.url)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: entry.icon)
                                .font(.title3)
                                .foregroundStyle(entry.isDirectory ? .blue : .secondary)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.name)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                HStack(spacing: 8) {
                                    Text(entry.detail)
                                    if let date = entry.modifiedAt {
                                        Text("· \(date.formatted(date: .abbreviated, time: .omitted))")
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: entry.isDirectory ? "chevron.right" : "arrow.up.forward.app")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Abrir", systemImage: "arrow.up.forward.app") {
                            if entry.isDirectory {
                                history.append(currentFolder)
                                show(entry.url)
                            } else {
                                LearningMaterialsService.open(entry.url)
                            }
                        }
                        Button("Mostrar en Finder", systemImage: "folder") {
                            LearningMaterialsService.open(entry.url.deletingLastPathComponent())
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var relativePath: String {
        let root = LearningMaterialsService.rootURL.path
        let current = currentFolder.path
        guard current.hasPrefix(root) else { return current }
        let suffix = String(current.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return suffix.isEmpty ? "Raíz" : suffix
    }

    private func reloadRoot() {
        let root = LearningMaterialsService.rootURL
        currentFolder = root
        history = []
        let rootEntries = LearningMaterialsService.entries(in: root)
        topLevelFolders = rootEntries.filter(\.isDirectory)
        entries = rootEntries
        selectedTopLevelID = nil
    }

    private func show(_ folder: URL) {
        currentFolder = folder
        entries = LearningMaterialsService.entries(in: folder)
    }

    private func goBack() {
        guard let previous = history.popLast() else { return }
        show(previous)
        if previous.standardizedFileURL == LearningMaterialsService.rootURL.standardizedFileURL {
            selectedTopLevelID = nil
        }
    }
}
