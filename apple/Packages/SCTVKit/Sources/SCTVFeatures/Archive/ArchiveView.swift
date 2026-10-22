import SCTVCore
import SwiftUI

public struct ArchiveView: View {
    @Bindable private var model: ArchiveModel
    @State private var selecting = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let play: (ProgrammeContent, BroadcastDate) -> Void
    private let download: ([ProgrammeContent], BroadcastDate) -> Void

    public init(
        model: ArchiveModel, play: @escaping (ProgrammeContent, BroadcastDate) -> Void,
        download: @escaping ([ProgrammeContent], BroadcastDate) -> Void
    ) {
        self.model = model
        self.play = play
        self.download = download
    }

    public var body: some View {
        List {
            if !model.dates.isEmpty {
                Section {
                    if dynamicTypeSize.isAccessibilitySize {
                        Menu {
                            datePicker.pickerStyle(.inline)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("播出日期", systemImage: "chevron.down").font(.headline)
                                Text(model.broadcast?.date ?? "选择日期")
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain)
                    } else {
                        datePicker
                    }
                }
            }
            if let warning = model.warning {
                Section {
                    Label(warning, systemImage: "exclamationmark.triangle")
                    Button("重试") { Task { await model.refresh() } }
                }
            }
            if model.hasPendingUpdate {
                Button("本栏目有更新，点此查看") { Task { await model.acceptUpdate() } }.disabled(
                    !model.selection.isEmpty)
            }
            if model.isLoading && model.contents.isEmpty { ProgressView("载入节目") }
            if !model.fullEpisodes.isEmpty {
                Section("完整节目") { ForEach(model.fullEpisodes) { contentRow($0) } }
            }
            if !model.clips.isEmpty { Section("节目片段") { ForEach(model.clips) { contentRow($0) } } }
            if !model.isLoading && model.contents.isEmpty {
                ContentUnavailableView(
                    "暂无节目", systemImage: "play.rectangle", description: Text("选择其他播出日期，或稍后刷新。"))
            }
        }
        .scrollPosition(id: $model.scrollAnchor)
        .navigationTitle(model.programme.name)
        .toolbar {
            ToolbarItem {
                Menu("更多", systemImage: "ellipsis") {
                    Toggle("片段时间正序", isOn: $model.ascending)
                    Button(selecting ? "取消选择" : "选择节目") {
                        selecting.toggle()
                        model.setSelection([])
                    }
                    Button("刷新", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
                }
            }
            if selecting {
                ToolbarItem {
                    Button("下载所选（\(model.selection.count)）", systemImage: "arrow.down.circle") {
                        if let date = model.broadcast { download(model.selectedContents, date) }
                    }.disabled(model.selection.isEmpty || model.selection.count > 100)
                }
            }
        }
        .task { await model.load() }
        .onDisappear { model.stop() }
    }

    private var datePicker: some View {
        Picker(
            "播出日期",
            selection: Binding(
                get: { model.selectedDateID ?? "" },
                set: { id in Task { await model.selectDate(id) } })
        ) {
            ForEach(model.dates) { Text($0.date).tag($0.id) }
        }
    }

    private func contentRow(_ content: ProgrammeContent) -> some View {
        HStack(spacing: 12) {
            if selecting {
                Button {
                    var ids = model.selection
                    if !ids.insert(content.id).inserted { ids.remove(content.id) }
                    model.setSelection(ids)
                } label: {
                    Image(
                        systemName: model.selection.contains(content.id)
                            ? "checkmark.circle.fill" : "circle")
                }
                .buttonStyle(.plain).accessibilityLabel("选择\(content.title)")
            }
            Button {
                if let date = model.broadcast { play(content, date) }
            } label: {
                HStack(spacing: 12) {
                    Artwork(url: content.cover).frame(width: 104).clipShape(
                        RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(content.title).foregroundStyle(.primary)
                        if let published = content.publishedAt {
                            Text(published).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain)
            Menu("节目操作", systemImage: "ellipsis") {
                Button("播放", systemImage: "play") {
                    if let date = model.broadcast { play(content, date) }
                }
                Button("下载", systemImage: "arrow.down.circle") {
                    if let date = model.broadcast { download([content], date) }
                }.accessibilityIdentifier("download-content-\(content.id)")
            }.labelStyle(.iconOnly).accessibilityIdentifier("content-actions-\(content.id)")
        }.padding(.vertical, 4).id(content.id)
    }
}
