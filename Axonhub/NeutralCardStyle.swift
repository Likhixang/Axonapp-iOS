import SwiftUI

/// Shared neutral surfaces. Accent colors belong to data and status, not every action.
struct NeutralCardSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.primary.opacity(scheme == .dark ? 0.12 : 0.065), lineWidth: 0.75)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(scheme == .dark ? 0.16 : 0.045), radius: 12, x: 0, y: 5)
    }
}

/// Rectangular tactile controls, never system-tinted capsules. Primary uses adaptive ink.
struct NeutralActionStyle: ButtonStyle {
    var primary = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(primary ? Color(.systemBackground) : Color.primary)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(primary ? Color.primary : Color(.tertiarySystemGroupedBackground))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(primary ? Color.clear : Color.primary.opacity(scheme == .dark ? 0.16 : 0.10), lineWidth: 0.75)
            }
            .shadow(color: Color.black.opacity(primary ? 0.10 : 0.025), radius: 2, x: 0, y: 1)
            .opacity(!enabled ? 0.42 : configuration.isPressed ? 0.72 : 1)
    }
}

struct NeutralActionFooter<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.55)
            content.padding(12)
        }.background(Color(.secondarySystemBackground).opacity(0.45))
    }
}

extension View {
    func neutralCard() -> some View { modifier(NeutralCardSurface()) }
}
