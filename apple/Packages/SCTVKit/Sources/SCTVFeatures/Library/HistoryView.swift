import SCTVCore
import SwiftUI

public struct HistoryView: View {
    @Bindable private var model: LibraryModel
    @State private var confirmClear = false
    @Environment(\.colorScheme) private var scheme
    private let play: (HistoryEntry) -> Void

    public init(model: LibraryModel, play: @escaping (HistoryEntry) -> Void) {
        self.model = model
        self.play = play
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if let warning = model.warning { InlineNotice(text: warning) }
                ForEach(HistoryDay.group(model.entries)) { day in
                    SectionHeading(title: day.id.formatted(date: .abbreviated, time: .omitted))
                    ForEach(day.entries) { entry in
                        HistoryCard(
                            entry: entry, play: { play(entry) },
                            remove: { Task { await model.remove(entry) } })
                    }
                }
            }.padding(20).frame(maxWidth: 1000).frame(maxWidth: .infinity)
        }
        .background(PresentationStyle.canvas(scheme))
        .overlay {
            if model.entries.isEmpty { ContentUnavailableView("暂无观看记录", systemImage: "clock") }
        }
        .navigationTitle("观看历史")
        .toolbar {
            Button("清空历史", role: .destructive) { confirmClear = true }.disabled(
                model.entries.isEmpty)
        }
        .confirmationDialog("清空全部观看历史？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("清空历史", role: .destructive) { Task { await model.clear() } }
        }
        .task { await model.load() }
    }
}
