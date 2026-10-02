import SwiftUI
import UIKit

struct AddInstanceSheet: View {
    @ObservedObject var store: AxonStore
    private let instance: AxonInstance?
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var address: String = "https://"
    @State private var allowHTTP: Bool = false
    @State private var authType: AxonAuthType = .adminJWT
    @State private var email: String = ""
    @State private var secret: String = ""
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String? = nil

    init(store: AxonStore, instance: AxonInstance? = nil) {
        self.store = store
        self.instance = instance
        _name = State(initialValue: instance?.name ?? "")
        _address = State(initialValue: instance?.address ?? "https://")
        _allowHTTP = State(initialValue: instance?.allowHTTP ?? false)
        _authType = State(initialValue: instance?.authType ?? .adminJWT)
        _email = State(initialValue: instance?.adminEmail ?? "")
        // Never load an existing password, JWT or API key into the editor.
    }

    private var requiresNewSecret: Bool {
        guard let instance = instance else { return true }
        return instance.address != address.trimmingCharacters(in: .whitespacesAndNewlines) ||
            instance.authType != authType ||
            instance.adminEmail != email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (authType != .adminJWT || !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) &&
        (!requiresNewSecret || !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) &&
        !isSubmitting
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(NSLocalizedString("网关信息", comment: ""))) {
                    TextField(NSLocalizedString("名称 (例如：Production Axon)", comment: ""), text: $name)
                    TextField(NSLocalizedString("服务器地址 (https://...)", comment: ""), text: $address)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .keyboardType(.URL)
                    Toggle(NSLocalizedString("允许不安全 HTTP (仅限局域网/内网测试)", comment: ""), isOn: $allowHTTP)
                }

                Section(header: Text(NSLocalizedString("认证方式", comment: ""))) {
                    Picker(NSLocalizedString("方式", comment: ""), selection: $authType) {
                        ForEach(AxonAuthType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    if authType == .adminJWT {
                        TextField(NSLocalizedString("管理员邮箱", comment: ""), text: $email)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .keyboardType(.emailAddress)
                        SecureField(NSLocalizedString("管理员密码", comment: ""), text: $secret)
                    } else {
                        SecureField(NSLocalizedString("AxonHub API Key", comment: ""), text: $secret)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        Text(NSLocalizedString("API Key 仅可查看可用模型；仪表盘、渠道与审计请使用管理员账号。", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if instance != nil {
                        Text(NSLocalizedString("留空以保留现有凭据；更改地址、认证方式或邮箱时必须输入新凭据。", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if let err = errorMessage {
                    Section {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            .disabled(isSubmitting)
            .navigationTitle(NSLocalizedString(instance == nil ? "添加 AxonHub 网关" : "编辑 AxonHub 网关", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("取消", comment: "")) {
                        dismiss()
                    }
                    .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString(instance == nil ? "连接" : "保存", comment: "")) {
                        submit()
                    }
                    .disabled(!canSubmit)
                }
            }
            .interactiveDismissDisabled(isSubmitting)
        }
    }

    private func submit() {
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                if let instance = instance {
                    try await store.updateInstance(id: instance.id, name: name, address: address,
                        allowHTTP: allowHTTP, authType: authType, email: email, secret: secret)
                } else {
                    try await store.addInstance(name: name, address: address,
                        allowHTTP: allowHTTP, authType: authType, email: email, secret: secret)
                }
                dismiss()
            } catch let err as LocalizedError {
                errorMessage = err.errorDescription ?? err.localizedDescription
                isSubmitting = false
            } catch {
                errorMessage = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store: AxonStore
    @State private var showingAddSheet: Bool = false
    @State private var editingInstance: AxonInstance? = nil
    @State private var removingInstance: AxonInstance? = nil

    var body: some View {
        List {
            Section(header: Text(NSLocalizedString("连接", comment: ""))) {
                if store.instances.isEmpty {
                    Text(NSLocalizedString("尚未添加任何 AxonHub 实例", comment: ""))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(store.instances) { instance in
                        Button {
                            store.selectedID = instance.id
                            Task { await store.refresh() }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(instance.name)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Text(instance.address)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if instance.id == store.selectedID {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.accentColor)
                                        .accessibilityHidden(true)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .accessibilityAddTraits(instance.id == store.selectedID ? .isSelected : [])
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                removingInstance = instance
                            } label: {
                                Label(NSLocalizedString("移除", comment: ""), systemImage: "trash")
                            }
                            Button {
                                editingInstance = instance
                            } label: {
                                Label(NSLocalizedString("编辑实例", comment: ""), systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                        .contextMenu {
                            Button {
                                editingInstance = instance
                            } label: {
                                Label(NSLocalizedString("编辑实例", comment: ""), systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                removingInstance = instance
                            } label: {
                                Label(NSLocalizedString("移除", comment: ""), systemImage: "trash")
                            }
                        }
                    }
                }

                Button(action: { showingAddSheet = true }) {
                    Label(NSLocalizedString("添加新实例", comment: ""), systemImage: "plus")
                }
            }

            Section(header: Text(NSLocalizedString("应用", comment: ""))) {
                NavigationLink {
                    AppearanceView()
                } label: {
                    Text(NSLocalizedString("外观", comment: ""))
                }
                NavigationLink {
                    AboutView()
                } label: {
                    Text(NSLocalizedString("关于", comment: ""))
                }
            }
        }
        .navigationTitle(NSLocalizedString("设置", comment: ""))
        .sheet(isPresented: $showingAddSheet) {
            AddInstanceSheet(store: store)
        }
        .sheet(item: $editingInstance) { instance in
            AddInstanceSheet(store: store, instance: instance)
        }
        .confirmationDialog(
            String(format: NSLocalizedString("移除“%@”？", comment: ""), removingInstance?.name ?? ""),
            isPresented: Binding(
                get: { removingInstance != nil },
                set: { if !$0 { removingInstance = nil } }
            ),
            titleVisibility: .visible,
            presenting: removingInstance
        ) { instance in
            Button(NSLocalizedString("确认移除", comment: ""), role: .destructive) {
                store.deleteInstance(id: instance.id)
                removingInstance = nil
                Task { await store.refresh() }
            }
            Button(NSLocalizedString("取消", comment: ""), role: .cancel) {
                removingInstance = nil
            }
        } message: { _ in
            Text(NSLocalizedString("仅删除本机连接及 Keychain 凭据，不删除服务器。", comment: ""))
        }
    }
}

struct AboutView: View {
    private var appName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ??
            (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? ""
    }

    private var version: String {
        let release = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "—"
        let build = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "—"
        return "\(release) (\(build))"
    }

    private var appIcon: UIImage? {
        // App-icon sets are compiled as icon files, not regular image sets.
        // Resolve their generated names from the bundle rather than adding a duplicate asset.
        let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any]
        let primaryIcon = icons?["CFBundlePrimaryIcon"] as? [String: Any]
        let filenames = primaryIcon?["CFBundleIconFiles"] as? [String] ?? []
        for filename in filenames.reversed() {
            if let image = UIImage(named: filename) {
                return image
            }
        }
        return UIImage(named: "AppIcon")
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    if let appIcon = appIcon {
                        Image(uiImage: appIcon)
                            .resizable().scaledToFit().frame(width: 88, height: 88)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .accessibilityHidden(true)
                    }
                    Text(appName).font(.title2.bold())
                    Text("独立第三方客户端").font(.subheadline).foregroundStyle(.secondary)
                    Text(version).font(.caption.monospaced()).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 16)
            }
            Section("项目") {
                Link(destination: URL(string: "https://github.com/Likhixang/Axonapp-iOS")!) {
                    aboutLabel("源代码", symbol: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: URL(string: "https://github.com/Likhixang/Axonapp-iOS/issues")!) {
                    aboutLabel("问题反馈", symbol: "bubble.left.and.bubble.right")
                }
                Link(destination: URL(string: "https://github.com/Likhixang")!) {
                    HStack {
                        aboutLabel("开发者", symbol: "person.crop.circle")
                        Spacer()
                        Text("Likhixang").foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Link(destination: URL(string: "https://github.com/looplj/axonhub")!) {
                    HStack { Text("AxonHub"); Spacer(); Text("Apache-2.0").font(.caption).foregroundStyle(.secondary) }
                }
                Link(destination: URL(string: "https://github.com/lobehub/lobe-icons")!) {
                    HStack { Text("Lobe Icons"); Spacer(); Text("MIT").font(.caption).foregroundStyle(.secondary) }
                }
                NavigationLink {
                    ScrollView {
                        Text(licenseText).font(.footnote.monospaced()).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding()
                    }.navigationTitle("图标许可").navigationBarTitleDisplayMode(.inline)
                } label: { aboutLabel("图标许可", symbol: "doc.text") }
            } header: {
                Text("开源与致谢")
            } footer: {
                Text("仅使用 Apple 系统框架，无第三方运行时依赖。")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func aboutLabel(_ title: LocalizedStringKey, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).symbolVariant(.fill).foregroundStyle(Color.accentColor)
                .frame(width: 24).accessibilityHidden(true)
            Text(title).foregroundStyle(.primary)
        }.frame(minHeight: 32)
    }

    private var licenseText: String {
        guard let url = Bundle.main.url(forResource: "BrandIcons-LICENSE", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return obsText("许可文件未能读取") }
        return text
    }
}
