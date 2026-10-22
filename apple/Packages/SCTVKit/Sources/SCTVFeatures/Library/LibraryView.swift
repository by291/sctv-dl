import SCTVCore
import SwiftUI

public struct LibraryView: View {
    @Bindable private var model: LibraryModel
    @Bindable private var catalogue: CatalogueModel
    @State private var confirmClear = false
    private let play: (HistoryEntry) -> Void
    private let open: (Programme) -> Void
    private let settings: () -> Void

    public init(
        model: LibraryModel, catalogue: CatalogueModel, play: @escaping (HistoryEntry) -> Void,
        open: @escaping (Programme) -> Void, settings: @escaping () -> Void
    ) {
        self.model = model
        self.catalogue = catalogue
        self.play = play
        self.open = open
        self.settings = settings
    }

    public var body: some View {
        List {
            if let warning = model.warning {
                Label(warning, systemImage: "exclamationmark.triangle")
            }
            Section("继续观看") {
                if model.continuing.isEmpty { Text("观看后的节目会出现在这里").foregroundStyle(.secondary) }
                ForEach(model.continuing) { entry in historyRow(entry) }
            }
            Section("收藏栏目") {
                let saved = catalogue.programmes.filter { catalogue.favouriteIDs.contains($0.id) }
                if saved.isEmpty { Text("在栏目上长按或右键即可收藏").foregroundStyle(.secondary) }
                ForEach(saved) { programme in
                    Button {
                        open(programme)
                    } label: {
                        Label(programme.name, systemImage: "star.fill")
                    }
                }
            }
            Section {
                NavigationLink("观看历史") {
                    List {
                        ForEach(HistoryDay.group(model.entries)) { day in
                            Section(day.id.formatted(date: .abbreviated, time: .omitted)) {
                                ForEach(day.entries) { entry in historyRow(entry) }
                            }
                        }
                    }
                    .overlay {
                        if model.entries.isEmpty {
                            ContentUnavailableView("暂无观看记录", systemImage: "clock")
                        }
                    }
                    .navigationTitle("观看历史")
                    .toolbar {
                        Button("清空历史", role: .destructive) { confirmClear = true }.disabled(
                            model.entries.isEmpty)
                    }
                }
                Button("设置", systemImage: "gearshape", action: settings)
            }
        }
        .navigationTitle("资料库")
        .confirmationDialog("清空全部观看历史？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("清空历史", role: .destructive) { Task { await model.clear() } }
        }
        .task {
            await model.load()
            await catalogue.load()
        }
    }

    private func historyRow(_ entry: HistoryEntry) -> some View {
        Button {
            play(entry)
        } label: {
            HStack(spacing: 12) {
                Artwork(url: entry.cover).frame(width: 100).clipShape(
                    RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.title).foregroundStyle(.primary)
                    Text("\(entry.programmeName) · \(entry.broadcastDate)").font(.caption)
                        .foregroundStyle(.secondary)
                    if let duration = entry.durationMs, duration > 0 {
                        ProgressView(value: min(Double(entry.positionMs) / Double(duration), 1))
                            .accessibilityLabel("观看进度")
                    }
                }
            }
        }.buttonStyle(.plain)
            .contextMenu {
                Button("删除记录", role: .destructive) { Task { await model.remove(entry) } }
            }
            .swipeActions {
                Button("删除", role: .destructive) { Task { await model.remove(entry) } }
            }
    }
}
