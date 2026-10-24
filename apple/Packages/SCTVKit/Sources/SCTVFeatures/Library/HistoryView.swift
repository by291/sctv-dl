import SCTVCore
import SwiftUI

public struct HistoryView: View {
    @Bindable private var model: LibraryModel
    @State private var confirmClear = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let play: (HistoryEntry) -> Void

    public init(model: LibraryModel, play: @escaping (HistoryEntry) -> Void) {
        self.model = model
        self.play = play
    }

    public var body: some View {
        GeometryReader { geometry in
            let columns = MediaCardLayout.columnCount(
                width: geometry.size.width, typeSize: typeSize)
            #if os(iOS)
                if columns == 1 {
                    List {
                        historySections(columns: columns)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                    }
                    .listStyle(.plain).scrollContentBackground(.hidden)
                } else {
                    gridPage(columns: columns)
                }
            #else
                gridPage(columns: columns)
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
            Button("清空历史", systemImage: "trash", role: .destructive) { confirmClear = true }
                .labelStyle(.iconOnly).help("清空历史")
                .disabled(model.entries.isEmpty)
                .accessibilityIdentifier("history-clear")
                .confirmationDialog(
                    "清空全部观看历史？", isPresented: $confirmClear, titleVisibility: .visible
                ) {
                    Button("清空历史", role: .destructive) { Task { await model.clear() } }
                        .accessibilityIdentifier("history-confirm-clear")
                }
        }
        .task { await model.load() }
    }

    private func gridPage(columns: Int) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) { historySections(columns: columns) }
                .padding(20).frame(maxWidth: 1000).frame(maxWidth: .infinity)
        }
    }

    private func historySections(columns: Int) -> some View {
        Group {
            if let warning = model.warning { InlineNotice(text: warning) }
            ForEach(HistoryDay.group(model.entries)) { day in
                Section {
                    if columns == 1 {
                        historyCards(day.entries)
                    } else {
                        LazyVGrid(
                            columns: MediaCardLayout.columns(columns),
                            spacing: MediaCardLayout.spacing
                        ) {
                            historyCards(day.entries)
                        }
                    }
                } header: {
                    SectionHeading(
                        title: day.id.formatted(
                            .dateTime.year().month(.wide).day().locale(Locale(identifier: "zh_CN")))
                    )
                    .foregroundStyle(Color.primary).textCase(nil)
                }
            }
        }
    }

    private func historyCards(_ entries: [HistoryEntry]) -> some View {
        ForEach(entries) { entry in
            HistoryCard(
                entry: entry, play: { play(entry) },
                remove: { Task { await model.remove(entry) } })
        }
    }
}
