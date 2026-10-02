import SwiftUI
import UniformTypeIdentifiers
import UIKit

@MainActor final class PlaygroundState: ObservableObject {
    @Published var identity = PlaygroundIdentity()
    @Published var catalog = PlaygroundCatalog()
    @Published var project = ""
    @Published var channel = ""
    @Published var gateway = false
    @Published var parameters = PlaygroundParameters()
    @Published var maxTokensText = "4096"
    @Published var input = ""
    @Published var images: [PlaygroundImage] = []
    @Published var messages: [PlaygroundMessage] = []
    @Published var busy = false
    @Published var loading = false
    @Published var error: String?
    @Published var finishReason = ""
    @Published var usage: JSON = .null
    private var boundInstance: AxonInstance?
    private var task: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var generation = UUID()
    private var loadGeneration = UUID()

    var models: [PlaygroundChoice] {
        gateway ? catalog.models : catalog.channels.first { $0.id == channel }?.models ?? []
    }
    func stop() {
        let wasBusy = busy
        generation = UUID(); task?.cancel(); task = nil; busy = false
        if wasBusy, messages.last?.role == "assistant" { messages[messages.count - 1].incomplete = true }
    }
    func leave() {
        stop(); loadGeneration = UUID(); loadTask?.cancel(); loadTask = nil; loading = false
    }
    func bind(store: AxonStore) {
        guard boundInstance != store.selectedInstance else {
            if store.selectedInstance != nil, !loading, !busy, catalog.channels.isEmpty, catalog.models.isEmpty {
                reload(store: store, identityNeeded: true)
            }
            return
        }
        leave(); boundInstance = store.selectedInstance
        messages = []; images = []; input = ""; identity = PlaygroundIdentity(); catalog = PlaygroundCatalog()
        parameters.model = ""; project = ""; channel = ""; gateway = false; error = nil
        finishReason = ""; usage = .null
        reload(store: store, identityNeeded: true)
    }
    func reload(store: AxonStore, identityNeeded: Bool = false) {
        guard !busy, let instance = store.selectedInstance else { return }
        loadTask?.cancel(); loadGeneration = UUID()
        let id = loadGeneration; loading = true; error = nil
        loadTask = Task { @MainActor [weak self, weak store] in
            guard let self = self, let store = store else { return }
            defer { if id == self.loadGeneration { self.loading = false; self.loadTask = nil } }
            do {
                let client = try store.ensureClient()
                let service = PlaygroundService()
                if identityNeeded {
                    let identity = try await service.identity(client: client)
                    try Task.checkCancellation()
                    guard store.selectedInstance == instance, id == self.loadGeneration else { return }
                    self.identity = identity
                    if client.authType == .adminJWT, !identity.projects.contains(where: { $0.id == self.project }) {
                        self.project = identity.projects.first?.id ?? ""
                        self.messages = []; self.images = []; self.input = ""
                    }
                    if client.authType == .apiKey { self.gateway = true }
                    else if !identity.canUseGateway { self.gateway = false }
                }
                let project = self.project
                let catalog = try await service.catalog(client: client, project: project, canUseGateway: self.identity.canUseGateway)
                try Task.checkCancellation()
                guard store.selectedInstance == instance, project == self.project, id == self.loadGeneration else { return }
                self.catalog = catalog
                if !catalog.channels.contains(where: { $0.id == self.channel }) { self.channel = catalog.channels.first?.id ?? "" }
                self.chooseModel()
            } catch {
                guard !Task.isCancelled, id == self.loadGeneration, store.selectedInstance == instance else { return }
                self.error = Self.safeError(error)
            }
        }
    }
    func chooseModel() {
        if !models.contains(where: { $0.id == parameters.model }) { parameters.model = models.first?.id ?? "" }
    }
    func changeProject(store: AxonStore) {
        stop(); messages = []; images = []; input = ""; catalog = PlaygroundCatalog(); channel = ""; parameters.model = ""
        reload(store: store)
    }
    func clear() { guard !busy else { return }; messages = []; finishReason = ""; usage = .null; error = nil }

    /// No requests to a model are made from bind/reload. This method is wired only to paid-action buttons.
    func run(store: AxonStore, retry: Bool = false) {
        guard !busy, !loading, let instance = store.selectedInstance else { return }
        do {
            guard instance.authType == .apiKey || !project.isEmpty else { throw PlaygroundError.invalidInput }
            guard let maxTokens = Int(maxTokensText), maxTokens > 0 else { throw PlaygroundError.invalidInput }
            parameters.maxTokens = maxTokens
            var conversation = messages
            if retry {
                guard let lastUser = conversation.lastIndex(where: { $0.role == "user" }) else { throw PlaygroundError.invalidInput }
                conversation = Array(conversation.prefix(lastUser + 1))
            } else {
                let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty || !images.isEmpty else { throw PlaygroundError.invalidInput }
                conversation.append(.user(text: text, images: images))
            }
            let client = try store.ensureClient()
            _ = try parameters.payload(auth: client.authType, messages: conversation)
            let settings = parameters; let project = self.project
            let channel = gateway ? "" : self.channel
            guard gateway || !channel.isEmpty else { throw PlaygroundError.invalidInput }
            messages = conversation
            messages.append(PlaygroundMessage(role: "assistant", parts: []))
            let index = messages.count - 1
            if !retry { input = ""; images = [] }
            busy = true; error = nil; finishReason = ""; usage = .null; generation = UUID()
            let id = generation
            task = Task { @MainActor [weak self, weak store] in
                guard let self = self, let store = store else { return }
                defer { if id == self.generation { self.busy = false; self.task = nil } }
                do {
                    let service = PlaygroundService()
                    try await service.stream(client: client, parameters: settings, messages: conversation, project: project, channel: channel) { [weak self, weak store] result in
                        guard let self = self, let store = store else { throw CancellationError() }
                        guard id == self.generation, store.selectedInstance == instance, self.project == project,
                              index < self.messages.count else { throw PlaygroundError.changedInstance }
                        self.messages[index] = result.message
                        self.finishReason = result.finishReason; self.usage = result.usage
                    }
                } catch {
                    guard !Task.isCancelled, id == self.generation, store.selectedInstance == instance else { return }
                    if index < self.messages.count { self.messages[index].incomplete = true }
                    self.error = Self.safeError(error)
                }
            }
        } catch { self.error = Self.safeError(error) }
    }
    func importImages(_ urls: [URL]) {
        do {
            guard images.count + urls.count <= 8 else { throw PlaygroundError.imageLimit }
            var imported: [PlaygroundImage] = []
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size > 0, size <= 10 * 1024 * 1024 else { throw PlaygroundError.imageLimit }
                let data = try Data(contentsOf: url)
                guard UIImage(data: data) != nil,
                      let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image),
                      let mime = type.preferredMIMEType else { throw PlaygroundError.unsupportedImage }
                imported.append(try PlaygroundImage(filename: url.lastPathComponent, mediaType: mime, data: data))
            }
            images.append(contentsOf: imported)
        } catch { self.error = Self.safeError(error) }
    }
    static func safeError(_ error: Error) -> String {
        if let safe = error as? PlaygroundError { return safe.localizedDescription }
        if let safe = error as? AxonAPIError { return safe.localizedDescription }
        if let network = error as? URLError, network.code == .timedOut { return AxonAPIError.timedOut.localizedDescription }
        return AxonAPIError.transport.localizedDescription // Never echo URLs, bearer tokens, or provider prose.
    }
}

/// Integration entry point. Pure native SwiftUI; no WebView or web-console redirect.
@MainActor struct PlaygroundView: View {
    @ObservedObject var store: AxonStore
    @StateObject private var state = PlaygroundState()
    @Environment(\.scenePhase) private var scenePhase
    @State private var importing = false
    @State private var settingsExpanded = true
    @State private var confirmClear = false

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if store.selectedInstance == nil {
                    Section { Text("请先连接一个 AxonHub 实例。") }
                } else {
                    settings
                    conversation
                    composer
                }
                if let error = state.error {
                    Section { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                }
                Color.clear.frame(height: 1).listRowSeparator(.hidden).id("playground-bottom")
            }
            .buttonStyle(.borderless) // Multiple buttons in a List row must not share its automatic row action.
            .onChange(of: state.messages) { _ in
                if state.busy { proxy.scrollTo("playground-bottom", anchor: .bottom) }
            }
        }
        .navigationTitle("模型测试")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { state.reload(store: store, identityNeeded: true) } label: { Label("刷新模型", systemImage: "arrow.clockwise") }
                    .disabled(state.busy || state.loading || store.selectedInstance == nil)
            }
        }
        .task { state.bind(store: store) }
        .onChange(of: store.selectedInstance) { _ in state.bind(store: store) }
        .onChange(of: scenePhase) { phase in if phase != .active { state.leave() } }
        .onDisappear { state.leave() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): state.importImages(urls)
            case .failure: state.error = NSLocalizedString("无法读取图片，请重新选择文件。", comment: "")
            }
        }
        .confirmationDialog("清空当前会话？不会删除服务端请求记录。", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("清空会话", role: .destructive) { state.clear() }
            Button("取消", role: .cancel) {}
        }
    }

    private var settings: some View {
        Section {
            DisclosureGroup("模型与参数", isExpanded: $settingsExpanded) {
                if store.canManage {
                    Picker("项目", selection: $state.project) {
                        Text("请选择项目").tag("")
                        ForEach(state.identity.projects) { Text($0.name).tag($0.id) }
                    }
                    .onChange(of: state.project) { _ in
                        // Initial identity loading sets project; that load already fetches the catalog.
                        if !state.loading { state.changeProject(store: store) }
                    }
                    if state.identity.canUseGateway {
                        Picker("模型来源", selection: $state.gateway) {
                            Text("指定渠道").tag(false)
                            Text("模型网关").tag(true)
                        }.pickerStyle(.segmented)
                        .onChange(of: state.gateway) { _ in state.chooseModel() }
                    }
                    if !state.gateway {
                        Picker("渠道", selection: $state.channel) {
                            Text("请选择渠道").tag("")
                            ForEach(state.catalog.channels) { Text($0.name).tag($0.id) }
                        }.onChange(of: state.channel) { _ in state.chooseModel() }
                    }
                }
                Picker("模型", selection: $state.parameters.model) {
                    Text("请选择模型").tag("")
                    ForEach(state.models) { Text($0.name).tag($0.id) }
                }
                HStack {
                    Text("温度")
                    Spacer()
                    Text(state.parameters.temperature, format: .number.precision(.fractionLength(1))).monospacedDigit()
                }
                Slider(value: $state.parameters.temperature, in: 0...2, step: 0.1) { Text("温度") }
                HStack {
                    Text("最大输出 Token")
                    TextField("最大输出 Token", text: $state.maxTokensText).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                }
                Text("系统提示词").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $state.parameters.system).frame(minHeight: 80).accessibilityLabel("系统提示词")
                Text("参数支持与图片识别取决于所选模型。 Playground 仅支持文本与图片输入。")
                    .font(.caption).foregroundStyle(.secondary)
            }.disabled(state.busy || state.loading)
            if state.loading { ProgressView("正在读取项目、渠道与模型…") }
            if store.selectedInstance?.authType == .apiKey {
                Text("使用当前实例 API Key 调用 /v1/chat/completions；项目由 Key 绑定，不使用管理员 JWT 调用此端点。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("使用当前登录 JWT 调用 /admin/playground/chat，不创建临时 API Key。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var conversation: some View {
        Section {
            if state.messages.isEmpty {
                Label("输入消息开始会话", systemImage: "bubble.left.and.bubble.right")
            }
            ForEach(state.messages) { message in
                VStack(alignment: .leading, spacing: 10) {
                    Text(message.role == "user" ? "用户" : "助手").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(Array(message.parts.enumerated()), id: \.offset) { _, part in
                        partView(part)
                    }
                    if message.incomplete { Text("响应未完成").font(.caption).foregroundStyle(.orange) }
                    if !message.text.isEmpty {
                        Button { UIPasteboard.general.string = message.text } label: { Label("复制文本", systemImage: "doc.on.doc") }
                            .font(.caption)
                    }
                }.padding(.vertical, 4)
            }
            if state.busy { ProgressView("正在生成…") }
            if !state.finishReason.isEmpty {
                HStack { Text("结束原因"); Spacer(); Text(state.finishReason).font(.caption).foregroundStyle(.secondary) }
            }
            if !state.usage.isNull {
                HStack {
                    Text("Token 用量")
                    Spacer()
                    Text(ManagementFormat.number(state.usage["prompt_tokens"]) + " / " + ManagementFormat.number(state.usage["completion_tokens"])).monospacedDigit()
                }
            }
            HStack {
                Button("重新生成（消耗额度）") { state.run(store: store, retry: true) }
                    .disabled(state.busy || state.loading || !state.messages.contains { $0.role == "user" })
                Spacer()
                Button("清空", role: .destructive) { confirmClear = true }.disabled(state.busy || state.messages.isEmpty)
            }
        } header: { Text("当前会话") } footer: {
            Text("切换实例或项目会清空会话。")
        }
    }
    @ViewBuilder private func partView(_ part: JSON) -> some View {
        switch part["type"].string {
        case "text":
            Text(.init(part["text"].string)).textSelection(.enabled)
        case "reasoning":
            DisclosureGroup("思考过程") { Text(part["text"].string).font(.callout).textSelection(.enabled) }
        case "file":
            if let data = Self.imageData(part["url"].string), let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 240).accessibilityLabel(part["filename"].string)
            } else {
                // Do not automatically fetch provider image URLs (privacy, signed-URL leakage).
                Label(part["filename"].string.isEmpty ? NSLocalizedString("模型返回的附件", comment: "") : part["filename"].string, systemImage: "photo")
            }
        default: EmptyView()
        }
    }
    private var composer: some View {
        Section {
            TextEditor(text: $state.input).frame(minHeight: 100).accessibilityLabel("输入消息")
                .disabled(state.busy)
            ForEach(state.images) { image in
                HStack {
                    if let preview = UIImage(data: image.data) {
                        Image(uiImage: preview).resizable().scaledToFit().frame(width: 50, height: 50)
                    }
                    Text(image.filename).font(.caption).lineLimit(2)
                    Spacer()
                    Button(role: .destructive) { state.images.removeAll { $0.id == image.id } } label: { Label("移除图片", systemImage: "xmark.circle") }
                        .labelStyle(.iconOnly).disabled(state.busy)
                }
            }
            HStack {
                Button { importing = true } label: { Label("添加图片", systemImage: "photo.badge.plus") }
                    .disabled(state.busy || state.images.count >= 8)
                Spacer()
                if state.busy {
                    Button("停止生成", role: .destructive) { state.stop() }
                } else {
                    Button("发送（消耗额度）") { state.run(store: store) }
                        .buttonStyle(.borderedProminent)
                        .disabled(state.loading || state.parameters.model.isEmpty || (state.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && state.images.isEmpty))
                }
            }
        } header: { Text("消息") } footer: {
            Text("点击发送或重新生成会实际调用模型并可能计费。图片仅随消息以 data URL 发送，不调用独立上传接口。每张最多 10 MB，每次最多 8 张。")
        }
    }
    private static func imageData(_ url: String) -> Data? {
        guard url.hasPrefix("data:image/"), let comma = url.firstIndex(of: ","),
              url[..<comma].hasSuffix(";base64") else { return nil }
        return Data(base64Encoded: String(url[url.index(after: comma)...]))
    }
}
