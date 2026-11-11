import SwiftUI
import Observation

/// The accent colour the user picked, saved in UserDefaults.
///
/// `Theme.accent` reads `color` from here, so every view that uses the accent is tracked by Observation
/// and redraws when the choice changes; the root view also passes it to `.tint`, which recolours
/// controls, navigation and tab bars, and the Liquid Glass tints built from `Theme.accent`.
@Observable
final class AccentSettings: @unchecked Sendable {
    static let shared = AccentSettings()

    var choice: AccentChoice {
        didSet { defaults.set(choice.storageValue, forKey: AccentChoice.storageKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.choice = AccentChoice(storageValue: defaults.string(forKey: AccentChoice.storageKey))
    }

    var color: Color { choice.color }

    func reset() { choice = .default }
}

extension AccentPreset {
    var color: Color {
        switch self {
        case .blue: return Color(uiColor: .systemBlue)
        case .indigo: return Color(uiColor: .systemIndigo)
        case .purple: return Color(uiColor: .systemPurple)
        case .pink: return Color(uiColor: .systemPink)
        case .red: return Color(uiColor: .systemRed)
        case .orange: return Color(uiColor: .systemOrange)
        case .yellow: return Color(uiColor: .systemYellow)
        case .green: return Color(uiColor: .systemGreen)
        case .mint: return Color(uiColor: .systemMint)
        case .teal: return Color(uiColor: .systemTeal)
        case .cyan: return Color(uiColor: .systemCyan)
        case .graphite: return Color(uiColor: .systemGray)
        }
    }
}

extension RGBColor {
    var color: Color { Color(red: red, green: green, blue: blue) }

    /// Converts a picked colour (any colour space) to sRGB components.
    init(_ color: Color) {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if !ui.getRed(&r, green: &g, blue: &b, alpha: &a) {
            var white: CGFloat = 0
            ui.getWhite(&white, alpha: &a)
            r = white; g = white; b = white
        }
        self.init(red: Double(r), green: Double(g), blue: Double(b))
    }
}

extension AccentChoice {
    var color: Color {
        switch self {
        case .preset(let preset): return preset.color
        case .custom(let rgb): return rgb.color
        }
    }
}

/// Settings → 强调色: preset swatches plus a free colour picker.
struct AccentColorSettingsView: View {
    @State private var settings = AccentSettings.shared
    @State private var customColor: Color = AccentSettings.shared.color

    private let columns = [GridItem(.adaptive(minimum: 52), spacing: 14)]

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "paintpalette.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(settings.color.gradient, in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("当前强调色").font(.subheadline.weight(.semibold))
                        Text(settings.choice.displayName).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("示例", isOn: .constant(true)).labelsHidden().allowsHitTesting(false)
                }
            }

            Section("预设") {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(AccentPreset.allCases) { preset in
                        Swatch(color: preset.color, selected: settings.choice == .preset(preset)) {
                            settings.choice = .preset(preset)
                            customColor = preset.color
                        }
                        .accessibilityLabel(preset.name)
                    }
                }
                .padding(.vertical, 6)
            }

            Section {
                ColorPicker("自定义颜色", selection: $customColor, supportsOpacity: false)
                    .onChange(of: customColor) { _, newValue in
                        let rgb = RGBColor(newValue)
                        if case .preset(let preset) = settings.choice, RGBColor(preset.color) == rgb { return }
                        settings.choice = .custom(rgb)
                    }
                if case .custom(let rgb) = settings.choice {
                    LabeledContent("颜色值") {
                        Text(rgb.hex).font(.callout.monospaced()).textSelection(.enabled)
                    }
                }
            } footer: {
                Text("强调色用在按钮、开关、底栏、图表和 Liquid Glass 的染色上，选好后立刻生效并自动保存。")
            }

            if settings.choice != .default {
                Section {
                    Button("恢复默认（iOS 蓝）") {
                        settings.reset()
                        customColor = settings.color
                    }
                }
            }
        }
        .navigationTitle("强调色")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct Swatch: View {
    let color: Color
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color.gradient)
                .frame(width: 44, height: 44)
                .overlay {
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.callout.weight(.bold))
                            .foregroundStyle(.white)
                    }
                }
                .overlay(Circle().strokeBorder(Color.primary.opacity(selected ? 0.35 : 0.08), lineWidth: selected ? 3 : 1)
                    .padding(-4))
                .frame(maxWidth: .infinity)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
