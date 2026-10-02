import Foundation

enum ManagedBatchAction: String, CaseIterable, Identifiable {
    case enable, disable, archive, delete, recover, sync, test
    var id: String { rawValue }
}

extension AxonStore {
    func authorizedChannelSecrets(_ target: ManagementTarget) async throws -> JSON {
        guard target.kind == .channel, let id = target.entityID else { throw ManagementError.changedTarget }
        let cli = try managementClient(target)
        let d = try await cli.channelSecrets(id: id)
        try validateTarget(target)
        return d
    }
    func managedOAuth(_ target: ManagementTarget, provider: String, action: String, body: JSON) async throws -> JSON {
        let cli = try managementClient(target)
        let result = try await cli.channelOAuth(provider: provider, action: action, body: body)
        try validateTarget(target)
        return result
    }
    func managedFetchModels(_ draft: ChannelDraft, target: ManagementTarget) async throws -> [String] {
        let cli = try managementClient(target)
        var input: [String: JSON] = ["channelType": .string(draft.type), "baseURL": .string(draft.baseURL),
            "apiKey": .string(draft.apiKey.isEmpty ? draft.credentials["apiKey"].string : draft.apiKey)]
        if input["apiKey"] == .string(""), let first = draft.credentials["apiKeys"].array.first { input["apiKey"] = first }
        if let id = target.entityID { input["channelID"] = .string(id) }
        let models = try await cli.fetchChannelModels(input: input)
        try validateTarget(target)
        return models
    }
    func managedRoutePreview(_ draft: ModelDraft, target: ManagementTarget) async throws -> JSON {
        try ChannelInputSchema.validate(draft.associations, type: "[ModelAssociationInput!]!")
        try ChannelSemantics.modelSettings(draft.settings)
        let result = try await managementClient(target).routeConnections(associations: draft.associations)
        try validateTarget(target)
        return result
    }
    func managedBatch(_ target: ManagementTarget, ids: [String], action: ManagedBatchAction) async throws -> String {
        guard !ids.isEmpty, Set(ids).count == ids.count else { throw ManagementError.invalidFields }
        let cli = try beginManagement(target)
        defer { endManagement() }
        var results: [String] = []
        // Save the selection/instance in the confirmation, never derive it after suspension.
        try validateTarget(target)
        switch (target.kind, action) {
        case (.channel, .enable): try await cli.channelBulkEnable(ids: ids)
        case (.channel, .disable): try await cli.channelBulkDisable(ids: ids)
        case (.channel, .archive): try await cli.channelBulkArchive(ids: ids)
        case (.channel, .delete): try await cli.channelBulkDelete(ids: ids)
        case (.channel, .recover): try await cli.channelBulkRecover(ids: ids)
        case (.model, .enable): try await cli.modelBulkEnable(ids: ids)
        case (.model, .disable): try await cli.modelBulkDisable(ids: ids)
        case (.model, .archive): try await cli.modelBulkArchive(ids: ids)
        case (.model, .delete): try await cli.modelBulkDelete(ids: ids)
        case (.channel, .sync), (.channel, .test):
            for id in ids {
                try validateTarget(target)
                guard let detail = try await cli.channelDetail(id: id) else { throw ManagementError.verification }
                if action == .sync {
                    let models = try await cli.syncChannelModels(id: id, pattern: detail["autoSyncModelPattern"].string)
                    guard let saved = try await cli.channelDetail(id: id), saved["supportedModels"] == models else { throw ManagementError.verification }
                    results.append("\(id): \(models.array.count)")
                } else {
                    let r = try await cli.testChannel(id: id)
                    results.append("\(id): \(r.success ? "OK" : "Failed") · \(r.latencyMs) ms")
                }
            }
        default: throw ManagementError.invalidFields
        }
        if ![.sync, .test].contains(action) {
            for id in ids {
                try validateTarget(target)
                let d = target.kind == .channel ? try await cli.channelDetail(id: id) : try await cli.modelDetail(id: id)
                if action == .delete { guard d == nil else { throw ManagementError.verification } }
                else {
                    let status = action == .enable || action == .recover ? "enabled" : action == .disable ? "disabled" : "archived"
                    guard d?["status"].string == status else { throw ManagementError.verification }
                }
            }
        }
        try validateTarget(target)
        await refresh(); try validateTarget(target)
        return results.isEmpty ? "Verified: \(ids.count)" : results.joined(separator: "\n")
    }
    func managedKeyAction(_ target: ManagementTarget, action: String, key: String = "", keys: [String] = [], model: String = "") async throws -> JSON {
        guard target.kind == .channel, let id = target.entityID else { throw ManagementError.changedTarget }
        let cli = try beginManagement(target); defer { endManagement() }
        let result: JSON
        switch action {
        case "testAll": result = try await cli.testChannelKeys(id: id, model: model.isEmpty ? nil : model)
        case "test": result = try await cli.testKey(id: id, key: key, model: model)
        case "enable": result = try await cli.enableKey(id: id, key: key)
        case "disable": result = try await cli.disableKey(id: id, key: key)
        case "enableAll": result = try await cli.enableAllKeys(id: id)
        case "enableSelected": result = try await cli.enableSelectedKeys(id: id, keys: keys)
        case "deleteDisabled":
            guard !keys.contains("__oauth__") else { throw ManagementError.invalidFields }
            result = try await cli.deleteDisabledKeys(id: id, keys: keys)
        default: throw ManagementError.invalidFields
        }
        try validateTarget(target)
        if action.hasPrefix("test") { return result }
        guard result.bool || result["success"].bool else { throw ManagementError.verification }
        let saved = try await cli.channelSecrets(id: id) // this screen has explicitly authorized secret reads.
        let disabled = Set(saved["disabledAPIKeys"].array.map { $0["key"].string })
        switch action {
        case "disable": guard disabled.contains(key) else { throw ManagementError.verification }
        case "enable": guard !disabled.contains(key) else { throw ManagementError.verification }
        case "enableAll": guard disabled.isEmpty else { throw ManagementError.verification }
        case "enableSelected", "deleteDisabled": guard disabled.isDisjoint(with: Set(keys)) else { throw ManagementError.verification }
        default: break
        }
        if action == "deleteDisabled" {
            guard Set(saved["credentials"]["apiKeys"].array.map(\.string)).isDisjoint(with: Set(keys)) else { throw ManagementError.verification }
        }
        try validateTarget(target)
        return saved
    }
}
