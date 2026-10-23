import SCTVCore
import SwiftUI

public struct CatalogueView: View {
    @Bindable private var model: CatalogueModel
    @State private var explorationID: String?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    private let open: (Programme) -> Void

    public init(model: CatalogueModel, open: @escaping (Programme) -> Void) {
        self.model = model
        self.open = open
    }

    private var exploration: Programme? {
        model.programmes.first { $0.id == explorationID } ?? model.programmes.first
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let programme = exploration {
                    explorationCard(programme)
                }
                catalogueHeading
                if let warning = model.warning { InlineNotice(text: warning) }
                if model.pending != nil {
                    Button {
                        Task { await model.acceptUpdate() }
                    } label: {
                        Label("发现新内容 · 点此更新", systemImage: "arrow.clockwise")
                            .font(.subheadline.weight(.medium)).padding(12)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(PresentationStyle.accent(scheme))
                    .background(PresentationStyle.accent(scheme).opacity(0.09), in: Capsule())
                }
                catalogueContents
            }
            .padding(20)
            .frame(maxWidth: 1200)
            .frame(maxWidth: .infinity)
        }
        .background(PresentationStyle.canvas(scheme))
        .accessibilityIdentifier("catalogue-scroll")
        .scrollPosition(id: $model.scrollAnchor)
        .navigationTitle("栏目")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            .toolbar(.visible, for: .navigationBar)
            .searchable(
                text: $model.search, placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: "搜索栏目")
        #else
            .searchable(text: $model.search, prompt: "搜索栏目")
            .toolbar {
                ToolbarItem {
                    Button("刷新", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
                }
            }
        #endif
        .refreshable { await model.refresh() }
        .task { await model.load() }
    }

    private var catalogueHeading: some View {
        HStack(alignment: .center, spacing: 12) {
            SectionHeading(title: "全部栏目", subtitle: "值得回看的每一刻")
            Button {
                model.favouritesOnly.toggle()
            } label: {
                Image(systemName: model.favouritesOnly ? "heart.fill" : "heart")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(model.favouritesOnly ? PresentationStyle.accent(scheme) : .secondary)
            .accessibilityLabel(model.favouritesOnly ? "显示全部栏目" : "只看收藏")
            Menu("排序", systemImage: "arrow.up.arrow.down") {
                Toggle("按名称排序", isOn: $model.alphabetical)
            }
            .menuStyle(.borderlessButton).fixedSize()
        }
    }

    @ViewBuilder private var catalogueContents: some View {
        if model.programmes.isEmpty && model.isLoading {
            ProgressView("载入栏目").frame(maxWidth: .infinity).padding(40)
        } else if model.visibleProgrammes.isEmpty {
            if !model.hasAcceptedSnapshot, model.warning != nil {
                ContentUnavailableView {
                    Label("暂时无法载入栏目", systemImage: "wifi.exclamationmark")
                } description: {
                    Text("检查网络连接后重试。")
                } actions: {
                    Button("重试") { Task { await model.refresh() } }
                }
            } else {
                ContentUnavailableView(
                    model.favouritesOnly ? "还没有收藏栏目" : "没有找到栏目",
                    systemImage: model.favouritesOnly ? "heart" : "magnifyingglass",
                    description: Text(
                        model.favouritesOnly ? "轻点封面上的爱心，把喜欢的栏目留在这里。" : "试试其他关键词，或下拉刷新。"))
            }
        } else {
            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(minimum: typeSize.isAccessibilitySize ? 280 : 156), spacing: 18)
                ],
                spacing: 22
            ) {
                ForEach(model.visibleProgrammes) { programme in
                    programmeCard(programme).id(programme.id)
                }
            }.scrollTargetLayout()
        }
    }

    private func programmeCard(_ programme: Programme) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                open(programme)
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Artwork(url: programme.cover)
                    Text(programme.name)
                        .font(.headline).foregroundStyle(.primary)
                        .lineLimit(typeSize.isAccessibilitySize ? 2 : 1, reservesSpace: true)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(programme.name)
        }
        .editorialCard()
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(alignment: .topTrailing) {
            Button {
                Task { await model.toggleFavourite(programme) }
            } label: {
                Image(
                    systemName: model.favouriteIDs.contains(programme.id) ? "heart.fill" : "heart"
                )
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(PresentationStyle.accent(scheme))
                .frame(width: 32, height: 32)
                .background(.regularMaterial, in: Circle())
                .contentShape(Circle())
            }
            .buttonStyle(.plain).padding(8)
            .accessibilityLabel(
                model.favouriteIDs.contains(programme.id)
                    ? "取消收藏 \(programme.name)" : "收藏 \(programme.name)")
        }
    }

    private func explorationCard(_ programme: Programme) -> some View {
        ExplorationCard(
            programme: programme, canShuffle: model.programmes.count > 1,
            open: { open(programme) },
            shuffle: {
                explorationID =
                    model.programmes.filter { $0.id != programme.id }.randomElement()?.id
            })
    }
}
