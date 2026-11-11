import Foundation

/// The app's accent colour choices: system presets (iOS blue by default) or a custom RGB colour.
/// Kept free of SwiftUI so the storage format can be unit tested; `AccentSettings` maps it to `Color`.
enum AccentPreset: String, CaseIterable, Identifiable, Sendable {
    case blue, indigo, purple, pink, red, orange, yellow, green, mint, teal, cyan, graphite

    var id: String { rawValue }

    var name: String {
        switch self {
        case .blue: return "蓝色（默认）"
        case .indigo: return "靛蓝"
        case .purple: return "紫色"
        case .pink: return "粉色"
        case .red: return "红色"
        case .orange: return "橙色"
        case .yellow: return "黄色"
        case .green: return "绿色"
        case .mint: return "薄荷"
        case .teal: return "蓝绿"
        case .cyan: return "青色"
        case .graphite: return "石墨"
        }
    }
}

struct RGBColor: Hashable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    /// Accepts `#RRGGBB`, `RRGGBB` or `#RGB`.
    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        if text.count == 3 { text = text.map { "\($0)\($0)" }.joined() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }

    var hex: String {
        func byte(_ component: Double) -> Int { Int((component * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }
}

enum AccentChoice: Hashable, Sendable {
    case preset(AccentPreset)
    case custom(RGBColor)

    static let storageKey = "appearance.accentColor"
    static let `default` = AccentChoice.preset(.blue)

    /// Reads the saved value: a preset name (`blue`) or a hex colour (`#FF6600`). Anything else is iOS blue.
    init(storageValue: String?) {
        guard let value = storageValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            self = .default
            return
        }
        if let preset = AccentPreset(rawValue: value) {
            self = .preset(preset)
        } else if value.hasPrefix("#"), let rgb = RGBColor(hex: value) {
            self = .custom(rgb)
        } else {
            self = .default
        }
    }

    var storageValue: String {
        switch self {
        case .preset(let preset): return preset.rawValue
        case .custom(let rgb): return rgb.hex
        }
    }

    var displayName: String {
        switch self {
        case .preset(let preset): return preset.name
        case .custom(let rgb): return "自定义 \(rgb.hex)"
        }
    }
}
