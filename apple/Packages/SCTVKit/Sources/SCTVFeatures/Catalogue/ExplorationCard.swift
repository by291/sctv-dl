import SCTVCore
import SwiftUI

struct ExplorationCard: View {
    let programme: Programme
    let canShuffle: Bool
    let open: () -> Void
    let shuffle: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title2) private var compactTitleSize = 24
    @ScaledMetric(relativeTo: .title) private var wideTitleSize = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            if typeSize.isAccessibilitySize {
                compactContent
            } else {
                ViewThatFits(in: .horizontal) {
                    ExplorationLayout {
                        identity(wide: true)
                        cover(compact: false)
                    }.frame(minWidth: 540)
                    compactContent
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { backdrop }
        .clipShape(RoundedRectangle(cornerRadius: 28))
        // Decorative transforms must not enlarge the card's accessibility or pointer bounds.
        .contentShape(RoundedRectangle(cornerRadius: 28))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("catalogue-exploration")
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                label
                Spacer(minLength: 12)
                shuffleButton
            }
            VStack(alignment: .leading, spacing: 4) {
                label
                shuffleButton
            }
        }
    }

    private var label: some View {
        Label("栏目探索", systemImage: "sparkle")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(PresentationStyle.accent(scheme))
    }

    private var shuffleButton: some View {
        Button("换一个", systemImage: "shuffle", action: shuffle)
            .buttonStyle(.plain)
            .font(.subheadline)
            .disabled(!canShuffle)
            .frame(minHeight: 44)
    }

    private var compactContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            cover(compact: true)
                .frame(maxWidth: 340)
                .frame(maxWidth: .infinity)
            if typeSize.isAccessibilitySize {
                identity(wide: false)
            } else {
                HStack(spacing: 12) {
                    title(wide: false)
                    Spacer(minLength: 0)
                    Button(action: open) { entryIcon }
                        .buttonStyle(.plain)
                        .accessibilityLabel("查看节目")
                }
            }
        }
    }

    private func title(wide: Bool) -> some View {
        Text(programme.name)
            .font(.system(size: wide ? wideTitleSize : compactTitleSize, weight: .semibold))
            .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
            .minimumScaleFactor(typeSize.isAccessibilitySize ? 1 : 0.8)
            .accessibilityIdentifier("exploration-title")
    }

    private var entryIcon: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 20, weight: .semibold))
            .frame(width: 44, height: 44)
            .foregroundStyle(scheme == .dark ? Color.black : Color.white)
            .background(PresentationStyle.accent(scheme), in: Circle())
    }

    private func identity(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            title(wide: wide)
            Button(action: open) {
                HStack(spacing: 12) {
                    entryIcon
                    Text("查看节目")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PresentationStyle.accent(scheme))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cover(compact: Bool) -> some View {
        Artwork(url: programme.cover)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(PresentationStyle.surface(scheme), lineWidth: 3)
            }
            .rotationEffect(.degrees(3))
            .shadow(color: .black.opacity(scheme == .dark ? 0.24 : 0.14), radius: 12, x: 0, y: 8)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(PresentationStyle.surface(scheme).opacity(scheme == .dark ? 0.65 : 0.8))
                    .rotationEffect(.degrees(-7))
                    .scaleEffect(0.94)
                    .offset(x: -4, y: -5)
            }
            // Reserve the rotated edges so loading and title changes cannot move the cover.
            .padding(.horizontal, compact ? 24 : 8)
            .padding(.vertical, compact ? 14 : 18)
            .accessibilityHidden(true)
    }

    private var backdrop: some View {
        GeometryReader { geometry in
            ZStack {
                PresentationStyle.surface(scheme)
                PresentationStyle.accent(scheme).opacity(scheme == .dark ? 0.12 : 0.07)
                // Reuse the cached cover for ambient color without an extra image-analysis pipeline.
                Artwork(url: programme.cover)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .scaleEffect(1.5)
                    .blur(radius: 48)
                    .opacity(scheme == .dark ? 0.25 : 0.48)
                LinearGradient(
                    colors: [
                        PresentationStyle.surface(scheme).opacity(0.08),
                        PresentationStyle.surface(scheme).opacity(scheme == .dark ? 0.8 : 0.64),
                    ], startPoint: .topTrailing, endPoint: .bottomLeading)
                Ellipse()
                    .fill(PresentationStyle.surface(scheme).opacity(scheme == .dark ? 0.22 : 0.35))
                    .frame(width: geometry.size.width * 1.4, height: geometry.size.height * 0.75)
                    .rotationEffect(.degrees(-24))
                    .offset(x: -geometry.size.width * 0.25, y: geometry.size.height * 0.4)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Wide cards keep the cover dominant without depending on the title's intrinsic width.
private struct ExplorationLayout: Layout {
    private let spacing: CGFloat = 20

    private func widths(_ width: CGFloat) -> (text: CGFloat, artwork: CGFloat) {
        let artwork = min(440, (width - spacing) * 0.58)
        return (width - spacing - artwork, artwork)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 540
        let columns = widths(width)
        let text = subviews[0].sizeThatFits(.init(width: columns.text, height: nil))
        let artwork = subviews[1].sizeThatFits(.init(width: columns.artwork, height: nil))
        return CGSize(width: width, height: max(text.height, artwork.height))
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        let columns = widths(bounds.width)
        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading,
            proposal: .init(width: columns.text, height: nil))
        subviews[1].place(
            at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing,
            proposal: .init(width: columns.artwork, height: nil))
    }
}
