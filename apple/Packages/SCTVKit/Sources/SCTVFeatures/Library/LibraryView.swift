import SCTVCore
import SwiftUI

public struct LibraryView: View {
    @Bindable private var model: LibraryModel
    @Bindable private var catalogue: CatalogueModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let play: (HistoryEntry) -> Void
    private let open: (Programme) -> Void
    private let showHistory: () -> Void
    private let settings: () -> Void

    public init(
        model: LibraryModel, catalogue: CatalogueModel, play: @escaping (HistoryEntry) -> Void,
        open: @escaping (Programme) -> Void, showHistory: @escaping () -> Void,
        settings: @escaping () -> Void
    ) {
        self.model = model
        self.catalogue = catalogue
        self.play = play
        self.open = open
        self.settings = settings
        self.showHistory = showHistory
    }

    public var body: some View {
        Group {
            #if os(iOS)
                List {
                    sections
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            #else
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        sections
                    }
                    .padding(20).frame(maxWidth: 1160).frame(maxWidth: .infinity)
                }
            #endif
        }
        // Animate the accepted row change once, including replacement by the empty state.
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.25), value: model.continuing.map(\.id)
        )
        .background(PresentationStyle.canvas(scheme))
        .navigationTitle("资料库")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            .toolbar(.visible, for: .navigationBar)
        #endif
        #if os(iOS)
            .toolbar {
                ToolbarItem {
                    Button("设置", systemImage: "gearshape", action: settings)
                    .labelStyle(.iconOnly).help("设置")
                }
            }
        #endif
        .task {
            await model.load()
            await catalogue.load()
        }
    }

    private var sections: some View {
        Group {
            if let warning = model.warning { InlineNotice(text: warning) }
            Section {
                if model.continuing.isEmpty {
                    informationCard(
                        "故事，留待下次继续", detail: "观看中的节目会自动保存在这里。", symbol: "play.rectangle"
                    )
                    .transition(.opacity)
                } else {
                    #if os(iOS)
                        ForEach(model.continuing) { entry in historyRow(entry) }
                    #else
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 290), spacing: 16)], spacing: 16
                        ) {
                            ForEach(model.continuing) { entry in historyRow(entry) }
                        }
                    #endif
                }
            } header: {
                SectionHeading(title: "继续观看", count: model.continuing.count)
                    .foregroundStyle(Color.primary).textCase(nil)
            }
            Section {
                favourites
            } header: {
                SectionHeading(title: "收藏栏目", count: savedProgrammes.count)
                    .foregroundStyle(Color.primary).textCase(nil)
            }
            Button(action: showHistory) {
                informationCard(
                    "观看历史", detail: "每一次回看，都有迹可循", symbol: "clock.arrow.circlepath",
                    disclosure: true)
            }.buttonStyle(.plain).accessibilityLabel("观看历史")
        }
    }

    private var savedProgrammes: [Programme] {
        catalogue.programmes.filter { catalogue.favouriteIDs.contains($0.id) }
    }

    @ViewBuilder private var favourites: some View {
        if savedProgrammes.isEmpty {
            informationCard("把喜欢的栏目留在身边", detail: "轻点栏目封面上的爱心，即可收藏。", symbol: "heart")
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 156), spacing: 16)], spacing: 16) {
                ForEach(savedProgrammes) { programme in
                    Button {
                        open(programme)
                    } label: {
                        VStack(alignment: .leading, spacing: 0) {
                            Artwork(url: programme.cover).clipShape(
                                RoundedRectangle(cornerRadius: 16))
                            Text(programme.name).font(.headline).foregroundStyle(Color.primary)
                                .lineLimit(1)
                                .padding(.horizontal, 12).padding(.vertical, 10)
                        }.editorialCard()
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func informationCard(
        _ title: String, detail: String, symbol: String, disclosure: Bool = false
    ) -> some View {
        HStack(spacing: 16) {
            Image(systemName: symbol).symbolVariant(.none).font(.system(size: 26, weight: .light))
                .foregroundStyle(PresentationStyle.accent(scheme))
                .frame(width: 52, height: 52)
                .background(
                    PresentationStyle.accent(scheme).opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline).foregroundStyle(Color.primary)
                Text(detail).font(.subheadline).foregroundStyle(Color.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if disclosure {
                Image(systemName: "chevron.right").foregroundStyle(Color.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(18).editorialCard()
    }

    private func historyRow(_ entry: HistoryEntry) -> some View {
        HistoryCard(
            entry: entry, play: { play(entry) }, remove: { Task { await model.remove(entry) } })
    }
}
