import SwiftUI

struct MediaCoverBadge: View {
    let symbol: String
    var large = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: large ? 20 : 14, weight: .semibold))
            .frame(width: large ? 48 : 32, height: large ? 48 : 32)
            .background(.regularMaterial, in: Circle())
            .foregroundStyle(PresentationStyle.accent(scheme))
            .padding(12)
            .accessibilityHidden(true)
    }
}
