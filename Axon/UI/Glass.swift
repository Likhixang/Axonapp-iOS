import SwiftUI

// Liquid Glass on iOS 26 and later; the regular look (materials, bordered buttons) on iOS 17–25.
// System chrome (tab bar, navigation bars, toolbars, sheets) picks up Liquid Glass by itself when
// the app is built with the iOS 26 SDK, so these helpers only cover the app's own surfaces.

enum GlassSupport {
    static var isAvailable: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    @available(iOS 26.0, *)
    static func glass(tint: Color?, interactive: Bool) -> Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }
}

extension View {
    /// Liquid Glass in `shape` on iOS 26+, otherwise a material (or `fallback` colour) background.
    @ViewBuilder
    func adaptiveGlass<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(GlassSupport.glass(tint: tint, interactive: interactive), in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
        }
    }

    /// Card surface: glass on iOS 26+, the grouped secondary background below.
    @ViewBuilder
    func adaptiveCardBackground(cornerRadius: CGFloat = Theme.cardRadius) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(Color(.secondarySystemGroupedBackground), in: shape)
        }
    }

    /// `.glass` / `.glassProminent` buttons on iOS 26+, bordered buttons below.
    @ViewBuilder
    func adaptiveButtonStyle(prominent: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if prominent { self.buttonStyle(.glassProminent) } else { self.buttonStyle(.glass) }
        } else {
            if prominent { self.buttonStyle(.borderedProminent) } else { self.buttonStyle(.bordered) }
        }
    }

    /// Tab bar shrinks while scrolling down on iOS 26+.
    @ViewBuilder
    func adaptiveTabBarMinimize() -> some View {
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }

    /// Groups nearby glass shapes so they blend and morph together on iOS 26+.
    @ViewBuilder
    func adaptiveGlassContainer(spacing: CGFloat = 12) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }
}

/// Soft backdrop used behind glass cards so the glass has something to refract.
struct GlassBackdrop: View {
    var body: some View {
        if GlassSupport.isAvailable {
            ZStack {
                Color(.systemGroupedBackground)
                LinearGradient(colors: [Theme.accent.opacity(0.16), .clear, Color.purple.opacity(0.10)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .ignoresSafeArea()
        } else {
            Color(.systemGroupedBackground).ignoresSafeArea()
        }
    }
}
