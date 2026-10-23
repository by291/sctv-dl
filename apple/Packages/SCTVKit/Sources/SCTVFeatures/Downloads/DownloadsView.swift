import SCTVCore
import SwiftUI

public struct DownloadsView: View {
    @Bindable private var model: DownloadsModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var confirming: [DownloadCommand] = []
    @State private var selecting = false
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
        List(selection: selectionBinding) {
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
            if model.isReconciling {
                VStack {
                    if model.warning == nil {
                        ProgressView("正在恢复下载任务")
                    } else {
                        Button("重试恢复下载状态") { Task { await model.reconcile() } }
                    }
                }
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
            } else if model.visibleTasks.isEmpty {
                ContentUnavailableView(
                    "暂无下载", systemImage: "arrow.down.circle",
                    description: Text("在节目页面选择下载，完成后即可离线观看。")
                )
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
            }

            ForEach(model.isReconciling ? [] : model.visibleTasks) { task in
                taskCard(task).tag(task.id)
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
                    .contextMenu { if !selecting { actions(task) } }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: 1160)
        .frame(maxWidth: .infinity)
        .background(PresentationStyle.canvas(scheme))
        .scrollPosition(
            id: Binding(
                get: { model.anchors[model.filter] }, set: { model.anchors[model.filter] = $0 })
        )
        .navigationTitle("下载")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            .toolbar(selecting ? .hidden : .visible, for: .tabBar)
            .toolbar(.visible, for: .navigationBar)
            .environment(
                \.editMode,
                Binding(
                    get: { selecting ? .active : .inactive },
                    set: { selecting = $0.isEditing }))
        #endif
        .onChange(of: selecting) { _, value in
            if !value { model.setSelection([]) }
        }
        .onChange(of: model.visibleTasks.isEmpty) { _, empty in
            if empty { selecting = false }
        }
        .toolbar {
            // Preserve item identity when select-all is inserted or removed during rapid toggles.
            if selecting {
                ToolbarItem(id: "downloads-select-all", placement: .cancellationAction) {
                    Button(model.selection.count == model.visibleTasks.count ? "取消全选" : "全选") {
                        let all = Set(model.visibleTasks.map(\.id))
                        model.setSelection(model.selection == all ? [] : all)
                    }
                    .help(model.selection.count == model.visibleTasks.count ? "取消全选" : "全选")
                }
            }
            if !model.visibleTasks.isEmpty {
                ToolbarItem(id: "downloads-selection") {
                    Button(
                        selecting ? "完成" : "选择", systemImage: selecting ? "checkmark" : "checklist"
                    ) {
                        withAnimation { selecting.toggle() }
                    }
                    .labelStyle(.iconOnly).help(selecting ? "完成" : "选择")
                    .accessibilityIdentifier("downloads-select")
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if selecting { selectionBar }
        }
        .confirmationDialog(
            "确认执行所选操作？",
            isPresented: Binding(get: { !confirming.isEmpty }, set: { if !$0 { confirming = [] } }),
            titleVisibility: .visible
        ) {
            Button("确认", role: .destructive) {
                let commands = confirming
                confirming = []
                Task { await model.perform(commands) }
            }
        } message: {
            Text("移除记录会保留文件；删除文件会保留记录。")
        }
        .task { await model.load() }
    }

    // A nil binding keeps ordinary row/menu taps out of native selection mode.
    private var selectionBinding: Binding<Set<UUID>>? {
        guard selecting else { return nil }
        return Binding(get: { model.selection }, set: { model.setSelection($0) })
    }

    private struct BatchAction: Identifiable {
        let title: String
        let action: DownloadAction
        var destructive = false
        var id: String { title }
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

    private var selectionBar: some View {
        let actions = availableBatchActions
        return Group {
            if model.selection.isEmpty {
                Text("请选择要操作的下载任务")
                    .font(.subheadline).foregroundStyle(secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: 12),
                        count: typeSize.isAccessibilitySize ? 1 : max(1, min(actions.count, 3))),
                    spacing: 12
                ) {
                    ForEach(actions) { item in
                        Button(role: item.destructive ? .destructive : nil) {
                            let commands = model.commands(for: item.action)
                            if item.destructive {
                                confirming = commands
                            } else {
                                Task { await model.perform(commands) }
                            }
                        } label: {
                            Text(item.title).frame(maxWidth: .infinity, minHeight: 32)
                        }
                    }
                }
                .buttonStyle(.bordered).buttonBorderShape(.capsule)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .frame(maxWidth: 600).frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private func taskCard(_ task: DownloadTask) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            let layout =
                typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
            layout {
                Artwork(url: task.cover)
                    // Fix both dimensions so title height cannot shrink the fitted artwork.
                    .frame(
                        width: typeSize.isAccessibilitySize ? nil : 136,
                        height: typeSize.isAccessibilitySize ? nil : 136 * 9 / 16
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title).font(.headline)
                        // Keep selected-row text readable without overriding button tint.
                        .foregroundStyle(scheme == .dark ? Color.white : Color.black)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(task.programmeName) · \(task.broadcastDate)")
                        .font(.caption).foregroundStyle(secondaryText)
                        .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                    Text(task.quality == .standard ? "标准画质" : "流畅画质")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(PresentationStyle.accent(scheme))
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider().opacity(0.5)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 8) {
                    taskStatus(task)
                    Spacer(minLength: 4)
                    if !selecting { cardActions(task) }
                }
                VStack(alignment: .leading, spacing: 8) {
                    taskStatus(task)
                    if !selecting {
                        HStack {
                            Spacer()
                            cardActions(task)
                        }
                    }
                }
            }
            .frame(minHeight: 44)
        }
        .padding(12).editorialCard()
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
        }
    }

    private func taskStatus(_ task: DownloadTask) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol(task.state))
                .foregroundStyle(PresentationStyle.accent(scheme))
            VStack(alignment: .leading, spacing: 5) { status(task.state) }
                .foregroundStyle(scheme == .dark ? Color.white : Color.black)
        }
    }

    @ViewBuilder private func primaryActions(_ task: DownloadTask) -> some View {
        if case .completed = task.state {
            Button("播放") { play(task) }
                .buttonStyle(.bordered).buttonBorderShape(.capsule)
                .accessibilityIdentifier("play-download-\(task.content.contentID)")
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
                    confirming = commands
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

    @ViewBuilder private func status(_ state: DownloadState) -> some View {
        switch state {
        case .transferring(let received, let total):
            if let total, total > 0 {
                ProgressView(value: Double(received), total: Double(max(total, received)))
                    .accessibilityLabel("下载进度")
            } else {
                ProgressView().controlSize(.small)
            }
            Text(ByteCountFormatter.string(fromByteCount: received, countStyle: .file)).font(
                .caption
            ).foregroundStyle(secondaryText)
        case .completed(let file):
            Text(
                "已完成 · "
                    + ByteCountFormatter.string(fromByteCount: file.byteSize, countStyle: .file)
            ).font(
                .caption
            ).foregroundStyle(secondaryText)
        case .queued: Text("等待下载").font(.caption)
        case .paused(let resume): Text(resume == nil ? "已暂停，可重新下载" : "已暂停").font(.caption)
        case .publishing: ProgressView("正在保存文件")
        case .cancelled: Text("已取消").font(.caption)
        case .interrupted(let reason), .transferFailed(let reason, _),
            .publicationFailed(let reason, _):
            Text(reason).font(.caption).foregroundStyle(secondaryText)
        case .missingFile: Text("文件已移动或删除").font(.caption).foregroundStyle(secondaryText)
        }
    }

    private func symbol(_ state: DownloadState) -> String {
        switch state {
        case .completed: "checkmark.circle"
        case .paused: "pause.circle"
        case .transferFailed, .publicationFailed, .missingFile, .interrupted:
            "exclamationmark.circle"
        default: "arrow.down.circle"
        }
    }
}
