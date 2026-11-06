import SwiftUI

struct ChannelDetailView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    let channelID: String
    let initial: Channel
    /// Reports the updated channel, or `nil` when it was deleted.
    var onUpdate: (Channel?) -> Void

    @State private var channel: Channel?
    @State private var loadError: String?
    @State private var testModel = ""
    @State private var testResult: ChannelTestResult?
    @State private var testError: String?
    @State private var isTesting = false
    @State private var isSyncing = false
    @State private var showEdit = false
    @State private var confirmDelete = false
    @State private var modelQuery = ""
    @State private var toast: Toast?

    private var current: Channel { channel ?? initial }

    var body: some View {
        List {
            header
            if let message = current.errorMessage?.nilIfBlank {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.danger)
                        .textSelection(.enabled)
                }
            }
            testSection
            infoSection
            modelsSection
            if let mappings = current.settings?.modelMappings, !mappings.isEmpty {
                Section("模型映射") {
                    ForEach(mappings, id: \.self) { mapping in
                        HStack {
                            Text(mapping.from).font(.caption.monospaced())
                            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                            Text(mapping.to).font(.caption.monospaced())
                        }
                    }
                }
            }
            if let keys = current.disabledAPIKeys, !keys.isEmpty {
                disabledKeysSection(keys)
            }
            Section {
                Button(current.channelStatus == .enabled ? "停用渠道" : "启用渠道",
                       systemImage: current.channelStatus == .enabled ? "pause.circle" : "play.circle") {
                    Task { await setStatus(current.channelStatus == .enabled ? .disabled : .enabled) }
                }
                if current.channelStatus != .archived {
                    Button("归档", systemImage: "archivebox") { Task { await setStatus(.archived) } }
                }
                Button("删除渠道", systemImage: "trash", role: .destructive) { confirmDelete = true }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("编辑") { showEdit = true }.disabled(channel == nil)
            }
        }
        .sheet(isPresented: $showEdit) {
            if let channel {
                ChannelFormView(mode: .edit(channel)) { updated in
                    Task { await reload(fallback: updated) }
                    toast = Toast(message: "已保存")
                }
            }
        }
        .confirmationDialog("删除渠道？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除 \(current.name)", role: .destructive) { Task { await delete() } }
        } message: {
            Text("删除后无法恢复。")
        }
        .toast($toast)
        .refreshable { await reload() }
        .task { await reload() }
    }

    private var header: some View {
        Section {
            HStack(spacing: 14) {
                ProviderIcon(provider: current.provider, size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(current.name).font(.title3.weight(.semibold))
                    Text(current.provider.name).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(current.channelStatus)
            }
            .padding(.vertical, 4)
            if let loadError {
                Text(loadError).font(.caption).foregroundStyle(Theme.danger)
            }
        }
    }

    private var testSection: some View {
        Section {
            HStack {
                TextField("测试模型", text: $testModel)
                    .font(.callout.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Menu {
                    ForEach(current.supportedModels, id: \.self) { model in
                        Button(model) { testModel = model }
                    }
                } label: {
                    Image(systemName: "chevron.up.chevron.down")
                }
                .disabled(current.supportedModels.isEmpty)
            }
            Button {
                Task { await test() }
            } label: {
                HStack {
                    Label("测试连接", systemImage: "bolt.horizontal")
                    Spacer()
                    if isTesting { ProgressView() }
                }
            }
            .disabled(isTesting)
            if let testResult {
                HStack {
                    Image(systemName: testResult.success ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(testResult.success ? Theme.success : Theme.danger)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(testResult.success ? "连接正常" : "测试失败").font(.callout.weight(.medium))
                        if let detail = (testResult.success ? testResult.message : (testResult.error ?? testResult.message))?.nilIfBlank {
                            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(5).textSelection(.enabled)
                        }
                    }
                    Spacer()
                    Text(Fmt.latency(testResult.latency * 1000)).font(.callout.monospacedDigit())
                }
            }
            if let testError {
                Text(testError).font(.caption).foregroundStyle(Theme.danger).textSelection(.enabled)
            }
        } header: {
            Text("连通性")
        }
    }

    private var infoSection: some View {
        Section("配置") {
            KeyValueRow(key: "类型", value: current.type, monospaced: true)
            KeyValueRow(key: "Base URL", value: current.baseURL?.nilIfBlank ?? "默认", monospaced: true)
            KeyValueRow(key: "排序权重", value: String(current.orderingWeight ?? 0))
            KeyValueRow(key: "默认测试模型", value: current.defaultTestModel?.nilIfBlank ?? "—", monospaced: true)
            KeyValueRow(key: "自动同步模型", value: (current.autoSyncSupportedModels ?? false) ? "开" : "关")
            if let prefix = current.settings?.extraModelPrefix?.nilIfBlank {
                KeyValueRow(key: "模型前缀", value: prefix, monospaced: true)
            }
            if let tags = current.tags, !tags.isEmpty {
                HStack {
                    Text("标签").foregroundStyle(.secondary)
                    Spacer()
                    ForEach(tags, id: \.self) { Tag(text: $0) }
                }
            }
            if let remark = current.remark?.nilIfBlank {
                KeyValueRow(key: "备注", value: remark)
            }
            KeyValueRow(key: "创建时间", value: Fmt.dateTime(current.createdAt))
            KeyValueRow(key: "更新时间", value: Fmt.dateTime(current.updatedAt))
            if let disabledAt = current.autoDisabledAt {
                KeyValueRow(key: "自动停用于", value: Fmt.dateTime(disabledAt))
            }
        }
    }

    private var modelsSection: some View {
        let entries = current.allModelEntries ?? current.supportedModels.map { ChannelModelEntry(requestModel: $0, actualModel: $0, source: "direct") }
        let filtered = modelQuery.isEmpty ? entries : entries.filter { $0.requestModel.localizedCaseInsensitiveContains(modelQuery) || $0.actualModel.localizedCaseInsensitiveContains(modelQuery) }
        return Section {
            if entries.count > 8 {
                TextField("筛选模型", text: $modelQuery)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            ForEach(filtered.prefix(200), id: \.self) { entry in
                HStack {
                    Text(entry.requestModel).font(.callout.monospaced()).lineLimit(1)
                    Spacer()
                    if entry.actualModel != entry.requestModel {
                        Text("→ \(entry.actualModel)").font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if entry.source != "direct" {
                        Tag(text: entry.source)
                    }
                }
                .contextMenu { Button("拷贝", systemImage: "doc.on.doc") { Clipboard.copy(entry.requestModel) } }
            }
            if entries.isEmpty {
                Text("没有模型").font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text("支持的模型 (\(entries.count))")
                Spacer()
                Button {
                    Task { await sync() }
                } label: {
                    if isSyncing { ProgressView().controlSize(.mini) } else { Label("同步", systemImage: "arrow.triangle.2.circlepath") }
                }
                .font(.caption)
                .textCase(nil)
                .disabled(isSyncing)
            }
        }
    }

    private func disabledKeysSection(_ keys: [DisabledAPIKey]) -> some View {
        Section("已自动停用的密钥") {
            ForEach(keys, id: \.key) { key in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(Fmt.mask(key.key)).font(.callout.monospaced())
                        Spacer()
                        Button("恢复") { Task { await enableKey(key.key) } }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    HStack(spacing: 8) {
                        if let code = key.errorCode { Text("HTTP \(code)") }
                        if let date = key.disabledAt { Text(Fmt.relative(date)) }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    if let reason = key.reason?.nilIfBlank {
                        Text(reason).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func reload(fallback: Channel? = nil) async {
        guard let service = session.service else { return }
        do {
            let loaded = try await service.channel(id: channelID)
            channel = loaded
            loadError = nil
            if testModel.isEmpty { testModel = loaded.defaultTestModel ?? loaded.supportedModels.first ?? "" }
            onUpdate(loaded)
        } catch {
            if let fallback { channel = fallback; onUpdate(fallback) }
            loadError = error.localizedDescription
        }
    }

    private func test() async {
        guard let service = session.service else { return }
        isTesting = true
        testError = nil
        testResult = nil
        defer { isTesting = false }
        do {
            testResult = try await service.testChannel(id: channelID, model: testModel)
            UINotificationFeedbackGenerator().notificationOccurred(testResult?.success == true ? .success : .error)
        } catch {
            testError = error.localizedDescription
        }
    }

    private func sync() async {
        guard let service = session.service else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let result = try await service.syncChannelModels(id: channelID)
            toast = Toast(message: "已同步 \(result.supportedModels.count) 个模型")
            await reload()
        } catch {
            toast = Toast(message: error.localizedDescription, isError: true)
        }
    }

    private func setStatus(_ status: ResourceStatus) async {
        guard let service = session.service else { return }
        do {
            try await service.setChannelStatus(id: channelID, status: status)
            toast = Toast(message: "状态已更新为\(status.label)")
            await reload()
        } catch {
            toast = Toast(message: error.localizedDescription, isError: true)
        }
    }

    private func enableKey(_ key: String) async {
        guard let service = session.service else { return }
        do {
            try await service.enableChannelKey(channelID: channelID, key: key)
            toast = Toast(message: "密钥已恢复")
            await reload()
        } catch {
            toast = Toast(message: error.localizedDescription, isError: true)
        }
    }

    private func delete() async {
        guard let service = session.service else { return }
        do {
            try await service.deleteChannel(id: channelID)
            onUpdate(nil)
            dismiss()
        } catch {
            toast = Toast(message: error.localizedDescription, isError: true)
        }
    }
}
