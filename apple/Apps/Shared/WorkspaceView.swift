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
    @State private var selection: WorkspaceSection? = .catalogue
    @SceneStorage("workspace.tab") private var selectedTabName = "栏目"
    @SceneStorage("workspace.cataloguePath") private var savedCataloguePath = Data()
    @SceneStorage("workspace.libraryPath") private var savedLibraryPath = Data()
    @SceneStorage("workspace.catalogueSort") private var savedAlphabetical = false
    @State private var restoredPaths = false
    @State private var cataloguePath: [Programme] = []
    @State private var libraryPath: [Programme] = []
    @State private var showingSettings = false
    @State private var playerPresentation: PlayerPresentation?
    @State private var message: String?
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
    }

    var body: some View {
        Group {
            #if os(macOS)
                NavigationSplitView {
                    List(WorkspaceSection.allCases, selection: $selection) { item in
                        Label(item.rawValue, systemImage: item.symbol).tag(item)
                    }
                    .navigationTitle("SCTV")
                    .navigationSplitViewColumnWidth(min: 160, ideal: 200)
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
            savedCataloguePath = (try? JSONEncoder().encode(value.map(\.id))) ?? Data()
        }
        .onChange(of: libraryPath) { _, value in
            savedLibraryPath = (try? JSONEncoder().encode(value.map(\.id))) ?? Data()
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
            .sheet(item: $playerPresentation) { presentation in
                NavigationStack {
                    PlayerSessionView(session: player)
                    .onDisappear { Task { await player.close(expected: presentation.id) } }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("完成") { playerPresentation = nil }
                        }
                    }
                }
            }
        #endif
    }

    private var catalogueNavigation: some View {
        NavigationStack(path: $cataloguePath) {
            CatalogueView(model: catalogue) { cataloguePath.append($0) }
                .navigationDestination(for: Programme.self) { archive($0) }
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
                            await present(request, intent: intent)
                        } catch {
                            if player.isCurrentRequest(intent) {
                                message = error.localizedDescription
                            }
                        }
                    }
                }, open: { libraryPath.append($0) },
                settings: {
                    #if os(macOS)
                        openSettings()
                    #else
                        showingSettings = true
                    #endif
                }
            ).navigationDestination(for: Programme.self) { archive($0) }
        }
    }

    private var downloadsNavigation: some View {
        NavigationStack {
            DownloadsView(
                model: downloads,
                play: { task in
                    let intent = player.beginRequest()
                    Task { await playDownloaded(task, intent: intent) }
                },
                export: { task in Task { await sharing.export(task) } },
                reveal: { task in Task { await sharing.reveal(task) } },
                reauthorize: { task in Task { await sharing.reauthorize(task) } })
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
                    cover: task.cover, localFile: lease), intent: intent)
        } catch {
            if player.isCurrentRequest(intent) { message = error.localizedDescription }
            try? await dependencies.downloads.service.reconcile()
        }
    }

    private func archive(_ programme: Programme) -> some View {
        ArchiveDestination(
            programme: programme, repository: dependencies.programmes,
            play: { content, date in
                let intent = player.beginRequest()
                Task {
                    do {
                        let request = try await dependencies.resolver.prepare(
                            content, programme: programme, broadcast: date,
                            quality: dependencies.settings.value.playbackQuality)
                        await present(request, intent: intent)
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

    private func present(_ request: PlaybackRequest, intent: UUID) async {
        guard let token = player.beginPresentation(for: intent) else { return }
        #if os(macOS)
            openWindow(id: "player")
        #else
            playerPresentation = PlayerPresentation(id: token)
        #endif
        await player.open(request, expected: token)
    }

    private func restore(_ data: Data) -> [Programme] {
        let ids = (try? JSONDecoder().decode([String].self, from: data)) ?? []
        return ids.compactMap { id in catalogue.programmes.first { $0.id == id } }
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
    @State private var model: ArchiveModel?
    @SceneStorage private var dateID: String
    @SceneStorage private var ascending: Bool
    @SceneStorage private var anchor: String
    let programme: Programme
    let repository: any ProgrammeRepository
    let play: (ProgrammeContent, BroadcastDate) -> Void
    let download: ([ProgrammeContent], BroadcastDate) -> Void

    init(
        programme: Programme, repository: any ProgrammeRepository,
        play: @escaping (ProgrammeContent, BroadcastDate) -> Void,
        download: @escaping ([ProgrammeContent], BroadcastDate) -> Void
    ) {
        self.programme = programme
        self.repository = repository
        self.play = play
        self.download = download
        _dateID = SceneStorage(wrappedValue: "", "archive.\(programme.id).date")
        _ascending = SceneStorage(wrappedValue: true, "archive.\(programme.id).ascending")
        _anchor = SceneStorage(wrappedValue: "", "archive.\(programme.id).anchor")
    }

    var body: some View {
        Group {
            if let model {
                ArchiveView(model: model, play: play, download: download)
                    .onChange(of: model.selectedDateID) { _, value in
                        if let value { dateID = value }
                    }
                    .onChange(of: model.ascending) { _, value in ascending = value }
                    .onChange(of: model.scrollAnchor) { _, value in if let value { anchor = value }
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

private struct PlayerPresentation: Identifiable { let id: UUID }
