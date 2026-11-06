import Foundation

/// Typed access to the AxonHub admin GraphQL API (`/admin/graphql`).
/// All query documents follow `internal/server/gql/*.graphql` in looplj/axonhub.
struct AxonService: Sendable {
    let client: APIClient

    static let pageSize = 30

    // MARK: - Fragments

    private static let channelFields = """
    id createdAt updatedAt type baseURL name status supportedModels manualModels autoSyncSupportedModels
    tags defaultTestModel orderingWeight errorMessage remark autoDisabledAt
    """

    private static let channelDetailFields = channelFields + """
     settings { extraModelPrefix modelMappings { from to } }
     allModelEntries { requestModel actualModel source }
     disabledAPIKeys { key disabledAt errorCode reason }
    """

    private static let modelFields = """
    id createdAt developer modelID type name icon group status remark associatedChannelCount
    modelCard {
      toolCall temperature vision knowledge releaseDate
      reasoning { supported default }
      modalities { input output }
      cost { input output cacheRead cacheWrite }
      limit { context output }
    }
    """

    private static let apiKeyFields = """
    id createdAt updatedAt name key type status scopes allowedIps
    profiles { activeProfile profiles { name modelIDs channelTags } }
    project { id name }
    """

    private static let usageFields = """
    usageLogs(first: 1) { edges { node { promptTokens completionTokens totalTokens promptCachedTokens completionReasoningTokens totalCost } } }
    """

    private static let requestFields = """
    id createdAt modelID format source status stream clientIP userAgent reasoningEffort
    metricsLatencyMs metricsFirstTokenLatencyMs traceID
    channel { id name }
    apiKey { id name }
    """ + usageFields

    // MARK: - Helpers

    private func page<Node>(_ connection: Connection<Node>) -> Page<Node> {
        Page(items: connection.nodes, hasMore: connection.pageInfo.hasNextPage,
             cursor: connection.pageInfo.endCursor, totalCount: connection.totalCount)
    }

    private static func paging(after cursor: String?, first: Int = pageSize) -> [String: JSONValue] {
        var variables: [String: JSONValue] = ["first": .int(first)]
        if let cursor { variables["after"] = .string(cursor) }
        return variables
    }

    private static func order(_ field: String, _ direction: String = "DESC") -> JSONValue {
        ["field": .string(field), "direction": .string(direction)]
    }

    // MARK: - Me & projects

    func me() async throws -> UserInfo {
        struct R: Decodable { let me: UserInfo }
        let result: R = try await client.graphQL("""
        query {
          me { id email firstName lastName isOwner preferLanguage avatar scopes hasPassword
            roles { name }
            projects { projectID isOwner scopes effectiveScopes roles { name } } }
        }
        """)
        return result.me
    }

    func myProjects() async throws -> [Project] {
        struct R: Decodable { let myProjects: [Project] }
        let result: R = try await client.graphQL("query { myProjects { id name description status createdAt } }")
        return result.myProjects
    }

    func updatePassword(old: String?, new: String) async throws {
        struct R: Decodable { let updateMyPassword: Bool }
        var input: [String: JSONValue] = ["newPassword": .string(new)]
        if let old, !old.isEmpty { input["oldPassword"] = .string(old) }
        let _: R = try await client.graphQL(
            "mutation($input: UpdateMyPasswordInput!) { updateMyPassword(input: $input) }",
            variables: ["input": .object(input)]
        )
    }

    func systemVersion() async throws -> SystemVersion {
        struct R: Decodable { let systemVersion: SystemVersion }
        let result: R = try await client.graphQL("query { systemVersion { version commit buildTime goVersion platform uptime } }")
        return result.systemVersion
    }

    // MARK: - Dashboard

    func dashboard(window: TimeWindow) async -> DashboardSnapshot {
        var snapshot = DashboardSnapshot()
        let tw = JSONValue.string(window.rawValue)

        struct Core: Decodable {
            let dashboardOverview: DashboardOverview
            let tokenStats: TokenStats
            let dailyRequestStats: [DailyRequestStat]
        }
        struct Breakdown: Decodable {
            let requestStatsByModel: [ModelRequestCount]
            let costStatsByModel: [ModelCost2]
            let tokenStatsByModel: [ModelTokens]
        }
        struct Health: Decodable {
            let channelSuccessRates: [ChannelSuccessRate]
        }
        struct Speed: Decodable {
            let fastestModels: [FastestModel]
        }

        async let core: Core = client.graphQL("""
        query {
          dashboardOverview { totalRequests failedRequests averageResponseTime
            requestStats { requestsToday requestsThisWeek requestsLastWeek requestsThisMonth } }
          tokenStats { totalInputTokensToday totalOutputTokensToday totalCachedTokensToday
            totalInputTokensThisWeek totalOutputTokensThisWeek totalCachedTokensThisWeek
            totalInputTokensThisMonth totalOutputTokensThisMonth totalCachedTokensThisMonth
            totalInputTokensAllTime totalOutputTokensAllTime totalCachedTokensAllTime }
          dailyRequestStats { date count tokens cost }
        }
        """)
        async let breakdown: Breakdown = client.graphQL("""
        query($tw: String) {
          requestStatsByModel(timeWindow: $tw) { modelId count }
          costStatsByModel(timeWindow: $tw) { modelId cost }
          tokenStatsByModel(timeWindow: $tw) { modelId inputTokens outputTokens cachedTokens totalTokens }
        }
        """, variables: ["tw": tw])
        async let health: Health = client.graphQL("""
        query($tw: String) {
          channelSuccessRates(timeWindow: $tw, limit: 8) { channelId channelName channelType channelDisabled successCount failedCount totalCount successRate }
        }
        """, variables: ["tw": tw])
        async let speed: Speed = client.graphQL("""
        query($input: FastestChannelsInput!) {
          fastestModels(input: $input) { modelId modelName throughput latencyMs requestCount }
        }
        """, variables: ["input": ["timeWindow": window == .allTime ? "month" : tw, "limit": 5]])

        do {
            let value = try await core
            snapshot.overview = value.dashboardOverview
            snapshot.tokens = value.tokenStats
            snapshot.daily = value.dailyRequestStats
        } catch {
            snapshot.partialErrors.append(error.localizedDescription)
        }
        do {
            let value = try await breakdown
            snapshot.topModels = value.requestStatsByModel.sorted { $0.count > $1.count }
            snapshot.modelCosts = value.costStatsByModel.sorted { $0.cost > $1.cost }
            snapshot.modelTokens = value.tokenStatsByModel.sorted { $0.totalTokens > $1.totalTokens }
        } catch {
            snapshot.partialErrors.append(error.localizedDescription)
        }
        if let value = try? await health { snapshot.channelHealth = value.channelSuccessRates }
        if let value = try? await speed { snapshot.fastestModels = value.fastestModels }
        return snapshot
    }

    // MARK: - Requests

    struct RequestFilter: Hashable, Sendable {
        var status: RequestStatus?
        var model: String = ""
        var source: String?

        var isActive: Bool { status != nil || !model.trimmed.isEmpty || source != nil }

        var whereInput: JSONValue {
            var object: [String: JSONValue] = [:]
            if let status { object["status"] = .string(status.rawValue) }
            if let model = model.nilIfBlank { object["modelIDContainsFold"] = .string(model) }
            if let source { object["source"] = .string(source) }
            return .object(object)
        }
    }

    func requests(after cursor: String?, filter: RequestFilter) async throws -> Page<RequestLog> {
        struct R: Decodable { let requests: Connection<RequestLog> }
        var variables = Self.paging(after: cursor)
        variables["orderBy"] = Self.order("CREATED_AT")
        variables["where"] = filter.whereInput
        let result: R = try await client.graphQL("""
        query($first: Int, $after: Cursor, $orderBy: RequestOrder, $where: RequestWhereInput) {
          requests(first: $first, after: $after, orderBy: $orderBy, where: $where) {
            edges { node { \(Self.requestFields) } }
            pageInfo { hasNextPage endCursor }
            totalCount
          }
        }
        """, variables: variables)
        return page(result.requests)
    }

    func requestDetail(id: String) async throws -> RequestDetail {
        struct R: Decodable { let node: RequestDetail? }
        let result: R = try await client.graphQL("""
        query($id: ID!) {
          node(id: $id) {
            ... on Request {
              id createdAt modelID format source status stream clientIP userAgent reasoningEffort
              metricsLatencyMs metricsFirstTokenLatencyMs metricsReasoningDurationMs traceID contentSaved
              requestHeaders requestBody responseHeaders responseBody
              channel { id name }
              apiKey { id name }
              \(Self.usageFields)
              executions(first: 20, orderBy: { field: CREATED_AT, direction: ASC }) {
                edges { node {
                  id createdAt modelID upstreamModelID format status stream errorMessage responseStatusCode
                  metricsLatencyMs metricsFirstTokenLatencyMs requestURL
                  channel { id name }
                } }
              }
            }
          }
        }
        """, variables: ["id": .string(id)])
        guard let node = result.node else { throw APIError.graphQL(["请求不存在或没有权限查看"]) }
        return node
    }

    // MARK: - Channels

    struct ChannelFilter: Hashable, Sendable {
        var search: String = ""
        var status: ResourceStatus?

        var whereInput: JSONValue {
            var object: [String: JSONValue] = [:]
            if let status {
                object["status"] = .string(status.rawValue)
            } else {
                object["statusNEQ"] = "archived"
            }
            if let search = search.nilIfBlank { object["nameContainsFold"] = .string(search) }
            return .object(object)
        }
    }

    func channels(after cursor: String?, filter: ChannelFilter) async throws -> Page<Channel> {
        struct R: Decodable { let channels: Connection<Channel> }
        var variables = Self.paging(after: cursor, first: 50)
        variables["orderBy"] = Self.order("ORDERING_WEIGHT")
        variables["where"] = filter.whereInput
        let result: R = try await client.graphQL("""
        query($first: Int, $after: Cursor, $orderBy: ChannelOrder, $where: ChannelWhereInput) {
          channels(first: $first, after: $after, orderBy: $orderBy, where: $where) {
            edges { node { \(Self.channelFields) } }
            pageInfo { hasNextPage endCursor }
            totalCount
          }
        }
        """, variables: variables)
        return page(result.channels)
    }

    func channel(id: String) async throws -> Channel {
        struct R: Decodable { let node: Channel? }
        let result: R = try await client.graphQL("""
        query($id: ID!) { node(id: $id) { ... on Channel { \(Self.channelDetailFields) } } }
        """, variables: ["id": .string(id)])
        guard let node = result.node else { throw APIError.graphQL(["渠道不存在"]) }
        return node
    }

    func createChannel(_ input: [String: JSONValue]) async throws -> Channel {
        struct R: Decodable { let createChannel: Channel }
        let result: R = try await client.graphQL("""
        mutation($input: CreateChannelInput!) { createChannel(input: $input) { \(Self.channelFields) } }
        """, variables: ["input": .object(input)])
        return result.createChannel
    }

    func updateChannel(id: String, _ input: [String: JSONValue]) async throws -> Channel {
        struct R: Decodable { let updateChannel: Channel }
        let result: R = try await client.graphQL("""
        mutation($id: ID!, $input: UpdateChannelInput!) { updateChannel(id: $id, input: $input) { \(Self.channelFields) } }
        """, variables: ["id": .string(id), "input": .object(input)])
        return result.updateChannel
    }

    func setChannelStatus(id: String, status: ResourceStatus) async throws {
        struct R: Decodable { struct C: Decodable { let id: String }; let updateChannelStatus: C }
        let _: R = try await client.graphQL("""
        mutation($id: ID!, $status: ChannelStatus!) { updateChannelStatus(id: $id, status: $status) { id } }
        """, variables: ["id": .string(id), "status": .string(status.rawValue)])
    }

    func deleteChannel(id: String) async throws {
        struct R: Decodable { let deleteChannel: Bool }
        let _: R = try await client.graphQL("mutation($id: ID!) { deleteChannel(id: $id) }", variables: ["id": .string(id)])
    }

    func testChannel(id: String, model: String?) async throws -> ChannelTestResult {
        struct R: Decodable { let testChannel: ChannelTestResult }
        var input: [String: JSONValue] = ["channelID": .string(id)]
        if let model = model?.nilIfBlank { input["modelID"] = .string(model) }
        let result: R = try await client.graphQL("""
        mutation($input: TestChannelInput!) { testChannel(input: $input) { latency success message error } }
        """, variables: ["input": .object(input)])
        return result.testChannel
    }

    func syncChannelModels(id: String) async throws -> SyncModelsResult {
        struct R: Decodable { let syncChannelModels: SyncModelsResult }
        let result: R = try await client.graphQL("""
        mutation($id: ID!) { syncChannelModels(channelID: $id) { supportedModels manualModels } }
        """, variables: ["id": .string(id)])
        return result.syncChannelModels
    }

    /// Asks the server to list the upstream provider's models (`fetchModels`).
    func fetchUpstreamModels(type: String, baseURL: String, apiKey: String?, channelID: String?) async throws -> [String] {
        struct R: Decodable {
            struct Payload: Decodable { struct M: Decodable { let id: String }; let models: [M]; let error: String? }
            let fetchModels: Payload
        }
        var input: [String: JSONValue] = ["channelType": .string(type), "baseURL": .string(baseURL)]
        if let apiKey = apiKey?.nilIfBlank { input["apiKey"] = .string(apiKey) }
        if let channelID { input["channelID"] = .string(channelID) }
        let result: R = try await client.graphQL("""
        query($input: FetchModelsInput!) { fetchModels(input: $input) { models { id } error } }
        """, variables: ["input": .object(input)])
        if let error = result.fetchModels.error?.nilIfBlank, result.fetchModels.models.isEmpty {
            throw APIError.graphQL([error])
        }
        return result.fetchModels.models.map(\.id)
    }

    func enableChannelKey(channelID: String, key: String) async throws {
        struct R: Decodable { let enableChannelAPIKey: Bool }
        let _: R = try await client.graphQL("""
        mutation($id: ID!, $key: String!) { enableChannelAPIKey(channelID: $id, key: $key) }
        """, variables: ["id": .string(channelID), "key": .string(key)])
    }

    // MARK: - Models

    struct ModelFilter: Hashable, Sendable {
        var search: String = ""
        var status: ResourceStatus?

        var whereInput: JSONValue {
            var object: [String: JSONValue] = [:]
            if let status {
                object["status"] = .string(status.rawValue)
            } else {
                object["statusNEQ"] = "archived"
            }
            if let search = search.nilIfBlank {
                object["or"] = [
                    ["modelIDContainsFold": .string(search)],
                    ["nameContainsFold": .string(search)],
                    ["developerContainsFold": .string(search)],
                ]
            }
            return .object(object)
        }
    }

    func models(after cursor: String?, filter: ModelFilter) async throws -> Page<AIModel> {
        struct R: Decodable { let models: Connection<AIModel> }
        var variables = Self.paging(after: cursor, first: 50)
        variables["orderBy"] = Self.order("CREATED_AT")
        variables["where"] = filter.whereInput
        let result: R = try await client.graphQL("""
        query($first: Int, $after: Cursor, $orderBy: ModelOrder, $where: ModelWhereInput) {
          models(first: $first, after: $after, orderBy: $orderBy, where: $where) {
            edges { node { \(Self.modelFields) } }
            pageInfo { hasNextPage endCursor }
            totalCount
          }
        }
        """, variables: variables)
        return page(result.models)
    }

    func setModelStatus(id: String, status: ResourceStatus) async throws {
        struct R: Decodable { let updateModelStatus: Bool }
        let _: R = try await client.graphQL("""
        mutation($id: ID!, $status: ModelStatus!) { updateModelStatus(id: $id, status: $status) }
        """, variables: ["id": .string(id), "status": .string(status.rawValue)])
    }

    func deleteModel(id: String) async throws {
        struct R: Decodable { let deleteModel: Bool }
        let _: R = try await client.graphQL("mutation($id: ID!) { deleteModel(id: $id) }", variables: ["id": .string(id)])
    }

    /// Model ids the playground can call: enabled models plus every channel's supported models.
    func playgroundModels() async throws -> [String] {
        struct R: Decodable {
            let models: Connection<Lite>
            let channels: Connection<ChannelLite>
            struct Lite: Decodable, Sendable { let modelID: String }
            struct ChannelLite: Decodable, Sendable { let supportedModels: [String] }
        }
        let result: R = try await client.graphQL("""
        query {
          models(first: 500, where: { status: enabled }) { edges { node { modelID } } pageInfo { hasNextPage endCursor } }
          channels(first: 200, where: { status: enabled }) { edges { node { supportedModels } } pageInfo { hasNextPage endCursor } }
        }
        """)
        var seen = Set<String>()
        var ordered: [String] = []
        for id in result.models.nodes.map(\.modelID) + result.channels.nodes.flatMap(\.supportedModels) where seen.insert(id).inserted {
            ordered.append(id)
        }
        return ordered
    }

    // MARK: - API keys

    func apiKeys(after cursor: String?, search: String, includeArchived: Bool = false) async throws -> Page<APIKey> {
        struct R: Decodable { let apiKeys: Connection<APIKey> }
        var variables = Self.paging(after: cursor)
        variables["orderBy"] = Self.order("CREATED_AT")
        var whereInput: [String: JSONValue] = [:]
        if !includeArchived { whereInput["statusNEQ"] = "archived" }
        if let search = search.nilIfBlank { whereInput["nameContainsFold"] = .string(search) }
        if let projectID = client.projectID { whereInput["projectID"] = .string(projectID) }
        variables["where"] = .object(whereInput)
        let result: R = try await client.graphQL("""
        query($first: Int, $after: Cursor, $orderBy: APIKeyOrder, $where: APIKeyWhereInput) {
          apiKeys(first: $first, after: $after, orderBy: $orderBy, where: $where) {
            edges { node { \(Self.apiKeyFields) } }
            pageInfo { hasNextPage endCursor }
            totalCount
          }
        }
        """, variables: variables)
        return page(result.apiKeys)
    }

    func createAPIKey(name: String, projectID: String) async throws -> APIKey {
        struct R: Decodable { let createAPIKey: APIKey }
        let result: R = try await client.graphQL("""
        mutation($input: CreateAPIKeyInput!) { createAPIKey(input: $input) { \(Self.apiKeyFields) } }
        """, variables: ["input": ["name": .string(name), "projectID": .string(projectID)]])
        return result.createAPIKey
    }

    func renameAPIKey(id: String, name: String) async throws -> APIKey {
        struct R: Decodable { let updateAPIKey: APIKey }
        let result: R = try await client.graphQL("""
        mutation($id: ID!, $input: UpdateAPIKeyInput!) { updateAPIKey(id: $id, input: $input) { \(Self.apiKeyFields) } }
        """, variables: ["id": .string(id), "input": ["name": .string(name)]])
        return result.updateAPIKey
    }

    func setAPIKeyStatus(id: String, status: ResourceStatus) async throws -> APIKey {
        struct R: Decodable { let updateAPIKeyStatus: APIKey }
        let result: R = try await client.graphQL("""
        mutation($id: ID!, $status: APIKeyStatus!) { updateAPIKeyStatus(id: $id, status: $status) { \(Self.apiKeyFields) } }
        """, variables: ["id": .string(id), "status": .string(status.rawValue)])
        return result.updateAPIKeyStatus
    }

    func rotateAPIKey(id: String) async throws -> APIKey {
        struct R: Decodable { let rotateAPIKey: APIKey }
        let result: R = try await client.graphQL("""
        mutation($id: ID!) { rotateAPIKey(id: $id) { \(Self.apiKeyFields) } }
        """, variables: ["id": .string(id)])
        return result.rotateAPIKey
    }

    // MARK: - Users & projects (owner / admin)

    func users(after cursor: String?, search: String) async throws -> Page<AxonUser> {
        struct R: Decodable { let users: Connection<AxonUser> }
        var variables = Self.paging(after: cursor)
        variables["orderBy"] = Self.order("CREATED_AT")
        if let search = search.nilIfBlank {
            variables["where"] = ["or": [
                ["emailContainsFold": .string(search)],
                ["firstNameContainsFold": .string(search)],
                ["lastNameContainsFold": .string(search)],
            ]]
        }
        let result: R = try await client.graphQL("""
        query($first: Int, $after: Cursor, $orderBy: UserOrder, $where: UserWhereInput) {
          users(first: $first, after: $after, orderBy: $orderBy, where: $where) {
            edges { node { id email firstName lastName status isOwner createdAt } }
            pageInfo { hasNextPage endCursor }
            totalCount
          }
        }
        """, variables: variables)
        return page(result.users)
    }

    func setUserStatus(id: String, active: Bool) async throws {
        struct R: Decodable { struct U: Decodable { let id: String }; let updateUserStatus: U }
        let _: R = try await client.graphQL("""
        mutation($id: ID!, $status: UserStatus!) { updateUserStatus(id: $id, status: $status) { id } }
        """, variables: ["id": .string(id), "status": .string(active ? "activated" : "deactivated")])
    }

    func projects(after cursor: String?) async throws -> Page<Project> {
        struct R: Decodable { let projects: Connection<Project> }
        var variables = Self.paging(after: cursor)
        variables["orderBy"] = Self.order("CREATED_AT")
        let result: R = try await client.graphQL("""
        query($first: Int, $after: Cursor, $orderBy: ProjectOrder) {
          projects(first: $first, after: $after, orderBy: $orderBy) {
            edges { node { id name description status createdAt } }
            pageInfo { hasNextPage endCursor }
            totalCount
          }
        }
        """, variables: variables)
        return page(result.projects)
    }

    func createProject(name: String, description: String) async throws -> Project {
        struct R: Decodable { let createProject: Project }
        let result: R = try await client.graphQL("""
        mutation($input: CreateProjectInput!) { createProject(input: $input) { id name description status createdAt } }
        """, variables: ["input": ["name": .string(name), "description": .string(description)]])
        return result.createProject
    }

    func setProjectStatus(id: String, active: Bool) async throws {
        struct R: Decodable { struct P: Decodable { let id: String }; let updateProjectStatus: P }
        let _: R = try await client.graphQL("""
        mutation($id: ID!, $status: ProjectStatus!) { updateProjectStatus(id: $id, status: $status) { id } }
        """, variables: ["id": .string(id), "status": .string(active ? "active" : "archived")])
    }
}
