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
                                                in: RoundedRectangle(cornerRadius: 12))
                                    }.buttonStyle(.plain)
                                        .accessibilityAddTraits(
                                            selection == item ? .isSelected : [])
                                }
                            }.padding(.horizontal, 12)
                        }
                        Button("设置", systemImage: "gearshape") { openSettings() }
                            .buttonStyle(.plain).padding(20)
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
                }.tabViewStyle(.sidebarAdaptable)
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
        .task {
            catalogue.alphabetical = savedAlphabetical
            selection = WorkspaceSection(rawValue: selectedTabName) ?? .catalogue
            await dependencies.settings.load()
        }
        .onChange(of: selection) { _, value in if let value { selectedTabName = value.rawValue } }
        .onChange(of: catalogue.hasAcceptedSnapshot) { _, accepted in
            guard accepted, !restoredPaths else { return }
            restoredPaths = true
            cataloguePath = restore(savedCataloguePath)
            libraryPath = restore(savedLibraryPath)
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
                        Button("完成") { showingSettings = false }
                    }
                }
            }
            .sheet(item: $sharing.sharing) { FileShareView(file: $0) }
        #endif
    }

    private var catalogueNavigation: some View {
        NavigationStack(path: $cataloguePath) {
            CatalogueView(model: catalogue) { cataloguePath.append(.archive($0)) }
                .navigationDestination(for: WorkspaceRoute.self) {
                    destination($0, section: .catalogue)
                }
        }
    }

    private var libraryNavigation: some View {
        NavigationStack(path: $libraryPath) {
            LibraryView(
                model: library, catalogue: catalogue,
                play: { entry in
                    let intent = player.beginRequest()
                    Task {
                        do {
                            let request = try await dependencies.resolver.resolve(
                                entry, quality: dependencies.settings.value.playbackQuality)
                            await present(request, intent: intent, section: .library)
                        } catch {
                            if player.isCurrentRequest(intent) {
                                message = error.localizedDescription
                            }
                        }
                    }
                }, open: { libraryPath.append(.archive($0)) },
                showHistory: { libraryPath.append(.history) },
                settings: {
                    #if os(macOS)
                        openSettings()
                    #else
                        showingSettings = true
                    #endif
                }
            ).navigationDestination(for: WorkspaceRoute.self) { destination($0, section: .library) }
        }
    }

    private var downloadsNavigation: some View {
        NavigationStack(path: $downloadsPath) {
            DownloadsView(
                model: downloads,
                play: { task in
                    let intent = player.beginRequest()
                    Task { await playDownloaded(task, intent: intent) }
                },
                export: { task in Task { await sharing.export(task) } },
                reveal: { task in Task { await sharing.reveal(task) } },
                reauthorize: { task in Task { await sharing.reauthorize(task) } }
            )
            .navigationDestination(for: PlayerPresentation.self) { playerPage($0) }
        }
    }

    private func playDownloaded(_ task: DownloadTask, intent: UUID) async {
        do {
            let lease = try await dependencies.downloads.access.open(task.id)
            let history = try? await dependencies.history.entries().first {
                $0.content == task.content
            }
            let resume =
                history.map {
                    HistoryRules.resumePosition(positionMs: $0.positionMs, completed: $0.completed)
                } ?? 0
            await present(
                PlaybackRequest(
                    content: task.content, title: task.title, sources: [], quality: task.quality,
                    resumeMilliseconds: resume, programmeName: task.programmeName,
                    broadcastDate: task.broadcastDate,
                    cover: task.cover, localFile: lease), intent: intent, section: .downloads)
        } catch {
            if player.isCurrentRequest(intent) { message = error.localizedDescription }
            try? await dependencies.downloads.service.reconcile()
        }
    }

    private func archive(_ programme: Programme, section: WorkspaceSection) -> some View {
        ArchiveDestination(
            programme: programme, repository: dependencies.programmes, catalogue: catalogue,
            play: { content, date in
                let intent = player.beginRequest()
                Task {
                    do {
                        let request = try await dependencies.resolver.prepare(
                            content, programme: programme, broadcast: date,
                            quality: dependencies.settings.value.playbackQuality)
                        await present(request, intent: intent, section: section)
                    } catch {
                        if player.isCurrentRequest(intent) { message = error.localizedDescription }
                    }
                }
            },
            download: { contents, date in
                Task { await startDownloads(contents, programme: programme, broadcast: date) }
            })
    }

    private func startDownloads(
        _ contents: [ProgrammeContent], programme: Programme, broadcast: BroadcastDate
    ) async {
        await dependencies.downloads.start()
        guard dependencies.downloads.warning == nil else {
            message = dependencies.downloads.warning
            return
        }

        let quality = dependencies.settings.value.playbackQuality
        let prepared = DownloadPreparation.prepare(
            contents: contents, programme: programme, broadcast: broadcast,
            requestedQuality: quality, productVersion: "0.1.0")
        let requests = prepared.prepared.map {
            $0.request(
                destination: dependencies.downloads.destination,
                allowsCellular: dependencies.settings.value.allowCellularDownloads)
        }
        let result = await dependencies.downloads.service.start(requests)

        let failed = prepared.failures.count + result.failures.count
        let fallback = prepared.prepared.filter { $0.source.quality != quality }.count
        message =
            "已添加 \(result.accepted.count) 个下载"
            + (fallback > 0 ? "，其中 \(fallback) 项使用可用画质" : "")
            + (failed > 0 ? "；\(failed) 项未添加，请检查任务列表或稍后重试。" : "。")
    }

    private func present(_ request: PlaybackRequest, intent: UUID, section: WorkspaceSection) async
    {
        guard let token = player.beginPresentation(for: intent) else { return }
        #if os(macOS)
            openWindow(id: "player")
        #else
            let presentation = PlayerPresentation(id: token, section: section)
            playerLifetime.takeOwnership(of: token)
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
        await player.open(request, expected: token)
    }

    @ViewBuilder private func destination(_ route: WorkspaceRoute, section: WorkspaceSection)
        -> some View
    {
        switch route {
        case .archive(let programme): archive(programme, section: section)
        case .player(let presentation): playerPage(presentation)
        case .history:
            HistoryView(model: library) { entry in
                let intent = player.beginRequest()
                Task {
                    do {
                        let request = try await dependencies.resolver.resolve(
                            entry, quality: dependencies.settings.value.playbackQuality)
                        await present(request, intent: intent, section: .library)
                    } catch {
                        if player.isCurrentRequest(intent) { message = error.localizedDescription }
                    }
                }
            }
        }
    }

    private func playerPage(_ presentation: PlayerPresentation) -> some View {
        PlayerSessionView(session: player, download: dependencies.downloadCurrentProgramme)
            #if os(iOS)
                .toolbar(.hidden, for: .tabBar)
            #endif
            .onDisappear {
                // AVKit fullscreen temporarily covers this view without ending its route.
                // A committed navigation pop releases only the presentation that left.
                let remains =
                    cataloguePath.contains(.player(presentation))
                    || libraryPath.contains(.player(presentation))
                    || downloadsPath.contains(presentation)
                guard !remains else { return }
                Task { await player.close(expected: presentation.id) }
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

private struct ArchiveDestination: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false
    @State private var model: ArchiveModel?
    @SceneStorage private var dateID: String
    @SceneStorage private var ascending: Bool
    @SceneStorage private var anchor: String
    let programme: Programme
    let repository: any ProgrammeRepository
    let catalogue: CatalogueModel
    let play: (ProgrammeContent, BroadcastDate) -> Void
    let download: ([ProgrammeContent], BroadcastDate) -> Void

    init(
        programme: Programme, repository: any ProgrammeRepository, catalogue: CatalogueModel,
        play: @escaping (ProgrammeContent, BroadcastDate) -> Void,
        download: @escaping ([ProgrammeContent], BroadcastDate) -> Void
    ) {
        self.programme = programme
        self.repository = repository
        self.catalogue = catalogue
        self.play = play
        self.download = download
        _dateID = SceneStorage(wrappedValue: "", "archive.\(programme.id).date")
        _ascending = SceneStorage(wrappedValue: true, "archive.\(programme.id).ascending")
        _anchor = SceneStorage(wrappedValue: "", "archive.\(programme.id).anchor")
    }

    var body: some View {
        Group {
            if let model {
                ArchiveView(
                    model: model, favourite: catalogue.favouriteIDs.contains(programme.id),
                    toggleFavourite: { Task { await catalogue.toggleFavourite(programme) } },
                    play: play, download: download
                )
                .onChange(of: model.selectedDateID) { _, value in
                    if let value { dateID = value }
                }
                .onChange(of: model.ascending) { _, value in ascending = value }
                // Persist at lifecycle boundaries without observing every scroll target
                // in this parent, which would invalidate the complete archive subtree.
                .onAppear { isVisible = true }
                .onDisappear {
                    isVisible = false
                    if let value = model.scrollAnchor { anchor = value }
                }
                .onChange(of: scenePhase) { _, phase in
                    if isVisible, phase != .active, let value = model.scrollAnchor {
                        anchor = value
                    }
                }
            } else {
                ProgressView("载入栏目")
            }
        }.task {
            guard model == nil else { return }
            let value = ArchiveModel(
                programme: programme, repository: repository, restoredDateID: dateID)
            value.ascending = ascending
            value.scrollAnchor = anchor.isEmpty ? nil : anchor
            model = value
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
