import SCTVCore
import SwiftUI

struct HistoryCard: View {
    let entry: HistoryEntry
    let play: () -> Void
    let remove: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .headline) private var contentHeight = 82.0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                play()
            } label: {
                let layout =
                    typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
                    : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
                layout {
                    Artwork(url: entry.cover)
                        .overlay {
                            Image(systemName: "play.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(.black.opacity(0.4), in: Circle())
                                .accessibilityHidden(true)
                        }
                        .overlay(alignment: .bottom) {
                            if let duration = entry.durationMs, duration > 0 {
                                ProgressView(
                                    value: min(Double(entry.positionMs) / Double(duration), 1)
                                )
                                .tint(PresentationStyle.accent(scheme))
                                .accessibilityLabel("观看进度")
                            }
                        }
                        .clipShape(
                            RoundedRectangle(cornerRadius: typeSize.isAccessibilitySize ? 18 : 12)
                        )
                        .frame(width: typeSize.isAccessibilitySize ? nil : 136)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.title).font(.headline).foregroundStyle(.primary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(entry.programmeName) · \(entry.broadcastDate)")
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: typeSize.isAccessibilitySize ? nil : contentHeight)
                .contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(entry.title)
        }.padding(10).editorialCard()
            .accessibilityHint(entry.completed ? "点击再次观看" : "点击继续观看")
            .accessibilityAction(named: "删除记录", remove)
            #if os(iOS)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("删除记录", systemImage: "trash", role: .destructive, action: remove)
                }
            #else
                .contextMenu {
                    Button("删除记录", systemImage: "trash", role: .destructive, action: remove)
                }
            #endif
    }
}
