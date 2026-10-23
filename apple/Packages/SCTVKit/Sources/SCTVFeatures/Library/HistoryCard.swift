import SCTVCore
import SwiftUI

struct HistoryCard: View {
    let entry: HistoryEntry
    let play: () -> Void
    let remove: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

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
                            RoundedRectangle(cornerRadius: typeSize.isAccessibilitySize ? 18 : 10)
                        )
                        .frame(width: typeSize.isAccessibilitySize ? nil : 136)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(entry.title).font(.headline).foregroundStyle(.primary)
                            .lineLimit(3, reservesSpace: true)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(entry.programmeName) · \(entry.broadcastDate)")
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(entry.title)
            HStack {
                Button(entry.completed ? "再次观看" : "继续观看", systemImage: "play.fill") {
                    play()
                }
                .buttonStyle(.plain).font(.subheadline)
                .foregroundStyle(PresentationStyle.accent(scheme))
                .frame(minHeight: 44)
                Spacer()
                Menu {
                    Button("删除记录", role: .destructive) { remove() }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(PresentationStyle.accent(scheme))
                .accessibilityLabel("记录操作")
            }.padding(.top, 6)
        }.padding(12).editorialCard()
    }
}
