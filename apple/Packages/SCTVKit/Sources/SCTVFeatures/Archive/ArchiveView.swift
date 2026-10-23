import SCTVCore
import SwiftUI

public struct ArchiveView: View {
    @Bindable private var model: ArchiveModel
    @State private var selecting = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var scheme
    private let favourite: Bool
    private let toggleFavourite: () -> Void
    private let play: (ProgrammeContent, BroadcastDate) -> Void
    private let download: ([ProgrammeContent], BroadcastDate) -> Void

    public init(
        model: ArchiveModel, favourite: Bool = false, toggleFavourite: @escaping () -> Void = {},
        play: @escaping (ProgrammeContent, BroadcastDate) -> Void,
        download: @escaping ([ProgrammeContent], BroadcastDate) -> Void
    ) {
        self.model = model
        self.favourite = favourite
        self.toggleFavourite = toggleFavourite
        self.play = play
        self.download = download
    }

    public var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 850 && !typeSize.isAccessibilitySize
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    archiveHeader
                    ArchiveDateSelection(model: model)
                    if let warning = model.warning {
                        InlineNotice(text: warning)
                        Button("重试") { Task { await model.refresh() } }
                    }
                    if model.hasPendingUpdate && !selecting {
                        Button("发现新内容，点此查看", systemImage: "arrow.clockwise") {
                            Task { await model.acceptUpdate() }
                        }.buttonStyle(.bordered)
                    }
                    if model.isLoading && model.contents.isEmpty {
                        ProgressView("载入节目").frame(maxWidth: .infinity).padding(24)
                    }
                    if wide {
                        HStack(alignment: .top, spacing: 28) {
                            if !model.fullEpisodes.isEmpty {
                                VStack(alignment: .leading, spacing: 16) {
                                    SectionHeading(title: "完整节目", subtitle: "一整期，慢慢看")
                                    LazyVStack(spacing: 16) {
                                        ForEach(model.fullEpisodes) { content in
                                            contentCard(content, featured: true).id(content.id)
                                        }
                                    }.scrollTargetLayout()
                                }.frame(maxWidth: .infinity, alignment: .topLeading)
                            }
                            if !model.clips.isEmpty {
                                VStack(alignment: .leading, spacing: 16) {
                                    clipsHeading
                                    LazyVStack(spacing: 12) {
                                        ForEach(model.clips) { content in
                                            contentCard(content, featured: false).id(content.id)
                                        }
                                    }.scrollTargetLayout()
                                }.frame(maxWidth: .infinity, alignment: .topLeading)
                            }
                        }
                    } else {
                        // Keep rows in one lazy stack so the scroll view can track
                        // their geometry without nested section-sized layouts.
                        if !model.fullEpisodes.isEmpty {
                            Section {
                                ForEach(model.fullEpisodes) { content in
                                    contentCard(content, featured: true).id(content.id)
                                }
                            } header: {
                                SectionHeading(title: "完整节目", subtitle: "一整期，慢慢看")
                                    .padding(.top, 12)
                            }
                        }
                        if !model.clips.isEmpty {
                            Section {
                                ForEach(model.clips) { content in
                                    contentCard(content, featured: false).id(content.id)
                                }
                            } header: {
                                clipsHeading
                                    .padding(.top, 12)
                            }
                        }
                    }
                    if !model.isLoading && model.contents.isEmpty && model.warning == nil {
                        ContentUnavailableView(
                            "暂无节目", systemImage: "play.rectangle",
                            description: Text("选择其他播出日期，或稍后刷新。"))
                    }
                }
                .scrollTargetLayout(isEnabled: !wide)
                .padding(20)
                .frame(maxWidth: 1160)
                .frame(maxWidth: .infinity)
            }
            .scrollPosition(id: $model.scrollAnchor)
            .refreshable { await model.refresh() }
            .accessibilityIdentifier("archive-scroll")
            .background(PresentationStyle.canvas(scheme))
        }
        .navigationTitle(model.programme.name)
        #if os(iOS)
            .toolbar(.visible, for: .navigationBar)
        #endif
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem {
                Button(selecting ? "取消选择" : "选择", systemImage: selecting ? "xmark" : "checklist") {
                    selecting.toggle()
                    model.setSelection([])
                }
                .labelStyle(.iconOnly).help(selecting ? "取消选择" : "选择")
                .accessibilityIdentifier("archive-select")
            }
            #if os(macOS)
                ToolbarItem {
                    Button("刷新", systemImage: "arrow.clockwise") {
                        Task { await model.refresh() }
                    }
                    .labelStyle(.iconOnly).help("刷新")
                }
            #endif
        }
        .safeAreaInset(edge: .bottom) {
            if selecting {
                HStack {
                    Button("取消") {
                        selecting = false
                        model.setSelection([])
                    }
                    Spacer()
                    Button("下载所选（\(model.selection.count)）", systemImage: "arrow.down.circle") {
                        if let date = model.broadcast { download(model.selectedContents, date) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.selection.isEmpty || model.selection.count > 100)
                }
                .padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
                .padding(.horizontal, 20).padding(.bottom, 8)
            }
        }
        .task { await model.load() }
        .onDisappear { model.stop() }
    }

    private var clipsHeading: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                SectionHeading(title: "节目片段", count: model.clips.count)
                Spacer(minLength: 12)
                sortButton
            }
            VStack(alignment: .leading, spacing: 4) {
                SectionHeading(title: "节目片段", count: model.clips.count)
                sortButton
            }
        }
    }

    private var sortButton: some View {
        Button {
            model.ascending.toggle()
        } label: {
            Label(model.ascending ? "时间正序" : "时间倒序", systemImage: "arrow.up.arrow.down")
                .font(.subheadline)
                .fixedSize()
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(PresentationStyle.accent(scheme))
        .accessibilityIdentifier("archive-sort")
    }

    private var archiveHeader: some View {
        let layout =
            typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 18))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 22))
        return layout {
            if !typeSize.isAccessibilitySize {
                Artwork(url: model.programme.cover)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .frame(maxWidth: 340)
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("SCTV / 栏目档案").font(.caption.weight(.semibold))
                    .tracking(2).foregroundStyle(PresentationStyle.accent(scheme))
                Text(model.programme.name)
                    .font(.system(.title, design: .serif, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                Button(
                    favourite ? "已收藏" : "收藏栏目", systemImage: favourite ? "heart.fill" : "heart",
                    action: toggleFavourite
                )
                .buttonStyle(.bordered).buttonBorderShape(.capsule)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 8)
    }

    private func contentCard(_ content: ProgrammeContent, featured: Bool) -> some View {
        let vertical = featured || typeSize.isAccessibilitySize
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                activate(content)
            } label: {
                let layout =
                    vertical
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                    : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
                layout {
                    Artwork(url: content.cover ?? model.programme.cover)
                        .overlay(alignment: .bottomTrailing) {
                            Image(
                                systemName: selecting
                                    ? (model.selection.contains(content.id)
                                        ? "checkmark.circle.fill" : "circle") : "play.fill"
                            )
                            .font(.system(size: featured ? 20 : 14, weight: .semibold))
                            .frame(width: featured ? 48 : 32, height: featured ? 48 : 32)
                            .background(.regularMaterial, in: Circle()).padding(12)
                            .foregroundStyle(PresentationStyle.accent(scheme))
                        }
                        .clipShape(RoundedRectangle(cornerRadius: vertical ? 18 : 10))
                        .frame(width: vertical ? nil : 136)
                    Text(content.title)
                        .font(featured ? .title3.weight(.semibold) : .headline)
                        .foregroundStyle(.primary)
                        .lineLimit(
                            featured && !typeSize.isAccessibilitySize ? 2 : 3,
                            reservesSpace: !featured
                        )
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, vertical ? (featured ? 16 : 18) : 0)
                        .padding(.top, vertical ? (featured ? 8 : 18) : 0)
                        .padding(.bottom, vertical && !featured ? 18 : 0)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, vertical ? 0 : 12)
                .padding(.top, vertical ? 0 : 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(content.title)
            .accessibilityIdentifier("archive-play-\(content.id)")
            HStack(spacing: 12) {
                Text(content.publishedAt ?? model.broadcast?.date ?? "")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.trailing, 44)
            .frame(minHeight: typeSize.isAccessibilitySize ? 44 : 20)
            .overlay(alignment: .trailing) {
                Menu {
                    Button("播放", systemImage: "play") {
                        if let date = model.broadcast { play(content, date) }
                    }
                    Button("下载", systemImage: "arrow.down.circle") {
                        if let date = model.broadcast { download([content], date) }
                    }.accessibilityIdentifier("download-content-\(content.id)")
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(PresentationStyle.accent(scheme))
                .accessibilityLabel("节目操作")
                .accessibilityIdentifier("content-actions-\(content.id)")
            }
            .padding(.horizontal, 16)
            .padding(.top, typeSize.isAccessibilitySize ? 0 : 12)
            // Shared episode/clip insets contain the menu's full 44-point hit area.
            .padding(.bottom, typeSize.isAccessibilitySize ? 6 : 14)
        }
        .editorialCard()
        .overlay {
            if model.selection.contains(content.id) {
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(PresentationStyle.accent(scheme), lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
    }

    private func activate(_ content: ProgrammeContent) {
        if selecting {
            var ids = model.selection
            if !ids.insert(content.id).inserted { ids.remove(content.id) }
            model.setSelection(ids)
        } else if let date = model.broadcast {
            play(content, date)
        }
    }
}
