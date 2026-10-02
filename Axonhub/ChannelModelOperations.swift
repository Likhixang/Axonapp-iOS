import Foundation

extension AxonClient {
    /// Called only after an explicit operator authorization; not used by overview/detail.
    func channelSecrets(id: String) async throws -> JSON {
        let query = """
        query ChannelSecrets($id: ID!) {
          channels(first: 1, where: {id: $id}) { edges { node {
            id updatedAt credentials { apiKey apiKeys gcp { region projectID jsonData }
              oauth { accessToken refreshToken clientID expiresAt tokenType scopes } }
            disabledAPIKeys { key disabledAt errorCode expiresAt }
            settings {
              extraModelPrefix modelMappings { from to } autoTrimedModelPrefixes hideOriginalModels hideMappedModels lowercaseModelId
              proxy { type url username password disableConnectionReuse }
              transformOptions { forceArrayInstructions forceArrayInputs replaceDeveloperRoleWithSystem reasoningEffortMapping { from to } }
              headerOverrideOperations { op path from to value condition match { path eq } index splat }
              bodyOverrideOperations { op path from to value condition match { path eq } index splat }
              passThroughUserAgent passThroughBody rateLimit { rpm tpm maxConcurrent queueSize queueTimeoutMs }
              retryableStatusCodes retryableErrorPatterns { pattern regex } modelProtocols { model apiFormats enabled }
              providerQuota { commandCode { authCookie } }
            }
          } } }
        }
        """
        let d = try await graphql(query: query, variables: ["id": id])
        guard let node = d["channels"]["edges"].array.first?["node"], node["id"].string == id else { throw AxonAPIError.invalidResponse }
        guard case .object = node["credentials"] else { throw AxonAPIError.forbidden }
        return node
    }
    func duplicateChannel(sourceID: String, input: [String: JSON]) async throws -> String {
        let mutation = """
        mutation ChannelDuplicate($sourceID: ID!, $input: CreateChannelInput!) { duplicateChannel(sourceID: $sourceID, input: $input) { id } }
        """
        let d = try await graphql(query: mutation, variables: ["sourceID": sourceID, "input": JSON.object(input).foundationObject()])
        guard !d["duplicateChannel"]["id"].string.isEmpty else { throw ManagementError.verification }
        return d["duplicateChannel"]["id"].string
    }
    func fetchChannelModels(input: [String: JSON]) async throws -> [String] {
        let query = """
        query ChannelFetchModels($input: FetchModelsInput!) { fetchModels(input: $input) { models { id } error } }
        """
        let d = try await graphql(query: query, variables: ["input": JSON.object(input).foundationObject()])
        guard d["fetchModels"]["error"].isNull || d["fetchModels"]["error"].string.isEmpty else { throw AxonAPIError.invalidResponse }
        return d["fetchModels"]["models"].array.map { $0["id"].string }
    }
    func syncChannelModels(id: String, pattern: String) async throws -> JSON {
        let mutation = """
        mutation ChannelSyncModels($id: ID!, $pattern: String) { syncChannelModels(channelID: $id, pattern: $pattern) { channelID supportedModels } }
        """
        let d = try await graphql(query: mutation, variables: ["id": id, "pattern": pattern])
        guard d["syncChannelModels"]["channelID"].string == id else { throw ManagementError.verification }
        return d["syncChannelModels"]["supportedModels"]
    }
    func testChannelKeys(id: String, model: String?) async throws -> JSON {
        let mutation = """
        mutation ChannelTestKeys($id: ID!, $model: String) { testChannelAPIKeys(channelID: $id, modelID: $model) { channelID total successCount failedCount results { success latency disabled } } }
        """
        var vars: [String: Any] = ["id": id]; if let model = model { vars["model"] = model }
        let d = try await graphql(query: mutation, variables: vars)
        let result = d["testChannelAPIKeys"]
        guard result["channelID"].string == id, result["results"].array.count == result["total"].int,
              result["successCount"].int + result["failedCount"].int == result["total"].int else { throw AxonAPIError.invalidResponse }
        return result // No keyPrefix or untrusted provider prose crosses the UI boundary.
    }
    func routeConnections(associations: JSON) async throws -> JSON {
        let query = """
        query ModelRouteConnections($associations: [ModelAssociationInput!]!) { queryModelChannelConnections(associations: $associations) { channel { id name status } priority models { requestModel actualModel source } } }
        """
        return try await graphql(query: query, variables: ["associations": associations.foundationObject()])["queryModelChannelConnections"]
    }
    func unassociatedChannels() async throws -> JSON {
        let query = """
        query ModelUnassociatedChannels { queryUnassociatedChannels { channel { id name status } models } }
        """
        return try await graphql(query: query)["queryUnassociatedChannels"]
    }
    func providersCatalog() async throws -> JSON {
        let query = """
        query ModelProvidersCatalog { providersCatalog(filtered: false) { data source fetchedAt filtered } }
        """
        return try await graphql(query: query)["providersCatalog"]
    }
    func refreshProvidersCatalog() async throws -> JSON {
        let mutation = """
        mutation ModelRefreshProvidersCatalog { refreshProvidersCatalog { data source fetchedAt filtered } }
        """
        return try await graphql(query: mutation)["refreshProvidersCatalog"]
    }
    func bulkCreateModels(inputs: JSON) async throws -> [String] {
        let mutation = """
        mutation ModelBulkCreate($inputs: [CreateModelInput!]!) { bulkCreateModels(inputs: $inputs) { id } }
        """
        let d = try await graphql(query: mutation, variables: ["inputs": inputs.foundationObject()])
        let ids = d["bulkCreateModels"].array.map { $0["id"].string }
        guard ids.count == inputs.array.count, ids.allSatisfy({ !$0.isEmpty }) else { throw ManagementError.verification }
        return ids
    }
    func channelBulkEnable(ids: [String]) async throws {
        let mutation = """
        mutation ChannelBulkEnable($ids: [ID!]!) { bulkEnableChannels(ids: $ids) }
        """
        let d = try await graphql(query: mutation, variables: ["ids": ids])
        guard d["bulkEnableChannels"].bool else { throw ManagementError.verification }
    }
    func channelBulkDisable(ids: [String]) async throws {
        let mutation = """
        mutation ChannelBulkDisable($ids: [ID!]!) { bulkDisableChannels(ids: $ids) }
        """
        let d = try await graphql(query: mutation, variables: ["ids": ids])
        guard d["bulkDisableChannels"].bool else { throw ManagementError.verification }
    }
    func channelBulkArchive(ids: [String]) async throws {
        let mutation = """
        mutation ChannelBulkArchive($ids: [ID!]!) { bulkArchiveChannels(ids: $ids) }
        """
        let d = try await graphql(query: mutation, variables: ["ids": ids])
        guard d["bulkArchiveChannels"].bool else { throw ManagementError.verification }
    }
    func channelBulkDelete(ids: [String]) async throws {
        let mutation = """
        mutation ChannelBulkDelete($ids: [ID!]!) { bulkDeleteChannels(ids: $ids) }
        """
        let d = try await graphql(query: mutation, variables: ["ids": ids])
        guard d["bulkDeleteChannels"].bool else { throw ManagementError.verification }
    }
    func channelBulkRecover(ids: [String]) async throws {
        let mutation = """
        mutation ChannelBulkRecover($ids: [ID!]!) { bulkRecoverChannels(ids: $ids) }
        """
        let d = try await graphql(query: mutation, variables: ["ids": ids])
        guard d["bulkRecoverChannels"].bool else { throw ManagementError.verification }
    }
    func modelBulkEnable(ids: [String]) async throws {
        let mutation = """
        mutation ModelBulkEnable($ids: [ID!]!) { bulkEnableModels(ids: $ids) }
        """
        let d = try await graphql(query: mutation, variables: ["ids": ids])
        guard d["bulkEnableModels"].bool else { throw ManagementError.verification }
    }
    func modelBulkDisable(ids: [String]) async throws {
        let mutation = """
        mutation ModelBulkDisable($ids: [ID!]!) { bulkDisableModels(ids: $ids) }
        """
        let d = try await graphql(query: mutation, variables: ["ids": ids])
        guard d["bulkDisableModels"].bool else { throw ManagementError.verification }
    }
    func modelBulkArchive(ids: [String]) async throws {
        let mutation = """
        mutation ModelBulkArchive($ids: [ID!]!) { bulkArchiveModels(ids: $ids) }
        """
        let d = try await graphql(query: mutation, variables: ["ids": ids])
        guard d["bulkArchiveModels"].bool else { throw ManagementError.verification }
    }
    func modelBulkDelete(ids: [String]) async throws {
        let mutation = """
        mutation ModelBulkDelete($ids: [ID!]!) { bulkDeleteModels(ids: $ids) }
        """
        let d = try await graphql(query: mutation, variables: ["ids": ids])
        guard d["bulkDeleteModels"].bool else { throw ManagementError.verification }
    }
    func disableKey(id: String, key: String) async throws -> JSON {
        let mutation = """
        mutation ChannelDisableKey($id: ID!, $key: String!) { disableChannelAPIKey(channelID: $id, key: $key) }
        """
        return try await graphql(query: mutation, variables: ["id": id, "key": key])["disableChannelAPIKey"]
    }
    func enableKey(id: String, key: String) async throws -> JSON {
        let mutation = """
        mutation ChannelEnableKey($id: ID!, $key: String!) { enableChannelAPIKey(channelID: $id, key: $key) }
        """
        return try await graphql(query: mutation, variables: ["id": id, "key": key])["enableChannelAPIKey"]
    }
    func enableAllKeys(id: String) async throws -> JSON {
        let mutation = """
        mutation ChannelEnableAllKeys($id: ID!) { enableAllChannelAPIKeys(channelID: $id) }
        """
        return try await graphql(query: mutation, variables: ["id": id])["enableAllChannelAPIKeys"]
    }
    func enableSelectedKeys(id: String, keys: [String]) async throws -> JSON {
        let mutation = """
        mutation ChannelEnableSelectedKeys($id: ID!, $keys: [String!]!) { enableSelectedChannelAPIKeys(channelID: $id, keys: $keys) }
        """
        return try await graphql(query: mutation, variables: ["id": id, "keys": keys])["enableSelectedChannelAPIKeys"]
    }
    func deleteDisabledKeys(id: String, keys: [String]) async throws -> JSON {
        let mutation = """
        mutation ChannelDeleteDisabledKeys($id: ID!, $keys: [String!]!) { deleteDisabledChannelAPIKeys(channelID: $id, keys: $keys) { success } }
        """
        return try await graphql(query: mutation, variables: ["id": id, "keys": keys])["deleteDisabledChannelAPIKeys"]
    }
    func testKey(id: String, key: String, model: String) async throws -> JSON {
        let mutation = """
        mutation ChannelTestKey($id: ID!, $key: String!, $model: String) { testChannelAPIKey(channelID: $id, key: $key, modelID: $model) { success latency disabled } }
        """
        return try await graphql(query: mutation, variables: ["id": id, "key": key, "model": model])["testChannelAPIKey"]
    }
    func bulkCreateChannels(input: JSON) async throws -> JSON {
        let mutation = """
        mutation ChannelBulkCreate($input: BulkCreateChannelsInput!) { bulkCreateChannels(input: $input) { id } }
        """
        return try await graphql(query: mutation, variables: ["input": input.foundationObject()])["bulkCreateChannels"]
    }
    func bulkImportChannels(input: JSON) async throws -> JSON {
        let mutation = """
        mutation ChannelBulkImport($input: BulkImportChannelsInput!) { bulkImportChannels(input: $input) { success created failed channels { id } } }
        """
        return try await graphql(query: mutation, variables: ["input": input.foundationObject()])["bulkImportChannels"]
    }
    func bulkUpdateChannelOrdering(input: JSON) async throws -> JSON {
        let mutation = """
        mutation ChannelBulkOrdering($input: BulkUpdateChannelOrderingInput!) { bulkUpdateChannelOrdering(input: $input) { success updated channels { id orderingWeight } } }
        """
        return try await graphql(query: mutation, variables: ["input": input.foundationObject()])["bulkUpdateChannelOrdering"]
    }
    func saveChannelModelPrices(input: JSON, id: String) async throws -> JSON {
        let mutation = """
        mutation ChannelSavePrices($id: ID!, $input: [SaveChannelModelPriceInput!]!) { saveChannelModelPrices(channelId: $id, input: $input) { id modelID } }
        """
        return try await graphql(query: mutation, variables: ["input": input.foundationObject(), "id": id])["saveChannelModelPrices"]
    }
    func channelPrices(id: String) async throws -> JSON {
        let query = """
        query ChannelPrices($id: ID!) {
          channels(first: 1, where: {id: $id}) { edges { node { id channelModelPrices { modelID price {
            items { itemCode pricing { mode flatFee usagePerUnit usageTiered { tiers { upTo pricePerUnit } } }
              promptWriteCacheVariants { variantCode pricing { mode flatFee usagePerUnit usageTiered { tiers { upTo pricePerUnit } } } } }
            schedule { timezone overrides { name priority when { dailyTime { start end } weekdays dateRange { start end } }
              items { itemCode pricing { mode flatFee usagePerUnit usageTiered { tiers { upTo pricePerUnit } } }
                promptWriteCacheVariants { variantCode pricing { mode flatFee usagePerUnit usageTiered { tiers { upTo pricePerUnit } } } } } } }
          } } } } }
        }
        """
        let d = try await graphql(query: query, variables: ["id": id])
        guard let node = d["channels"]["edges"].array.first?["node"], node["id"].string == id else { throw AxonAPIError.invalidResponse }
        return .array(node["channelModelPrices"].array.map { .object(["modelId": $0["modelID"], "price": $0["price"]]) })
    }
    func clearChannelError(id: String) async throws {
        let mutation = """
        mutation ChannelClearError($id: ID!) { updateChannel(id: $id, input: {clearErrorMessage: true}) { id errorMessage } }
        """
        let d = try await graphql(query: mutation, variables: ["id": id])
        guard d["updateChannel"]["id"].string == id, d["updateChannel"]["errorMessage"].isNull else { throw ManagementError.verification }
    }
    func allManagedModels() async throws -> [ModelItem] {
        let query = """
        query ModelAllPages($after: Cursor) {
          models(first: 100, after: $after, orderBy: {direction: DESC, field: CREATED_AT}) {
            edges { node { id modelID name developer type group icon status remark } }
            pageInfo { hasNextPage endCursor } totalCount
          }
        }
        """
        var after: String?, seen = Set<String>(), result: [ModelItem] = []
        repeat {
            try Task.checkCancellation()
            var vars: [String: Any] = [:]; if let after = after { vars["after"] = after }
            let page = try await graphql(query: query, variables: vars)["models"]
            guard case .array = page["edges"], case .bool = page["pageInfo"]["hasNextPage"], case .number = page["totalCount"] else { throw AxonAPIError.invalidResponse }
            for e in page["edges"].array {
                let m = e["node"]
                guard seen.insert(m["id"].string).inserted else { throw AxonAPIError.invalidResponse }
                result.append(ModelItem(id: m["id"].string, modelID: m["modelID"].string,
                    name: m["name"].string, developer: m["developer"].string, type: m["type"].string,
                    group: m["group"].string, icon: m["icon"].string, status: m["status"].string,
                    remark: m["remark"].isNull ? nil : m["remark"].string))
            }
            if !page["pageInfo"]["hasNextPage"].bool { guard result.count == page["totalCount"].int else { throw AxonAPIError.invalidResponse }; break }
            let next = page["pageInfo"]["endCursor"].string
            guard !next.isEmpty, next != after else { throw AxonAPIError.invalidResponse }; after = next
        } while true
        return result
    }
}
