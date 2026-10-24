import SCTVCore
import SwiftUI

struct DownloadCard<Actions: View>: View {
    let task: DownloadTask
    let selected: Bool
    let selecting: Bool
    let selectionProgress: CGFloat
    let usesCardSelection: Bool
    let play: () -> Void
    let toggleSelection: () -> Void
    @ViewBuilder let actions: () -> Actions

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    private var secondaryText: Color {
        (scheme == .dark ? Color.white : Color.black).opacity(0.55)
    }

    @ViewBuilder var body: some View {
        if usesCardSelection {
            playableCard
                .overlay {
                    // Keep the hit target stable: an animated removal can otherwise
                    // leave the outgoing selection button intercepting playback taps.
                    Button {
                        toggleSelection()
                    } label: {
                        Color.clear.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .allowsHitTesting(selecting)
                    .accessibilityHidden(!selecting)
                    .accessibilityLabel(task.title)
                    .accessibilityValue(selected ? "已选择" : "未选择")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("select-download-\(task.content.contentID)")
                }
        } else {
            playableCard
        }
    }

    @ViewBuilder private var playableCard: some View {
        if case .completed = task.state {
            Button {
                play()
            } label: {
                taskCard.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .allowsHitTesting(!selecting)
            .accessibilityHidden(selecting)
            .accessibilityLabel(task.title)
            .accessibilityHint("点击播放已下载的节目")
            .accessibilityIdentifier("play-download-\(task.content.contentID)")
            // Keep the menu outside the playback button so it cannot trigger playback.
            .overlay(alignment: .bottomTrailing) {
                fadingCardActions.padding(12)
            }
        } else {
            taskCard
        }
    }

    private var taskCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            let layout =
                typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(
                    HStackLayout(alignment: .center, spacing: PresentationStyle.mediaCardSpacing))
            layout {
                Artwork(url: task.cover)
                    // Fix both dimensions so title height cannot shrink the fitted artwork.
                    .frame(
                        width: typeSize.isAccessibilitySize ? nil : 136,
                        height: typeSize.isAccessibilitySize ? nil : 136 * 9 / 16
                    )
                    .overlay(alignment: .bottomTrailing) {
                        if case .completed = task.state {
                            MediaCoverBadge(symbol: "play.fill").opacity(1 - selectionProgress)
                        }
                        MediaCoverBadge(
                            symbol: selected
                                ? "checkmark.circle.fill" : "circle"
                        ).opacity(selectionProgress)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title).font(.headline)
                        // Keep selected-row text readable without overriding button tint.
                        .foregroundStyle(scheme == .dark ? Color.white : Color.black)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(task.programmeName) · \(task.broadcastDate)")
                        .font(.caption).foregroundStyle(secondaryText)
                        .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                    Text(task.quality == .standard ? "标准画质" : "流畅画质")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(PresentationStyle.accent(scheme))
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider().opacity(0.5)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 8) {
                    taskStatus
                    Spacer(minLength: 4)
                    cardActionSpace
                }
                VStack(alignment: .leading, spacing: 8) {
                    taskStatus
                    HStack {
                        Spacer()
                        cardActionSpace
                    }
                }
            }
            .frame(minHeight: 44)
        }
        .padding(PresentationStyle.mediaCardInset).editorialCard()
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(PresentationStyle.accent(scheme), lineWidth: 2)
                .opacity(selected ? selectionProgress : 0)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder private var cardActionSpace: some View {
        if case .completed = task.state {
            Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
        } else {
            fadingCardActions
        }
    }

    @ViewBuilder private var fadingCardActions: some View {
        if selectionProgress < 1 {
            actions()
                .opacity(1 - selectionProgress)
                .allowsHitTesting(!selecting)
                .accessibilityHidden(selecting)
        }
    }

    private var taskStatus: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol(task.state))
                .foregroundStyle(PresentationStyle.accent(scheme))
            VStack(alignment: .leading, spacing: 5) { status(task.state) }
                .foregroundStyle(scheme == .dark ? Color.white : Color.black)
        }
    }

    @ViewBuilder private func status(_ state: DownloadState) -> some View {
        switch state {
        case .transferring(let received, let total):
            if let total, total > 0 {
                ProgressView(value: Double(received), total: Double(max(total, received)))
                    .accessibilityLabel("下载进度")
            } else {
                ProgressView().controlSize(.small)
            }
            Text(ByteCountFormatter.string(fromByteCount: received, countStyle: .file)).font(
                .caption
            ).foregroundStyle(secondaryText)
        case .completed(let file):
            Text(
                "已完成 · "
                    + ByteCountFormatter.string(fromByteCount: file.byteSize, countStyle: .file)
            ).font(
                .caption
            ).foregroundStyle(secondaryText)
        case .queued: Text("等待下载").font(.caption)
        case .paused(let resume): Text(resume == nil ? "已暂停，可重新下载" : "已暂停").font(.caption)
        case .publishing: ProgressView("正在保存文件")
        case .cancelled: Text("已取消").font(.caption)
        case .interrupted(let reason), .transferFailed(let reason, _),
            .publicationFailed(let reason, _):
            Text(reason).font(.caption).foregroundStyle(secondaryText)
        case .missingFile: Text("文件已移动或删除").font(.caption).foregroundStyle(secondaryText)
        }
    }

    private func symbol(_ state: DownloadState) -> String {
        switch state {
        case .completed: "checkmark.circle"
        case .paused: "pause.circle"
        case .transferFailed, .publicationFailed, .missingFile, .interrupted:
            "exclamationmark.circle"
        default: "arrow.down.circle"
        }
    }
}
