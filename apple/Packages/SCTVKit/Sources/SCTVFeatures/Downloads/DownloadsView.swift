import SCTVCore
import SwiftUI

public struct DownloadsView: View {
    private enum ConfirmationSource: Equatable {
        case task(UUID)
        case batch(String)
    }

    private struct Confirmation {
        let source: ConfirmationSource
        let commands: [DownloadCommand]
    }

    private struct BatchAction: Identifiable {
        let title: String
        let action: DownloadAction
        var destructive = false
        var id: String { title }
    }

    @Bindable private var model: DownloadsModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var confirming: Confirmation?
    @State private var selecting = false
    @State private var departingActions: [BatchAction] = []

    private let play: (DownloadTask) -> Void
    private let export: (DownloadTask) -> Void
    private let reauthorize: (DownloadTask) -> Void
    private let reveal: (DownloadTask) -> Void

    public init(
        model: DownloadsModel, play: @escaping (DownloadTask) -> Void,
        export: @escaping (DownloadTask) -> Void, reveal: @escaping (DownloadTask) -> Void,
        reauthorize: @escaping (DownloadTask) -> Void = { _ in }
    ) {
        self.model = model
        self.play = play
        self.export = export
        self.reveal = reveal
        self.reauthorize = reauthorize
    }

    public var body: some View {
        #if os(iOS)
            BatchSelectionTransition(progress: selecting ? 1 : 0) { progress in
                page(selectionProgress: progress)
            }
        #else
            page(selectionProgress: selecting ? 1 : 0)
        #endif
    }

    private func page(selectionProgress: CGFloat) -> some View {
        GeometryReader { geometry in
            let columns = MediaCardLayout.columnCount(
                width: geometry.size.width, typeSize: typeSize)
            Group {
                if columns == 1 {
                    List(selection: selectionBinding) {
                        listHeader
                        ForEach(model.canPerformCommands ? model.visibleTasks : []) { task in
                            taskRow(task, progress: selectionProgress).tag(task.id)
                                .listRowBackground(Color.clear).listRowSeparator(.hidden)
                                .contextMenu { if !selecting { actions(task) } }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            listHeader
                            LazyVGrid(
                                columns: MediaCardLayout.columns(columns),
                                spacing: MediaCardLayout.spacing
                            ) {
                                ForEach(model.canPerformCommands ? model.visibleTasks : []) {
                                    task in
                                    taskRow(task, progress: selectionProgress, cardSelection: true)
                                        .id(task.id)
                                        .contextMenu { if !selecting { actions(task) } }
                                }
                            }.scrollTargetLayout()
                        }.padding(20)
                    }
                }
            }
            .frame(maxWidth: 1160)
            .frame(maxWidth: .infinity)
        }
        .background(PresentationStyle.canvas(scheme))
        .scrollPosition(
            id: Binding(
                get: { model.anchors[model.filter] }, set: { model.anchors[model.filter] = $0 })
        )
        .navigationTitle("下载")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            .toolbar(.visible, for: .navigationBar)
        #endif
        .onChange(of: selecting) { _, value in
            if !value { model.setSelection([]) }
        }
        .onChange(of: model.visibleTasks.isEmpty) { _, empty in
            if empty { setSelecting(false) }
        }
        .toolbar {
            // Keep toolbar membership stable so rapid taps retain the same native hit target.
            if !model.visibleTasks.isEmpty {
                ToolbarItem(id: "downloads-selection") {
                    Button(
                        selecting ? "完成" : "选择", systemImage: selecting ? "checkmark" : "checklist"
                    ) {
                        setSelecting(!selecting)
                    }
                    .labelStyle(.iconOnly).help(selecting ? "完成" : "选择")
                    .accessibilityIdentifier("downloads-select")
                }
            }
        }
        .batchSelectionBar(selecting: selecting, progress: selectionProgress) {
            selectionBar(progress: selectionProgress)
        }
        .alert(
            batchConfirmationTitle,
            isPresented: Binding(
                get: { batchConfirmation != nil },
                set: { if !$0, batchConfirmation != nil { confirming = nil } }),
            presenting: batchConfirmation
        ) { pending in
            Button("取消", role: .cancel) { confirming = nil }
            Button(
                pending.commands.first?.action == .deleteFile ? "删除文件" : "移除记录", role: .destructive
            ) {
                confirming = nil
                Task { await model.perform(pending.commands) }
            }
            .accessibilityIdentifier("download-confirm-action")
        } message: { pending in
            Text(
                pending.commands.first?.action == .deleteFile
                    ? "下载记录会保留，之后可以重新下载。" : "已下载的文件会保留。")
        }
        .task { await model.load() }
    }

    @ViewBuilder private var listHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(
                selecting
                    ? "已选 \(model.selection.count) 项" : "\(model.tasks.count) 个任务 · 将喜欢的节目带在身边"
            )
            .font(.subheadline).foregroundStyle(secondaryText)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(DownloadFilter.allCases) { filter in
                        Button {
                            model.selectFilter(filter)
                        } label: {
                            Text(filter.rawValue).font(.subheadline.weight(.medium))
                                .padding(.horizontal, 18).padding(.vertical, 12)
                                .foregroundStyle(
                                    model.filter == filter
                                        ? (scheme == .dark ? Color.black : .white) : .primary
                                )
                                .background(
                                    model.filter == filter
                                        ? PresentationStyle.accent(scheme)
                                        : PresentationStyle.surface(scheme), in: Capsule())
                        }.buttonStyle(.plain)
                            .accessibilityAddTraits(model.filter == filter ? .isSelected : [])
                    }
                }
            }
        }
        .padding(.vertical, 12)
        .listRowBackground(Color.clear).listRowSeparator(.hidden)
        if let warning = model.warning {
            InlineNotice(text: warning).listRowBackground(Color.clear).listRowSeparator(.hidden)
        }
        if !model.canPerformCommands {
            VStack {
                switch model.recoveryState {
                case .loading:
                    ProgressView("正在恢复下载任务")
                case .failed:
                    Button("重试恢复下载状态") { Task { await model.reconcile() } }
                case .ready:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear).listRowSeparator(.hidden)
        } else if model.visibleTasks.isEmpty {
            ContentUnavailableView(
                "暂无下载", systemImage: "arrow.down.circle",
                description: Text("在节目页面选择下载，完成后即可离线观看。")
            )
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear).listRowSeparator(.hidden)
        }
    }

    private var batchConfirmation: Confirmation? {
        guard let confirming, case .batch = confirming.source else { return nil }
        return confirming
    }

    private var batchConfirmationTitle: String {
        guard let pending = batchConfirmation else { return "" }
        let count = pending.commands.count
        return pending.commands.first?.action == .deleteFile
            ? "删除 \(count) 个文件？" : "移除 \(count) 条记录？"
    }

    private func confirmationPresented(for source: ConfirmationSource) -> Binding<Bool> {
        Binding(
            get: { confirming?.source == source },
            set: { presented in
                if !presented, confirming?.source == source { confirming = nil }
            })
    }

    private var confirmationActions: some View {
        Button("确认", role: .destructive) {
            guard let pending = confirming else { return }
            confirming = nil
            // Keep the original attempt guards while the confirmation is presented.
            Task { await model.perform(pending.commands) }
        }
        .accessibilityIdentifier("download-confirm-action")
    }

    private func setSelecting(_ value: Bool) {
        if !value { departingActions = availableBatchActions }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
            selecting = value
        }
    }

    // A nil binding keeps ordinary row/menu taps out of native selection mode.
    private var selectionBinding: Binding<Set<UUID>>? {
        #if os(iOS)
            return nil
        #else
            guard selecting else { return nil }
            return Binding(get: { model.selection }, set: { model.setSelection($0) })
        #endif
    }

    private func taskRow(
        _ task: DownloadTask, progress: CGFloat, cardSelection: Bool = false
    ) -> some View {
        #if os(iOS)
            let usesCardSelection = true
        #else
            let usesCardSelection = cardSelection
        #endif

        return DownloadCard(
            task: task, selected: model.selection.contains(task.id), selecting: selecting,
            selectionProgress: progress, usesCardSelection: usesCardSelection,
            play: { play(task) }, toggleSelection: { toggleSelection(of: task) },
            actions: { cardActions(task) })
    }

    private func toggleSelection(of task: DownloadTask) {
        var selection = model.selection
        if selection.contains(task.id) {
            selection.remove(task.id)
        } else {
            selection.insert(task.id)
        }
        model.setSelection(selection)
    }

    private var availableBatchActions: [BatchAction] {
        [
            BatchAction(title: "暂停", action: .pause),
            BatchAction(title: "继续", action: .resume),
            BatchAction(title: "重试", action: .retry),
            BatchAction(title: "重试保存", action: .retryPublication),
            BatchAction(title: "取消任务", action: .cancel),
            BatchAction(title: "删除文件", action: .deleteFile, destructive: true),
            BatchAction(title: "移除记录", action: .removeRecord, destructive: true),
        ].filter { !model.commands(for: $0.action).isEmpty }
    }

    private var secondaryText: Color {
        (scheme == .dark ? Color.white : Color.black).opacity(0.55)
    }

    private func selectionBar(progress: CGFloat) -> some View {
        // Retain outgoing labels only through the exit animation. Native menus can otherwise
        // expose the invisible buttons to accessibility after selection has ended.
        let actions = selecting ? availableBatchActions : (progress > 0 ? departingActions : [])
        return BatchActionBar {
            if actions.isEmpty {
                HStack(spacing: 12) {
                    selectAllButton
                    Text("请选择要操作的下载任务")
                        .font(.subheadline).foregroundStyle(secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            } else {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: 12),
                        count: typeSize.isAccessibilitySize ? 1 : min(actions.count + 1, 3)),
                    spacing: 12
                ) {
                    selectAllButton
                    ForEach(actions) { item in
                        Button(role: item.destructive ? .destructive : nil) {
                            let commands = model.commands(for: item.action)
                            if item.destructive {
                                confirming = Confirmation(
                                    source: .batch(item.id), commands: commands)
                            } else {
                                Task { await model.perform(commands) }
                            }
                        } label: {
                            Text(item.title).frame(maxWidth: .infinity, minHeight: 32)
                        }

                    }
                }
            }
        }
    }

    private var selectAllButton: some View {
        Button {
            let all = Set(model.visibleTasks.map(\.id))
            model.setSelection(model.selection == all ? [] : all)
        } label: {
            Text(model.selection.count == model.visibleTasks.count ? "取消全选" : "全选")
                .frame(maxWidth: .infinity, minHeight: 32)
        }
    }

    private func cardActions(_ task: DownloadTask) -> some View {
        Group {
            primaryActions(task)
            Menu {
                actions(task)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("下载操作")
            .accessibilityIdentifier("download-\(task.content.contentID)-\(task.state.storageKey)")
            .confirmationDialog(
                "确认执行所选操作？",
                isPresented: confirmationPresented(for: .task(task.id)),
                titleVisibility: .visible
            ) {
                confirmationActions
            } message: {
                Text("移除记录会保留文件；删除文件会保留记录。")
            }
        }
    }

    @ViewBuilder private func primaryActions(_ task: DownloadTask) -> some View {
        if case .completed = task.state {
            EmptyView()
        } else {
            HStack {
                commandButton("暂停", .pause, ids: [task.id])
                commandButton("继续", .resume, ids: [task.id])
                commandButton("重试", .retry, ids: [task.id])
                commandButton("重试保存", .retryPublication, ids: [task.id])
            }.buttonStyle(.bordered).buttonBorderShape(.capsule)
        }
    }

    @ViewBuilder private func actions(_ task: DownloadTask) -> some View {
        #if os(macOS)
            if case .external = task.destination {
                Button("重新授权下载目录", systemImage: "folder.badge.gearshape") { reauthorize(task) }
            }
        #endif
        if case .completed = task.state {
            Button("导出副本", systemImage: "square.and.arrow.up") { export(task) }
            #if os(macOS)
                Button("在访达中显示", systemImage: "folder") { reveal(task) }
            #endif
        }
        commandButton("取消下载", .cancel, ids: [task.id], systemImage: "xmark.circle")
        commandButton("删除文件", .deleteFile, ids: [task.id], destructive: true, systemImage: "trash")
        commandButton(
            "移除记录", .removeRecord, ids: [task.id], destructive: true,
            systemImage: "text.badge.minus")
    }

    @ViewBuilder private func commandButton(
        _ title: String, _ action: DownloadAction, ids: Set<UUID>? = nil, destructive: Bool = false,
        systemImage: String? = nil
    ) -> some View {
        let commands = model.commands(for: action, ids: ids)
        if !commands.isEmpty {
            Button(role: destructive ? .destructive : nil) {
                if destructive {
                    guard let id = ids?.first else { return }
                    confirming = Confirmation(source: .task(id), commands: commands)
                } else {
                    Task { await model.perform(commands) }
                }
            } label: {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
            }
        }
    }

}
