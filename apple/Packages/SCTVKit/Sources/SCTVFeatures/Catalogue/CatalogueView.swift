import SCTVCore
import SwiftUI

public struct CatalogueView: View {
    @Bindable private var model: CatalogueModel
    private let open: (Programme) -> Void

    public init(model: CatalogueModel, open: @escaping (Programme) -> Void) {
        self.model = model
        self.open = open
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let warning = model.warning {
                    Label(warning, systemImage: "exclamationmark.triangle").font(.callout)
                        .foregroundStyle(.secondary)
                }
                if model.pending != nil {
                    Button("栏目有更新，点此查看") { Task { await model.acceptUpdate() } }.buttonStyle(
                        .bordered)
                }
                if model.programmes.isEmpty && model.isLoading {
                    ProgressView("载入栏目")
                } else if model.visibleProgrammes.isEmpty {
                    if !model.hasAcceptedSnapshot, model.warning != nil {
                        ContentUnavailableView {
                            Label("暂时无法载入栏目", systemImage: "wifi.exclamationmark")
                        } description: {
                            Text("检查网络连接后重试。")
                        } actions: {
                            Button("重试") { Task { await model.refresh() } }
                        }
                    } else if !model.search.isEmpty || model.favouritesOnly {
                        ContentUnavailableView.search(text: model.search)
                    } else {
                        ContentUnavailableView(
                            "暂无栏目", systemImage: "tv", description: Text("稍后下拉刷新查看。"))
                    }
                }
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 160, maximum: 280), spacing: 20)],
                    spacing: 24
                ) {
                    ForEach(model.visibleProgrammes) { programme in
                        Button {
                            open(programme)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Artwork(url: programme.cover).clipShape(
                                    RoundedRectangle(cornerRadius: 12))
                                HStack {
                                    Text(programme.name).font(.headline).foregroundStyle(.primary)
                                    if model.favouriteIDs.contains(programme.id) {
                                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                                            .accessibilityLabel("已收藏")
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(
                                model.favouriteIDs.contains(programme.id) ? "取消收藏" : "收藏栏目",
                                systemImage: "star"
                            ) {
                                Task { await model.toggleFavourite(programme) }
                            }
                        }
                    }
                }
                .scrollTargetLayout()
            }.padding()
        }
        .scrollPosition(id: $model.scrollAnchor)
        .navigationTitle("栏目")
        .searchable(text: $model.search, prompt: "搜索栏目")
        .toolbar {
            ToolbarItem {
                Menu("筛选", systemImage: "line.3.horizontal.decrease") {
                    Toggle("只看收藏", isOn: $model.favouritesOnly)
                    Toggle("按名称排序", isOn: $model.alphabetical)
                    Button("刷新", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
                }
            }
        }
        .refreshable { await model.refresh() }
        .task { await model.load() }
    }
}
