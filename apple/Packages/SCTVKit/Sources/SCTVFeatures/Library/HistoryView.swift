import SCTVCore
import SwiftUI

public struct HistoryView: View {
    @Bindable private var model: LibraryModel
    @State private var confirmClear = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let play: (HistoryEntry) -> Void

    public init(model: LibraryModel, play: @escaping (HistoryEntry) -> Void) {
        self.model = model
        self.play = play
    }

    public var body: some View {
        Group {
            #if os(iOS)
                List {
                    historySections
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
            #else
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) { historySections }
                        .padding(20).frame(maxWidth: 1000).frame(maxWidth: .infinity)
                }
            #endif
        }
        .background(PresentationStyle.canvas(scheme))
        .overlay {
            if model.entries.isEmpty { ContentUnavailableView("暂无观看记录", systemImage: "clock") }
        }
        // Animate the accepted row change once, including replacement by the empty state.
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: model.entries.map(\.id))
        .navigationTitle("观看历史")
        #if os(iOS)
            .toolbar(.visible, for: .navigationBar)
        #endif
        .toolbar {
            Button("清空历史", role: .destructive) { confirmClear = true }.disabled(
                model.entries.isEmpty)
        }
        .confirmationDialog("清空全部观看历史？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("清空历史", role: .destructive) { Task { await model.clear() } }
        }
        .task { await model.load() }
    }

    private var historySections: some View {
        Group {
            if let warning = model.warning { InlineNotice(text: warning) }
            ForEach(HistoryDay.group(model.entries)) { day in
                Section {
                    ForEach(day.entries) { entry in
                        HistoryCard(
                            entry: entry, play: { play(entry) },
                            remove: { Task { await model.remove(entry) } })
                    }
                } header: {
                    SectionHeading(title: day.id.formatted(date: .abbreviated, time: .omitted))
                        .foregroundStyle(Color.primary).textCase(nil)
                }
            }
        }
    }

}
