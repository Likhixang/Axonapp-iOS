import SwiftUI

@MainActor
@Observable
final class PlaygroundModel {
    struct Message: Identifiable, Equatable {
        let id = UUID()
        var role: ChatTurn.Role
        var text: String
        var reasoning: String = ""
        var error: String?
        var isStreaming = false
    }

    var messages: [Message] = []
    var input = ""
    var options = PlaygroundOptions(model: "")
    var availableModels: [String] = []
    var modelsError: String?
    private(set) var isSending = false
    private var task: Task<Void, Never>?

    func loadModels(_ service: AxonService) async {
        do {
            let models = try await service.playgroundModels()
            availableModels = models
            modelsError = nil
            if options.model.isEmpty || !models.contains(options.model) {
                options.model = UserDefaults.standard.string(forKey: "axon.playground.model").flatMap { models.contains($0) ? $0 : nil }
                    ?? models.first ?? ""
            }
        } catch {
            modelsError = error.localizedDescription
        }
    }

    func send(client: APIClient) {
        let text = input.trimmed
        guard !text.isEmpty, !isSending, !options.model.isEmpty else { return }
        input = ""
        messages.append(Message(role: .user, text: text))
        start(client: client)
    }

    func regenerate(client: APIClient) {
        guard !isSending else { return }
        if messages.last?.role == .assistant { messages.removeLast() }
        guard messages.last?.role == .user else { return }
        start(client: client)
    }

    func stop() {
        task?.cancel()
    }

    func clear() {
        stop()
        messages.removeAll()
    }

    private func start(client: APIClient) {
        UserDefaults.standard.set(options.model, forKey: "axon.playground.model")
        let turns = messages.filter { $0.error == nil && !$0.text.isEmpty }.map { ChatTurn(role: $0.role, text: $0.text) }
        messages.append(Message(role: .assistant, text: "", isStreaming: true))
        let index = messages.count - 1
        isSending = true
        let service = PlaygroundService(client: client)
        let options = options

        task = Task { [weak self] in
            do {
                for try await chunk in service.stream(turns: turns, options: options) {
                    guard let self else { return }
                    switch chunk {
                    case .text(let delta): self.messages[index].text += delta
                    case .reasoning(let delta): self.messages[index].reasoning += delta
                    case .finish: break
                    }
                }
            } catch is CancellationError {
            } catch {
                if let self, (error as? URLError)?.code != .cancelled {
                    self.messages[index].error = error.localizedDescription
                }
            }
            guard let self else { return }
            if self.messages.indices.contains(index) {
                self.messages[index].isStreaming = false
                if self.messages[index].text.isEmpty && self.messages[index].error == nil && Task.isCancelled {
                    self.messages[index].error = "已停止"
                }
            }
            self.isSending = false
        }
    }
}

struct PlaygroundView: View {
    @Environment(SessionStore.self) private var session
    @State private var model = PlaygroundModel()
    @State private var showSettings = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    if model.messages.isEmpty {
                        emptyState
                    }
                    ForEach(model.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.messages.last?.text) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onChange(of: model.messages.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
        .safeAreaInset(edge: .bottom) { composer }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("对话测试")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { modelMenu }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                Menu {
                    Button("重新生成", systemImage: "arrow.clockwise") {
                        if let client = session.service?.client { model.regenerate(client: client) }
                    }
                    .disabled(model.messages.isEmpty || model.isSending)
                    Button("清空对话", systemImage: "trash", role: .destructive) { model.clear() }
                        .disabled(model.messages.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            PlaygroundSettingsSheet(options: $model.options)
                .presentationDetents([.medium, .large])
        }
        .task(id: session.selectedProjectID) {
            if let service = session.service { await model.loadModels(service) }
        }
    }

    private var modelMenu: some View {
        Menu {
            if model.availableModels.isEmpty {
                Text(model.modelsError ?? "没有可用模型")
            }
            Picker("模型", selection: $model.options.model) {
                ForEach(model.availableModels, id: \.self) { Text($0).tag($0) }
            }
        } label: {
            HStack(spacing: 4) {
                Text(model.options.model.isEmpty ? "选择模型" : model.options.model)
                    .font(.subheadline.weight(.semibold).monospaced())
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.caption2.weight(.bold))
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: 220)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(Theme.accent.gradient)
            Text("通过网关直接与模型对话").font(.headline)
            Text("请求会经过 AxonHub 的路由与负载均衡，并记录在请求日志中（来源：调试）。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let error = model.modelsError {
                Text(error).font(.caption).foregroundStyle(Theme.danger)
            }
        }
        .padding(.top, 80)
        .padding(.horizontal, 24)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("输入消息", text: $model.input, axis: .vertical)
                .lineLimit(1...6)
                .focused($inputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Button {
                if model.isSending {
                    model.stop()
                } else if let client = session.service?.client {
                    model.send(client: client)
                }
            } label: {
                Image(systemName: model.isSending ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 34))
                    .symbolRenderingMode(.hierarchical)
            }
            .disabled(!model.isSending && (model.input.trimmed.isEmpty || model.options.model.isEmpty))
            .accessibilityLabel(model.isSending ? "停止" : "发送")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

private struct MessageBubble: View {
    let message: PlaygroundModel.Message
    @State private var showReasoning = false

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .user { Spacer(minLength: 48) }
            VStack(alignment: .leading, spacing: 8) {
                if !message.reasoning.isEmpty {
                    DisclosureGroup(isExpanded: $showReasoning) {
                        Text(message.reasoning)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } label: {
                        Label(message.isStreaming && message.text.isEmpty ? "思考中…" : "思考过程", systemImage: "brain")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if !message.text.isEmpty {
                    Text(markdown(message.text))
                        .textSelection(.enabled)
                } else if message.isStreaming && message.reasoning.isEmpty {
                    TypingIndicator()
                }
                if let error = message.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.danger)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .foregroundStyle(message.role == .user ? Color.white : Color.primary)
            .background(
                message.role == .user ? AnyShapeStyle(Theme.accent.gradient) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .contextMenu {
                Button("拷贝", systemImage: "doc.on.doc") { Clipboard.copy(message.text) }
            }
            if message.role == .assistant { Spacer(minLength: 24) }
        }
    }

    private func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

private struct TypingIndicator: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .frame(width: 7, height: 7)
                    .opacity(0.3 + 0.7 * abs(sin(phase + Double(index) * 0.8)))
            }
        }
        .foregroundStyle(.secondary)
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = .pi }
        }
    }
}

private struct PlaygroundSettingsSheet: View {
    @Binding var options: PlaygroundOptions
    @Environment(\.dismiss) private var dismiss
    @State private var useTemperature = false
    @State private var temperature = 0.7
    @State private var useMaxTokens = false
    @State private var maxTokens = 2048
    @State private var channelText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("系统提示词") {
                    TextField("可选", text: $options.systemPrompt, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section("参数") {
                    Toggle("温度", isOn: $useTemperature)
                    if useTemperature {
                        HStack {
                            Slider(value: $temperature, in: 0...2, step: 0.1)
                            Text(String(format: "%.1f", temperature)).monospacedDigit().frame(width: 36)
                        }
                    }
                    Toggle("最大输出 Token", isOn: $useMaxTokens)
                    if useMaxTokens {
                        Stepper("\(maxTokens)", value: $maxTokens, in: 64...128_000, step: 256)
                    }
                }
                Section {
                    TextField("渠道数字 ID（可选）", text: $channelText)
                        .keyboardType(.numberPad)
                } header: {
                    Text("指定渠道")
                } footer: {
                    Text("留空时由网关按负载均衡策略选择渠道。")
                }
            }
            .navigationTitle("对话设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { apply(); dismiss() }
                }
            }
            .onAppear {
                useTemperature = options.temperature != nil
                temperature = options.temperature ?? 0.7
                useMaxTokens = options.maxTokens != nil
                maxTokens = options.maxTokens ?? 2048
                channelText = options.channelID.map(String.init) ?? ""
            }
        }
    }

    private func apply() {
        options.temperature = useTemperature ? temperature : nil
        options.maxTokens = useMaxTokens ? maxTokens : nil
        options.channelID = Int(channelText.trimmed)
    }
}
