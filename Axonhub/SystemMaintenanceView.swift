import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// System Maintenance & Operations Center
struct SystemMaintenanceView: View {
    @ObservedObject var store: AxonStore

    @State private var loading = false
    @State private var noticeMessage: String? = nil
    @State private var errorMessage: String? = nil

    // Cache clear state
    @State private var showClearCacheConfirm = false
    @State private var clearingCache = false

    // GC Cleanup state
    @State private var showGcConfirm = false
    @State private var runningGc = false

    // Update check state
    @State private var checkingUpdate = false
    @State private var updateInfo: JSON = .null

    // Backup state
    @State private var backingUp = false
    @State private var exportDocument: AdminExportDocument? = nil
    @State private var showingExport = false

    var body: some View {
        List {
            if let err = errorMessage {
                Section {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }

            if let notice = noticeMessage {
                Section {
                    Text(notice).font(.caption).foregroundStyle(.green)
                }
            }

            Section(header: Text(NSLocalizedString("网关缓存诊断与清理", comment: ""))) {

                Button(role: .destructive) {
                    showClearCacheConfirm = true
                } label: {
                    HStack {
                        Label(NSLocalizedString("清空全部网关缓存", comment: ""), systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        if clearingCache {
                            ProgressView()
                        }
                    }
                }
                .disabled(clearingCache || !store.canManage)
            }

            Section(header: Text(NSLocalizedString("存储与碎片回收 (GC)", comment: ""))) {

                Button {
                    showGcConfirm = true
                } label: {
                    HStack {
                        Label(NSLocalizedString("执行存储垃圾回收 (GC)", comment: ""), systemImage: "trash")
                        Spacer()
                        if runningGc {
                            ProgressView()
                        }
                    }
                }
                .disabled(runningGc || !store.canManage)
            }

            Section(header: Text(NSLocalizedString("数据备份与导出", comment: ""))) {

                Button {
                    triggerBackup()
                } label: {
                    HStack {
                        Label(NSLocalizedString("生成并导出配置备份", comment: ""), systemImage: "square.and.arrow.up")
                        Spacer()
                        if backingUp {
                            ProgressView()
                        }
                    }
                }
                .disabled(backingUp || !store.canManage)
            }

            Section(header: Text(NSLocalizedString("版本检查与更新", comment: ""))) {
                Button {
                    checkUpdate()
                } label: {
                    HStack {
                        Label(NSLocalizedString("检查网关服务更新", comment: ""), systemImage: "arrow.up.circle")
                        Spacer()
                        if checkingUpdate {
                            ProgressView()
                        }
                    }
                }
                .disabled(checkingUpdate || !store.canManage)

                if !updateInfo.isNull {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(format: NSLocalizedString("当前版本: %@", comment: ""), updateInfo["currentVersion"].string))
                            .font(.caption)
                        Text(String(format: NSLocalizedString("最新版本: %@", comment: ""), updateInfo["latestVersion"].string))
                            .font(.caption)
                            .foregroundStyle(updateInfo["hasUpdate"].bool ? .green : .secondary)

                        if updateInfo["hasUpdate"].bool, !updateInfo["releaseUrl"].string.isEmpty {
                            Link(NSLocalizedString("查看更新日志", comment: ""), destination: URL(string: updateInfo["releaseUrl"].string)!)
                                .font(.caption)
                        }
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("系统运维", comment: ""))
        .alert(
            NSLocalizedString("清空全部网关缓存", comment: ""),
            isPresented: $showClearCacheConfirm
        ) {
            Button(NSLocalizedString("确认清理", comment: ""), role: .destructive) {
                performClearCache()
            }
            Button(NSLocalizedString("取消", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("这将重置运行时路由和状态缓存，网关将在下次请求时重新加载。确定执行吗？", comment: ""))
        }
        .alert(
            NSLocalizedString("执行存储垃圾回收 (GC)", comment: ""),
            isPresented: $showGcConfirm
        ) {
            Button(NSLocalizedString("立即执行", comment: ""), role: .destructive) {
                performGc()
            }
            Button(NSLocalizedString("取消", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("将异步清理过期的请求记录和文件碎片。确定开始吗？", comment: ""))
        }
        .fileExporter(
            isPresented: $showingExport,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "axonhub-backup-\(Int(Date().timeIntervalSince1970))"
        ) { outcome in
            if case .failure = outcome {
                errorMessage = NSLocalizedString("备份导出失败", comment: "")
            } else {
                noticeMessage = NSLocalizedString("备份已成功保存", comment: "")
            }
        }
    }

    private func performClearCache() {
        guard !clearingCache else { return }
        clearingCache = true
        errorMessage = nil
        noticeMessage = nil

        Task {
            defer { clearingCache = false }
            do {
                let client = try store.ensureClient()
                let input: [String: Any] = ["targets": ["all"]]
                let res = try await client.graphql(
                    query: AdminDocuments.adminClearCache,
                    variables: ["input": input]
                )
                let msg = res["clearCache"]["message"].string
                noticeMessage = msg.isEmpty ? NSLocalizedString("缓存清理完成", comment: "") : msg
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func performGc() {
        guard !runningGc else { return }
        runningGc = true
        errorMessage = nil
        noticeMessage = nil

        Task {
            defer { runningGc = false }
            do {
                let client = try store.ensureClient()
                let input: [String: Any] = ["dryRun": false]
                _ = try await client.graphql(
                    query: AdminDocuments.adminTriggerGcCleanup,
                    variables: ["input": input]
                )
                noticeMessage = NSLocalizedString("GC 清理任务已在网关后台启动", comment: "")
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func triggerBackup() {
        guard !backingUp else { return }
        backingUp = true
        errorMessage = nil

        Task {
            defer { backingUp = false }
            do {
                let client = try store.ensureClient()
                let res = try await client.graphql(query: AdminDocuments.adminBackup)
                let backupData = res["backup"]["data"].string
                if !backupData.isEmpty {
                    exportDocument = AdminExportDocument(text: backupData)
                    showingExport = true
                } else {
                    errorMessage = NSLocalizedString("网关未返回有效的备份数据", comment: "")
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func checkUpdate() {
        guard !checkingUpdate else { return }
        checkingUpdate = true
        errorMessage = nil

        Task {
            defer { checkingUpdate = false }
            do {
                let client = try store.ensureClient()
                let res = try await client.graphql(
                    query: AdminDocuments.adminCheckForUpdate,
                    variables: ["includeBeta": true]
                )
                updateInfo = res["checkForUpdate"]
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
