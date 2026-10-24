import SCTVCore
import SCTVFeatures
import SCTVMedia
import SwiftUI

private enum WorkspaceSection: String, CaseIterable, Identifiable {
    case catalogue = "栏目"
    case library = "资料库"
    case downloads = "下载"
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .catalogue: "square.grid.2x2"
        case .library: "books.vertical"
        case .downloads: "arrow.down.circle"
        }
    }
}

struct WorkspaceView: View {
    let dependencies: AppDependencies
    private let actions: ProgrammeActions

    @State private var catalogue: CatalogueModel
    @State private var library: LibraryModel
    @State private var downloads: DownloadsModel
    @State private var sharing: FileSharingController
    @State private var player: PlayerSession
    @State private var playerLifetime: PlayerPresentationLifetime

    @State private var selection: WorkspaceSection? = .catalogue
    @SceneStorage("workspace.tab") private var selectedTabName = "栏目"
    @SceneStorage("workspace.cataloguePath") private var savedCataloguePath = Data()
    @SceneStorage("workspace.libraryPath") private var savedLibraryPath = Data()
    @SceneStorage("workspace.catalogueSort") private var savedAlphabetical = false

    @State private var restoredPaths = false
    @State private var cataloguePath: [WorkspaceRoute] = []
    @State private var libraryPath: [WorkspaceRoute] = []
    @State private var downloadsPath: [PlayerPresentation] = []
    @State private var showingSettings = false
    @State private var message: String?

    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var phase
    #if os(macOS)
        @Environment(\.openSettings) private var openSettings
    #endif

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        actions = ProgrammeActions(dependencies: dependencies)

        _catalogue = State(
            initialValue: CatalogueModel(
                repository: dependencies.programmes, favourites: dependencies.favourites))
        _library = State(initialValue: LibraryModel(repository: dependencies.history))
        _downloads = State(initialValue: DownloadsModel(service: dependencies.downloads.service))
        _sharing = State(initialValue: FileSharingController(downloads: dependencies.downloads))
        _player = State(initialValue: dependencies.player)
        _playerLifetime = State(
            initialValue: PlayerPresentationLifetime(session: dependencies.player))
    }

    var body: some View {
        Group {
            #if os(macOS)
                NavigationSplitView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(spacing: 12) {
                            Image(systemName: "play.rectangle.fill")
                                .font(.title).foregroundStyle(
                                    PresentationStyle.accent(colorScheme ?? systemScheme))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("SCTV").font(.system(.title2, design: .serif, weight: .bold))
                                Text("好节目，随时回看").font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.horizontal, 20).padding(.top, 28)
                        ScrollView {
                            VStack(spacing: 6) {
                                ForEach(WorkspaceSection.allCases) { item in
                                    Button {
                                        selection = item
                                    } label: {
                                        Label(item.rawValue, systemImage: item.symbol)
                                            .font(.headline)
                                            .foregroundStyle(
                                                selection == item
                                                    ? PresentationStyle.accent(
                                                        colorScheme ?? systemScheme) : .primary
                                            )
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.horizontal, 14).padding(.vertical, 13)
                                            .background(
                                                selection == item
                                                    ? PresentationStyle.accent(
                                                        colorScheme ?? systemScheme
                                                    ).opacity(0.12) : .clear,
                                                in: RoundedRectangle(cornerRadius: 12)
                                            )
                                            .contentShape(Rectangle())
                                    }.buttonStyle(.plain)
                                        .accessibilityAddTraits(
                                            selection == item ? .isSelected : [])
                                }
                            }.padding(.horizontal, 12)
                        }
                        Button {
                            openSettings()
                        } label: {
                            Label("设置", systemImage: "gearshape")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(20)
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
                } detail: {
                    switch selection ?? .catalogue {
                    case .catalogue: catalogueNavigation
                    case .library: libraryNavigation
                    case .downloads: downloadsNavigation
                    }
                }
            #else
                TabView(
                    selection: Binding(
                        get: { WorkspaceSection(rawValue: selectedTabName) ?? .catalogue },
                        set: { selectedTabName = $0.rawValue })
                ) {
                    Tab("栏目", systemImage: "square.grid.2x2", value: WorkspaceSection.catalogue) {
                        catalogueNavigation
                    }
                    Tab("资料库", systemImage: "books.vertical", value: WorkspaceSection.library) {
                        libraryNavigation
                    }
                    Tab("下载", systemImage: "arrow.down.circle", value: WorkspaceSection.downloads) {
                        downloadsNavigation
                    }
                }.tabViewStyle(.tabBarOnly)
            #endif
        }
        .tint(PresentationStyle.accent(colorScheme ?? systemScheme))
        .preferredColorScheme(colorScheme)
        .onChange(of: sharing.warning) { _, value in
            if let value {
                message = value
                sharing.warning = nil
            }
        }
        .task { await loadWorkspace() }
        .onChange(of: selection) { _, value in if let value { selectedTabName = value.rawValue } }
        .onChange(of: catalogue.hasAcceptedSnapshot) { _, accepted in
            if accepted { restoreNavigationIfNeeded() }
        }
        .onChange(of: cataloguePath) { _, value in
            savedCataloguePath =
                (try? JSONEncoder().encode(value.compactMap(\.programmeID))) ?? Data()
        }
        .onChange(of: libraryPath) { _, value in
            savedLibraryPath =
                (try? JSONEncoder().encode(value.compactMap(\.programmeID))) ?? Data()
        }
        .onChange(of: catalogue.alphabetical) { _, value in savedAlphabetical = value }
        .onChange(of: phase) { _, value in
            if value != .active { Task { await dependencies.settings.flush() } }
        }
        .alert(
            "提示", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })
        ) {
            Button("好") { message = nil }
        } message: {
            Text(message ?? "")
        }
        #if os(iOS)
            .sheet(isPresented: $showingSettings) {
                NavigationStack {
                    ApplicationSettingsView(dependencies: dependencies).toolbar {
                        Button("完成", systemImage: "checkmark") { showingSettings = false }
                        .labelStyle(.iconOnly).help("完成")
                    }
                }
                .tint(PresentationStyle.accent(colorScheme ?? systemScheme))
            }
            .sheet(item: $sharing.sharing) { FileShareView(file: $0) }
        #endif
    }

    private func loadWorkspace() async {
        catalogue.alphabetical = savedAlphabetical
        selection = WorkspaceSection(rawValue: selectedTabName) ?? .catalogue
        await dependencies.settings.load()
    }

    private func restoreNavigationIfNeeded() {
        guard !restoredPaths else { return }

        restoredPaths = true
        cataloguePath = restore(savedCataloguePath)
        libraryPath = restore(savedLibraryPath)
    }

    private func presentSettings() {
        #if os(macOS)
            openSettings()
        #else
            showingSettings = true
        #endif
    }

    private var catalogueNavigation: some View {
        NavigationStack(path: $cataloguePath) {
            CatalogueView(model: catalogue, settings: presentSettings) {
                cataloguePath.append(.archive($0))
            }
            .navigationDestination(for: WorkspaceRoute.self) {
                destination($0, section: .catalogue)
            }
        }
    }

    private var libraryNavigation: some View {
        NavigationStack(path: $libraryPath) {
            LibraryView(
                model: library, catalogue: catalogue,
                play: { play(.history($0), section: .library) },
                open: { libraryPath.append(.archive($0)) },
                showHistory: { libraryPath.append(.history) },
                settings: presentSettings
            ).navigationDestination(for: WorkspaceRoute.self) { destination($0, section: .library) }
        }
    }

    private var downloadsNavigation: some View {
        NavigationStack(path: $downloadsPath) {
            DownloadsView(
                model: downloads,
                play: { play(.download($0), section: .downloads) },
                export: { task in Task { await sharing.export(task) } },
                reveal: { task in Task { await sharing.reveal(task) } },
                reauthorize: { task in Task { await sharing.reauthorize(task) } }
            )
            .navigationDestination(for: PlayerPresentation.self) { playerPage($0) }
        }
    }

    private func play(_ selection: PlaybackSelection, section: WorkspaceSection) {
        // Capture the request token at tap time so delayed preparation cannot replace a newer tap.
        let requestID = player.reservePlaybackRequest()
        Task {
            do {
                let request = try await actions.playbackRequest(for: selection)
                await present(request, requestID: requestID, section: section)
            } catch {
                if player.isCurrentRequest(requestID) { message = error.localizedDescription }
                await actions.recoverAfterPlaybackFailure(for: selection)
            }
        }
    }

    private func archive(_ programme: Programme, section: WorkspaceSection) -> some View {
        ArchiveDestination(
            programme: programme, repository: dependencies.programmes, catalogue: catalogue,
            play: { content, date in
                play(.archive(content, programme: programme, broadcast: date), section: section)
            },
            download: { contents, date in
                download(contents, programme: programme, broadcast: date)
            })
    }

    private func download(
        _ contents: [ProgrammeContent], programme: Programme, broadcast: BroadcastDate
    ) {
        Task {
            message = await actions.startDownloads(
                contents, programme: programme, broadcast: broadcast)
        }
    }

    private func present(_ request: PlaybackRequest, requestID: UUID, section: WorkspaceSection)
        async
    {
        guard let presentationID = player.beginPresentation(forRequest: requestID) else { return }

        #if os(macOS)
            openWindow(id: "player")
        #else
            let presentation = PlayerPresentation(id: presentationID, section: section)
            playerLifetime.takeOwnership(of: presentationID)
            // The shared session has one destination, even when a tab retains its stack.
            cataloguePath.removeAll { $0.isPlayback }
            libraryPath.removeAll { $0.isPlayback }
            downloadsPath.removeAll()
            switch section {
            case .catalogue: cataloguePath.append(.player(presentation))
            case .library: libraryPath.append(.player(presentation))
            case .downloads: downloadsPath.append(presentation)
            }
        #endif

        await player.open(request, forPresentation: presentationID)
    }

    @ViewBuilder private func destination(_ route: WorkspaceRoute, section: WorkspaceSection)
        -> some View
    {
        switch route {
        case .archive(let programme): archive(programme, section: section)
        case .player(let presentation): playerPage(presentation)
        case .history:
            HistoryView(model: library) { play(.history($0), section: .library) }
        }
    }

    private func playerPage(_ presentation: PlayerPresentation) -> some View {
        PlayerSessionView(session: player, download: dependencies.downloadCurrentProgramme)
            #if os(iOS)
                .toolbar(.hidden, for: .tabBar)
            #endif
            .onDisappear {
                // Fullscreen layout changes do not end the playback route.
                // A committed navigation pop releases only the presentation that left.
                let remains =
                    cataloguePath.contains(.player(presentation))
                    || libraryPath.contains(.player(presentation))
                    || downloadsPath.contains(presentation)
                guard !remains else { return }
                Task { await player.close(presentationID: presentation.id) }
            }
    }

    private func restore(_ data: Data) -> [WorkspaceRoute] {
        let ids = (try? JSONDecoder().decode([String].self, from: data)) ?? []
        return ids.compactMap { id in
            catalogue.programmes.first { $0.id == id }.map(WorkspaceRoute.archive)
        }
    }

    private var colorScheme: ColorScheme? {
        switch dependencies.settings.value.appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

private struct PlayerPresentation: Identifiable, Hashable {
    let id: UUID
    let section: WorkspaceSection
}

private enum WorkspaceRoute: Hashable {
    case archive(Programme)
    case history
    case player(PlayerPresentation)

    var isPlayback: Bool {
        if case .player = self { true } else { false }
    }

    var programmeID: String? {
        if case .archive(let programme) = self { programme.id } else { nil }
    }
}
