import SwiftUI

struct LoginView: View {
    @Environment(SessionStore.self) private var session

    @State private var server = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var serverCheck: ServerCheck = .unknown
    @FocusState private var focus: Field?

    enum Field { case server, email, password }

    enum ServerCheck: Equatable {
        case unknown, checking
        case ok(String)
        case notInitialized
        case failed(String)
    }

    private var canSubmit: Bool {
        !server.trimmed.isEmpty && !email.trimmed.isEmpty && !password.isEmpty && !isSubmitting
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    header
                    form
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(Theme.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.opacity)
                    }
                    submitButton
                    Text("使用 AxonHub 管理后台的账号登录。令牌只保存在本机钥匙串中。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
        }
        .onAppear {
            if server.isEmpty { server = session.lastServer }
            if email.isEmpty { email = session.lastEmail }
            if let message = session.bannerMessage {
                errorMessage = message
                session.bannerMessage = nil
            }
        }
        .task(id: server) { await checkServer() }
        .animation(.default, value: errorMessage)
    }

    private var header: some View {
        VStack(spacing: 14) {
            BrandMark(size: 72)
                .padding(.top, 32)
            Text("AxonHub").font(.largeTitle.weight(.bold))
            Text("AI 网关管理").font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var form: some View {
        VStack(spacing: 0) {
            field(icon: "globe", trailing: serverIndicator) {
                TextField("服务器地址，如 https://axon.example.com", text: $server)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .server)
                    .submitLabel(.next)
                    .onSubmit { focus = .email }
            }
            Divider().padding(.leading, 48)
            field(icon: "envelope") {
                TextField("邮箱", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focus = .password }
            }
            Divider().padding(.leading, 48)
            field(icon: "lock") {
                SecureField("密码", text: $password)
                    .textContentType(.password)
                    .focused($focus, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { Task { await submit() } }
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            serverHint.offset(y: 22)
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var serverHint: some View {
        switch serverCheck {
        case .ok(let version):
            Text("已连接 · AxonHub \(version)").font(.caption2).foregroundStyle(.secondary).padding(.leading, 4)
        case .notInitialized:
            Text("服务器尚未初始化，请先在网页端完成初始化").font(.caption2).foregroundStyle(Theme.warning).padding(.leading, 4)
        case .failed(let message):
            Text(message).font(.caption2).foregroundStyle(Theme.danger).lineLimit(1).padding(.leading, 4)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var serverIndicator: some View {
        switch serverCheck {
        case .checking: ProgressView().controlSize(.small)
        case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
        case .notInitialized: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.warning)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.danger)
        case .unknown:
            if !session.recentServers.isEmpty {
                Menu {
                    ForEach(session.recentServers, id: \.self) { item in
                        Button(item) { server = item }
                    }
                } label: {
                    Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
                }
            }
        }
    }

    private func field<Content: View>(icon: String, @ViewBuilder content: () -> Content) -> some View {
        field(icon: icon, trailing: EmptyView(), content: content)
    }

    private func field<Content: View, Trailing: View>(icon: String, trailing: Trailing, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            content()
            trailing
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
    }

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            HStack {
                if isSubmitting { ProgressView().tint(.white) }
                Text(isSubmitting ? "正在登录…" : "登录")
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 14))
        .disabled(!canSubmit)
        .padding(.top, 8)
    }

    private func checkServer() async {
        guard let url = APIClient.normalizeBaseURL(server) else {
            serverCheck = .unknown
            return
        }
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled else { return }
        serverCheck = .checking
        do {
            let status = try await APIClient.systemStatus(baseURL: url)
            guard !Task.isCancelled else { return }
            if !status.isInitialized {
                serverCheck = .notInitialized
                return
            }
            let health = try? await APIClient.health(baseURL: url)
            guard !Task.isCancelled else { return }
            serverCheck = .ok(health?.version ?? health?.build?.version ?? "")
        } catch {
            guard !Task.isCancelled else { return }
            serverCheck = .failed(error.localizedDescription)
        }
    }

    private func submit() async {
        guard canSubmit else { return }
        focus = nil
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await session.signIn(server: server, email: email, password: password)
            password = ""
        } catch {
            errorMessage = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}
