import Foundation
import NukeUI
import SwiftUI

public struct Artwork: View {
    private let url: URL?

    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale

    public init(url: URL?) { self.url = url }

    public var body: some View {
        Rectangle().fill(.clear)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    let request = ArtworkCache.request(
                        url: url, width: geometry.size.width, scale: displayScale)
                    LazyImage(request: request) { state in
                        if let image = state.image {
                            image.resizable().scaledToFill()
                        } else {
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            PresentationStyle.accent(scheme).opacity(0.22),
                                            PresentationStyle.accent(scheme).opacity(0.06),
                                        ], startPoint: .topLeading, endPoint: .bottomTrailing)
                                )
                                .overlay {
                                    Image(systemName: "play.rectangle")
                                        .font(.system(size: 32, weight: .ultraLight))
                                        .foregroundStyle(
                                            PresentationStyle.accent(scheme).opacity(0.6))
                                }
                        }
                    }
                    .pipeline(ArtworkCache.pipeline)
                    // Nuke's request comparison omits thumbnail options; reload only across buckets.
                    .id(request?.thumbnail)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            .clipped()
            .accessibilityHidden(true)
    }
}
