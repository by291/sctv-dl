import SwiftUI

public enum PresentationStyle {
    public static func accent(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 1, green: 0.58, blue: 0.43)
            : Color(red: 0.70, green: 0.24, blue: 0.14)
    }

    public static func canvas(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.08, green: 0.085, blue: 0.09)
            : Color(red: 0.97, green: 0.96, blue: 0.94)
    }

    public static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.13, green: 0.135, blue: 0.14)
            : Color(red: 1, green: 0.995, blue: 0.98)
    }
}

private struct EditorialCard: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background(PresentationStyle.surface(scheme), in: RoundedRectangle(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    public func editorialCard() -> some View { modifier(EditorialCard()) }
}

struct SectionHeading: View {
    let title: String
    var subtitle: String? = nil
    var count: Int? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.title2.weight(.bold))
                if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
            if let count {
                Text(count.formatted()).font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

struct InlineNotice: View {
    let text: String
    var symbol = "exclamationmark.circle"

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
    }
}
