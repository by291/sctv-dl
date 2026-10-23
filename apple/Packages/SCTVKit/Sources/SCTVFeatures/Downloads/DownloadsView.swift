import SCTVCore
import SwiftUI

public struct DownloadsView: View {
    @Bindable private var model: DownloadsModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var confirming: [DownloadCommand] = []
    #if os(iOS)
        @State private var editMode: EditMode = .inactive
    #endif
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
        List(selection: Binding(get: { model.selection }, set: { model.setSelection($0) })) {
            VStack(alignment: .leading, spacing: 16) {
                Text("\(model.tasks.count) 个任务 · 将喜欢的节目带在身边")
                    .font(.subheadline).foregroundStyle(.secondary)
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
                    .contextMenu { actions(task) }
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
            .toolbar(.visible, for: .navigationBar)
            .environment(\.editMode, $editMode)
            .onChange(of: editMode) { _, value in
                if !value.isEditing { model.setSelection([]) }
            }
            .onChange(of: model.visibleTasks.isEmpty) { _, empty in
                if empty { editMode = .inactive }
            }
        #endif
        .toolbar {
            #if os(iOS)
                if !model.visibleTasks.isEmpty {
                    ToolbarItem {
                        Button(editMode.isEditing ? "完成" : "编辑") {
                            withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                        }
                    }
                }
            #endif
            if !model.selection.isEmpty {
                ToolbarItem {
                    Menu("批量操作", systemImage: "checklist") {
                        commandButton("暂停", .pause)
                        commandButton("继续", .resume)
                        commandButton("重试", .retry)
                        commandButton("取消任务", .cancel)
                        commandButton("删除文件", .deleteFile, destructive: true)
                        commandButton("移除记录", .removeRecord, destructive: true)
                    }
                }
            }
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

    private func taskCard(_ task: DownloadTask) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            let layout =
                typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
            layout {
                Artwork(url: task.cover)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .frame(width: typeSize.isAccessibilitySize ? nil : 120)
                VStack(alignment: .leading, spacing: 7) {
                    Text(task.title).font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(task.programmeName) · \(task.broadcastDate)")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(task.quality == .standard ? "标准画质" : "流畅画质")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(PresentationStyle.accent(scheme))
                }.frame(maxWidth: .infinity, alignment: .leading)
                Menu("下载操作", systemImage: "ellipsis") { actions(task) }
                    .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier(
                        "download-\(task.content.contentID)-\(task.state.storageKey)")
            }
            Divider().opacity(0.5)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 16) {
                    taskStatus(task)
                    Spacer()
                    primaryActions(task)
                }
                VStack(alignment: .leading, spacing: 12) {
                    taskStatus(task)
                    primaryActions(task)
                }
            }
        }.padding(18).editorialCard()
    }

    private func taskStatus(_ task: DownloadTask) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol(task.state))
                .foregroundStyle(PresentationStyle.accent(scheme))
            VStack(alignment: .leading, spacing: 5) { status(task.state) }
        }
    }

    @ViewBuilder private func primaryActions(_ task: DownloadTask) -> some View {
        if case .completed = task.state {
            Button("播放", systemImage: "play.fill") { play(task) }
                .buttonStyle(.bordered).buttonBorderShape(.capsule)
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
            Button("播放", systemImage: "play") { play(task) }.accessibilityIdentifier(
                "play-download-\(task.content.contentID)")
            Button("导出副本", systemImage: "square.and.arrow.up") { export(task) }
            #if os(macOS)
                Button("在访达中显示", systemImage: "folder") { reveal(task) }
            #endif
        }
        commandButton("暂停", .pause, ids: [task.id])
        commandButton("继续", .resume, ids: [task.id])
        commandButton("重新下载", .retry, ids: [task.id])
        commandButton("重试保存文件", .retryPublication, ids: [task.id])
        commandButton("取消下载", .cancel, ids: [task.id])
        commandButton("删除文件", .deleteFile, ids: [task.id], destructive: true)
        commandButton("移除记录", .removeRecord, ids: [task.id], destructive: true)
    }

    @ViewBuilder private func commandButton(
        _ title: String, _ action: DownloadAction, ids: Set<UUID>? = nil, destructive: Bool = false
    ) -> some View {
        let commands = model.commands(for: action, ids: ids)
        if !commands.isEmpty {
            Button(title, role: destructive ? .destructive : nil) {
                if destructive {
                    confirming = commands
                } else {
                    Task { await model.perform(commands) }
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
            ).foregroundStyle(.secondary)
        case .completed(let file):
            Text(
                "已完成 · "
                    + ByteCountFormatter.string(fromByteCount: file.byteSize, countStyle: .file)
            ).font(
                .caption
            ).foregroundStyle(.secondary)
        case .queued: Text("等待下载").font(.caption)
        case .paused(let resume): Text(resume == nil ? "已暂停，可重新下载" : "已暂停").font(.caption)
        case .publishing: ProgressView("正在保存文件")
        case .cancelled: Text("已取消").font(.caption)
        case .interrupted(let reason), .transferFailed(let reason, _),
            .publicationFailed(let reason, _):
            Text(reason).font(.caption).foregroundStyle(.secondary)
        case .missingFile: Text("文件已移动或删除").font(.caption).foregroundStyle(.secondary)
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
