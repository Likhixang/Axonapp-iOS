import SwiftUI
import UIKit

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return NSLocalizedString("跟随系统", comment: "")
        case .light: return NSLocalizedString("浅色", comment: "")
        case .dark: return NSLocalizedString("深色", comment: "")
        }
    }

    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

func hexRGB(_ hex: String) -> UInt32? {
    let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    guard clean.count == 6, let value = UInt32(clean, radix: 16) else { return nil }
    return value
}

func resolvedAccentColor(_ hex: String) -> Color {
    guard let rgb = hexRGB(hex) else {
        return Color(red: 99 / 255, green: 102 / 255, blue: 241 / 255)
    }
    return Color(
        red: Double((rgb >> 16) & 255) / 255,
        green: Double((rgb >> 8) & 255) / 255,
        blue: Double(rgb & 255) / 255
    )
}

struct LiquidGlassBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color.black.opacity(0.035), radius: 10, x: 0, y: 3)
    }
}

extension View {
    func liquidGlass() -> some View {
        self.modifier(LiquidGlassBackground())
    }
}

struct AppearanceView: View {
    @AppStorage("appAppearance") private var appMode = AppearanceMode.system.rawValue
    @AppStorage("accentHex") private var hex = "#6366F1"
    @State private var custom = false
    let colors = ["#6366F1", "#007AFF", "#AF52DE", "#FF2D55", "#FF9500", "#34C759", "#00C7BE"]

    var body: some View {
        Form {
            Section(NSLocalizedString("应用外观", comment: "")) {
                Picker(NSLocalizedString("主题外观", comment: ""), selection: $appMode) {
                    ForEach(AppearanceMode.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
            }

            Section(NSLocalizedString("强调色", comment: "")) {
                HStack(spacing: 0) {
                    ForEach(colors, id: \.self) { c in
                        Button {
                            hex = c
                        } label: {
                            Circle()
                                .fill(resolvedAccentColor(c))
                                .frame(width: 32, height: 32)
                                .overlay {
                                    if hex.uppercased() == c.uppercased() {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.white)
                                            .font(.caption.bold())
                                    }
                                }
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        custom = true
                    } label: {
                        Circle()
                            .fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                            .frame(width: 32, height: 32)
                            .overlay {
                                Image(systemName: colors.contains(hex.uppercased()) ? "plus" : "checkmark")
                                    .foregroundColor(.white)
                                    .font(.caption.bold())
                                    .shadow(radius: 1.5)
                            }
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle(NSLocalizedString("外观", comment: ""))
        .sheet(isPresented: $custom) {
            CustomAccentEditor(hex: $hex)
        }
    }
}

struct CustomAccentEditor: View {
    @Binding var hex: String
    @Environment(\.dismiss) private var dismiss
    @State private var draft = Color.blue
    @State private var input = ""
    @State private var invalid = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ColorPicker(NSLocalizedString("选择颜色", comment: ""), selection: $draft, supportsOpacity: false)
                    TextField(NSLocalizedString("HEX，例如 #6366F1", comment: ""), text: $input)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onChange(of: input) { value in
                            invalid = false
                            if hexRGB(value) != nil {
                                draft = resolvedAccentColor(value)
                            }
                        }
                    if invalid {
                        Text(NSLocalizedString("请输入 6 位 HEX 颜色值。", comment: ""))
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("自定义强调色", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("取消", comment: "")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("完成", comment: "")) {
                        guard hexRGB(input) != nil else {
                            invalid = true
                            return
                        }
                        hex = input.hasPrefix("#") ? input.uppercased() : "#" + input.uppercased()
                        dismiss()
                    }
                }
            }
            .onAppear {
                input = hex
                draft = resolvedAccentColor(hex)
            }
        }
    }
}
