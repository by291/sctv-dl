import SCTVCore
import SwiftUI

public struct LibraryView: View {
    @Bindable private var model: LibraryModel
    @Bindable private var catalogue: CatalogueModel
    @Environment(\.colorScheme) private var scheme
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
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                if let warning = model.warning { InlineNotice(text: warning) }
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeading(title: "继续观看", count: model.continuing.count)
                    if model.continuing.isEmpty {
                        emptySection(
                            "故事，留待下次继续", detail: "观看中的节目会自动保存在这里。", symbol: "play.rectangle")
                    } else {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 290), spacing: 16)], spacing: 16
                        ) {
                            ForEach(model.continuing) { entry in historyRow(entry) }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 16) {
                    let saved = catalogue.programmes.filter {
                        catalogue.favouriteIDs.contains($0.id)
                    }
                    SectionHeading(title: "收藏栏目", count: saved.count)
                    if saved.isEmpty {
                        emptySection("把喜欢的栏目留在身边", detail: "轻点栏目封面上的爱心，即可收藏。", symbol: "heart")
                    } else {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 156), spacing: 16)], spacing: 16
                        ) {
                            ForEach(saved) { programme in
                                Button {
                                    open(programme)
                                } label: {
                                    VStack(alignment: .leading, spacing: 0) {
                                        Artwork(url: programme.cover).clipShape(
                                            RoundedRectangle(cornerRadius: 16))
                                        Text(programme.name).font(.headline).foregroundStyle(
                                            .primary
                                        )
                                        .lineLimit(1)
                                        .padding(.horizontal, 12).padding(.vertical, 10)
                                    }.editorialCard()
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                Button(action: showHistory) {
                    HStack(spacing: 14) {
                        Image(systemName: "clock.arrow.circlepath").font(.title2)
                            .foregroundStyle(PresentationStyle.accent(scheme))
                        VStack(alignment: .leading, spacing: 5) {
                            Text("观看历史").font(.headline).foregroundStyle(.primary)
                            Text("每一次回看，都有迹可循")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }.padding(22).editorialCard()
                }.buttonStyle(.plain).accessibilityLabel("观看历史")
            }
            .padding(20).frame(maxWidth: 1160).frame(maxWidth: .infinity)
        }
        .background(PresentationStyle.canvas(scheme))
        .navigationTitle("资料库")
        .toolbar { ToolbarItem { Button("设置", systemImage: "gearshape", action: settings) } }
        .task {
            await model.load()
            await catalogue.load()
        }
    }

    private func emptySection(_ title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 18) {
            Image(systemName: symbol).font(.system(size: 28, weight: .light))
                .foregroundStyle(PresentationStyle.accent(scheme))
                .frame(width: 58, height: 58)
                .background(
                    PresentationStyle.accent(scheme).opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 18))
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(22).editorialCard()
    }

    private func historyRow(_ entry: HistoryEntry) -> some View {
        HistoryCard(
            entry: entry, play: { play(entry) }, remove: { Task { await model.remove(entry) } })
    }
}
