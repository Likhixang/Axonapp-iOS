import Foundation

/// Queries checked against official beta10 SDL. No synthesized metrics.
extension AxonClient {
    func observeRequestPage(variables: [String: Any] = [:]) async throws -> JSON {
        let query = """
        query ObserveRequestPage($first: Int!, $after: Cursor, $where: RequestWhereInput, $order: RequestOrder) { requests(first: $first, after: $after, where: $where, orderBy: $order) { edges { cursor node { id createdAt updatedAt projectID traceID channelID apiKeyID source modelID reasoningEffort format status stream clientIP metricsLatencyMs metricsFirstTokenLatencyMs metricsReasoningDurationMs contentSaved } } pageInfo { hasNextPage hasPreviousPage startCursor endCursor } totalCount } }
        """
        return try await graphql(query: query, variables: variables)
    }

    func observeTracePage(variables: [String: Any] = [:]) async throws -> JSON {
        let query = """
        query ObserveTracePage($first: Int!, $after: Cursor, $where: TraceWhereInput, $order: TraceOrder) { traces(first: $first, after: $after, where: $where, orderBy: $order) { edges { cursor node { id traceID threadID projectID status createdAt updatedAt firstUserQuery firstText usageMetadata { totalInputTokens totalOutputTokens totalTokens totalCachedTokens totalCachedWriteTokens totalCost } } } pageInfo { hasNextPage hasPreviousPage startCursor endCursor } totalCount } }
        """
        return try await graphql(query: query, variables: variables)
    }

    func observeThreadPage(variables: [String: Any] = [:]) async throws -> JSON {
        let query = """
        query ObserveThreadPage($first: Int!, $after: Cursor, $where: ThreadWhereInput, $order: ThreadOrder) { threads(first: $first, after: $after, where: $where, orderBy: $order) { edges { cursor node { id threadID projectID status createdAt updatedAt firstUserQuery archivedTracesCount usageMetadata { totalInputTokens totalOutputTokens totalTokens totalCachedTokens totalCachedWriteTokens totalCost } } } pageInfo { hasNextPage hasPreviousPage startCursor endCursor } totalCount } }
        """
        return try await graphql(query: query, variables: variables)
    }

    func observeUsageLogPage(variables: [String: Any] = [:]) async throws -> JSON {
        let query = """
        query ObserveUsageLogPage($first: Int!, $after: Cursor, $where: UsageLogWhereInput, $order: UsageLogOrder) { usageLogs(first: $first, after: $after, where: $where, orderBy: $order) { edges { cursor node { id createdAt requestID projectID channelID apiKeyID modelID promptTokens completionTokens totalTokens promptAudioTokens promptCachedTokens promptWriteCachedTokens promptWriteCachedTokens5m promptWriteCachedTokens1h completionAudioTokens completionReasoningTokens completionAcceptedPredictionTokens completionRejectedPredictionTokens source format totalCost costItems { itemCode quantity subtotal } } } pageInfo { hasNextPage hasPreviousPage startCursor endCursor } totalCount } }
        """
        return try await graphql(query: query, variables: variables)
    }

    func observeRequestDetail(variables: [String: Any] = [:]) async throws -> JSON {
        let query = """
        query ObserveRequestDetail($id: ID!) { node(id: $id) { ... on Request { id createdAt updatedAt projectID traceID channelID apiKeyID source modelID reasoningEffort format status stream clientIP metricsLatencyMs metricsFirstTokenLatencyMs metricsReasoningDurationMs contentSaved } } }
        """
        return try await graphql(query: query, variables: variables)
    }

    func observeTraceDetail(variables: [String: Any] = [:]) async throws -> JSON {
        let query = """
        query ObserveTraceDetail($id: ID!) { node(id: $id) { ... on Trace { id traceID threadID projectID status createdAt updatedAt firstUserQuery firstText usageMetadata { totalInputTokens totalOutputTokens totalTokens totalCachedTokens totalCachedWriteTokens totalCost } } } }
        """
        return try await graphql(query: query, variables: variables)
    }

    func observeThreadDetail(variables: [String: Any] = [:]) async throws -> JSON {
        let query = """
        query ObserveThreadDetail($id: ID!) { node(id: $id) { ... on Thread { id threadID projectID status createdAt updatedAt firstUserQuery archivedTracesCount usageMetadata { totalInputTokens totalOutputTokens totalTokens totalCachedTokens totalCachedWriteTokens totalCost } } } }
        """
        return try await graphql(query: query, variables: variables)
    }

    func observeUsageLogDetail(variables: [String: Any] = [:]) async throws -> JSON {
        let query = """
        query ObserveUsageLogDetail($id: ID!) { node(id: $id) { ... on UsageLog { id createdAt requestID projectID channelID apiKeyID modelID promptTokens completionTokens totalTokens promptAudioTokens promptCachedTokens promptWriteCachedTokens promptWriteCachedTokens5m promptWriteCachedTokens1h completionAudioTokens completionReasoningTokens completionAcceptedPredictionTokens completionRejectedPredictionTokens source format totalCost costItems { itemCode quantity subtotal } } } }
        """
        return try await graphql(query: query, variables: variables)
    }

    func observeRequestUsage(variables: [String: Any] = [:]) async throws -> JSON {
        let query = """
        query ObserveRequestUsage($id: ID!, $first: Int!, $after: Cursor) { node(id: $id) { ... on Request { id usageLogs(first: $first, after: $after, orderBy: {field: CREATED_AT, direction: ASC}) { edges { cursor node { id createdAt requestID projectID channelID apiKeyID modelID promptTokens completionTokens totalTokens promptAudioTokens promptCachedTokens promptWriteCachedTokens promptWriteCachedTokens5m promptWriteCachedTokens1h completionAudioTokens completionReasoningTokens completionAcceptedPredictionTokens completionRejectedPredictionTokens source format totalCost costItems { itemCode quantity subtotal } } } pageInfo { hasNextPage hasPreviousPage startCursor endCursor } totalCount } } } }
        """
        return try await graphql(query: query, variables: variables)
    }

    func observeExecutions(variables: [String: Any] = [:]) async throws -> JSON {
        let query = """
        query ObserveExecutions($id: ID!, $first: Int!, $after: Cursor, $where: RequestExecutionWhereInput) { node(id: $id) { ... on Request { id executions(first: $first, after: $after, where: $where, orderBy: {field: CREATED_AT, direction: ASC}) { edges { cursor node { id createdAt updatedAt requestID channelID projectID modelID format reasoningEffort status stream responseStatusCode passThroughApplied metricsLatencyMs metricsFirstTokenLatencyMs metricsReasoningDurationMs } } pageInfo { hasNextPage hasPreviousPage startCursor endCursor } totalCount } } } }
        """
        return try await graphql(query: query, variables: variables)
    }

    func observeRequestContent(variables: [String: Any] = [:]) async throws -> JSON {
        let query = """
        query ObserveRequestContent($id: ID!) { node(id: $id) { ... on Request { id requestHeaders requestBody responseBody responseChunks } } }
        """
        return try await graphql(query: query, variables: variables)
    }

    func observeRequestExecutionContent(variables: [String: Any] = [:]) async throws -> JSON {
        let query = """
        query ObserveRequestExecutionContent($id: ID!) { node(id: $id) { ... on RequestExecution { id requestID requestHeaders requestBody responseBody responseChunks errorMessage requestURL responseStatusCode } } }
        """
        return try await graphql(query: query, variables: variables)
    }

    func observeTraceContent(variables: [String: Any] = [:]) async throws -> JSON {
        let query = """
        query ObserveTraceContent($id: ID!) { node(id: $id) { ... on Trace { id rawRootSegment } } }
        """
        return try await graphql(query: query, variables: variables)
    }

    func observeTraceRequests(variables: [String: Any] = [:]) async throws -> JSON {
        let query = """
        query ObserveTraceRequests($id: ID!, $first: Int!, $after: Cursor, $where: RequestWhereInput) { node(id: $id) { ... on Trace { id requests(first: $first, after: $after, where: $where, orderBy: {field: CREATED_AT, direction: ASC}) { edges { cursor node { id createdAt updatedAt projectID traceID channelID apiKeyID source modelID reasoningEffort format status stream clientIP metricsLatencyMs metricsFirstTokenLatencyMs metricsReasoningDurationMs contentSaved } } pageInfo { hasNextPage hasPreviousPage startCursor endCursor } totalCount } } } }
        """
        return try await graphql(query: query, variables: variables)
    }

    func observeThreadTraces(variables: [String: Any] = [:]) async throws -> JSON {
        let query = """
        query ObserveThreadTraces($id: ID!, $first: Int!, $after: Cursor, $where: TraceWhereInput) { node(id: $id) { ... on Thread { id traces(first: $first, after: $after, where: $where, orderBy: {field: CREATED_AT, direction: ASC}) { edges { cursor node { id traceID threadID projectID status createdAt updatedAt firstUserQuery firstText usageMetadata { totalInputTokens totalOutputTokens totalTokens totalCachedTokens totalCachedWriteTokens totalCost } } } pageInfo { hasNextPage hasPreviousPage startCursor endCursor } totalCount } } } }
        """
        return try await graphql(query: query, variables: variables)
    }

    func observeArchiveTrace(variables: [String: Any] = [:]) async throws -> JSON {
        let query = """
        mutation ObserveArchiveTrace($id: ID!) { archiveTrace(id: $id) }
        """
        return try await graphql(query: query, variables: variables)
    }

    func observeUnarchiveTrace(variables: [String: Any] = [:]) async throws -> JSON {
        let query = """
        mutation ObserveUnarchiveTrace($id: ID!) { unarchiveTrace(id: $id) }
        """
        return try await graphql(query: query, variables: variables)
    }

    func observeRetainTrace(variables: [String: Any] = [:]) async throws -> JSON {
        let query = """
        mutation ObserveRetainTrace($id: ID!) { retainTrace(id: $id) }
        """
        return try await graphql(query: query, variables: variables)
    }

    func observeUnretainTrace(variables: [String: Any] = [:]) async throws -> JSON {
        let query = """
        mutation ObserveUnretainTrace($id: ID!) { unretainTrace(id: $id) }
        """
        return try await graphql(query: query, variables: variables)
    }

    func observeArchiveThread(variables: [String: Any] = [:]) async throws -> JSON {
        let query = """
        mutation ObserveArchiveThread($id: ID!) { archiveThread(id: $id) }
        """
        return try await graphql(query: query, variables: variables)
    }

    func observeUnarchiveThread(variables: [String: Any] = [:]) async throws -> JSON {
        let query = """
        mutation ObserveUnarchiveThread($id: ID!) { unarchiveThread(id: $id) }
        """
        return try await graphql(query: query, variables: variables)
    }

    func observeRetainThread(variables: [String: Any] = [:]) async throws -> JSON {
        let query = """
        mutation ObserveRetainThread($id: ID!) { retainThread(id: $id) }
        """
        return try await graphql(query: query, variables: variables)
    }

    func observeUnretainThread(variables: [String: Any] = [:]) async throws -> JSON {
        let query = """
        mutation ObserveUnretainThread($id: ID!) { unretainThread(id: $id) }
        """
        return try await graphql(query: query, variables: variables)
    }

    func observeAnalyticsMetadata(variables: [String: Any] = [:]) async throws -> JSON {
        let query = """
        query ObserveAnalyticsMetadata {
            analyticsMetadata {
              earliestDate
            }
          }
        """
        return try await graphql(query: query, variables: variables)
    }

    func observeAnalyticsOverview(variables: [String: Any] = [:]) async throws -> JSON {
        let query = """
        query ObserveAnalyticsOverview($filter: AnalyticsFilter) {
            analyticsOverview(filter: $filter) {
              totalTokens
              totalInputTokens
              totalCachedInputTokens
              totalUncachedInputTokens
              totalOutputTokens
              totalRequests
              totalCost
            }
          }
        """
        return try await graphql(query: query, variables: variables)
    }

    func observeAnalyticsDailyStats(variables: [String: Any] = [:]) async throws -> JSON {
        let query = """
        query ObserveAnalyticsDailyStats($filter: AnalyticsFilter) {
            analyticsDailyStats(filter: $filter) {
              date
              inputTokens
              cachedInputTokens
              uncachedInputTokens
              outputTokens
              totalTokens
              requestCount
              cost
            }
          }
        """
        return try await graphql(query: query, variables: variables)
    }

    func observeAnalyticsDimensionStats(variables: [String: Any] = [:]) async throws -> JSON {
        let query = """
        query ObserveAnalyticsDimensionStats($filter: AnalyticsFilter, $dimension: String!) {
            analyticsDimensionStats(filter: $filter, dimension: $dimension) {
              id
              name
              requestCount
              inputTokens
              cachedInputTokens
              outputTokens
              totalTokens
              cost
            }
          }
        """
        return try await graphql(query: query, variables: variables)
    }

    func observeDashboardStats(variables: [String: Any] = [:]) async throws -> JSON {
        let query = """
        query ObserveDashboardStats {
            dashboardOverview {
              totalRequests
              requestStats {
                requestsToday
                requestsThisWeek
                requestsLastWeek
                requestsThisMonth
              }
              failedRequests
              averageResponseTime
            }
          }
        """
        return try await graphql(query: query, variables: variables)
    }

    func observeRequestsByChannel(variables: [String: Any] = [:]) async throws -> JSON {
        let query = """
        query ObserveRequestsByChannel($timeWindow: String) {
            requestStatsByChannel(timeWindow: $timeWindow) {
              channelName
              count
            }
          }
        """
        return try await graphql(query: query, variables: variables)
    }

    func observeRequestsByModel(variables: [String: Any] = [:]) async throws -> JSON {
        let query = """
        query ObserveRequestsByModel($timeWindow: String) {
            requestStatsByModel(timeWindow: $timeWindow) {
              modelId
              count
            }
          }
        """
        return try await graphql(query: query, variables: variables)
    }

    func observeRequestsByAPIKey(variables: [String: Any] = [:]) async throws -> JSON {
        let query = """
        query ObserveRequestsByAPIKey($timeWindow: String) {
            requestStatsByAPIKey(timeWindow: $timeWindow) {
              apiKeyId
              apiKeyName
              count
            }
          }
        """
        return try await graphql(query: query, variables: variables)
    }

    func observeTokensByAPIKey(variables: [String: Any] = [:]) async throws -> JSON {
        let query = """
        query ObserveTokensByAPIKey($timeWindow: String) {
            tokenStatsByAPIKey(timeWindow: $timeWindow) {
              apiKeyId
              apiKeyName
              inputTokens
              outputTokens
              cachedTokens
              reasoningTokens
              totalTokens
            }
          }
        """
        return try await graphql(query: query, variables: variables)
    }

    func observeTokensByChannel(variables: [String: Any] = [:]) async throws -> JSON {
        let query = """
        query ObserveTokensByChannel($timeWindow: String) {
            tokenStatsByChannel(timeWindow: $timeWindow) {
              channelId
              channelName
              inputTokens
              outputTokens
              cachedTokens
              reasoningTokens
              totalTokens
            }
          }
        """
        return try await graphql(query: query, variables: variables)
    }

    func observeTokensByModel(variables: [String: Any] = [:]) async throws -> JSON {
        let query = """
        query ObserveTokensByModel($timeWindow: String) {
            tokenStatsByModel(timeWindow: $timeWindow) {
              modelId
              inputTokens
              outputTokens
              cachedTokens
              reasoningTokens
              totalTokens
            }
          }
        """
        return try await graphql(query: query, variables: variables)
    }

    func observeCostByChannel(variables: [String: Any] = [:]) async throws -> JSON {
        let query = """
        query ObserveCostByChannel($timeWindow: String) {
            costStatsByChannel(timeWindow: $timeWindow) {
              channelName
              cost
            }
          }
        """
        return try await graphql(query: query, variables: variables)
    }

    func observeCostByModel(variables: [String: Any] = [:]) async throws -> JSON {
        let query = """
        query ObserveCostByModel($timeWindow: String) {
            costStatsByModel(timeWindow: $timeWindow) {
              modelId
              cost
            }
          }
        """
        return try await graphql(query: query, variables: variables)
    }

    func observeCostByAPIKey(variables: [String: Any] = [:]) async throws -> JSON {
        let query = """
        query ObserveCostByAPIKey($timeWindow: String) {
            costStatsByAPIKey(timeWindow: $timeWindow) {
              apiKeyId
              apiKeyName
              cost
            }
          }
        """
        return try await graphql(query: query, variables: variables)
    }

    func observeDailyRequestStats(variables: [String: Any] = [:]) async throws -> JSON {
        let query = """
        query ObserveDailyRequestStats {
            dailyRequestStats {
              date
              count
              tokens
              cost
            }
          }
        """
        return try await graphql(query: query, variables: variables)
    }

    func observeTopProjects(variables: [String: Any] = [:]) async throws -> JSON {
        let query = """
        query ObserveTopProjects {
            topRequestsProjects {
              projectId
              projectName
              projectDescription
              requestCount
            }
          }
        """
        return try await graphql(query: query, variables: variables)
    }

    func observeChannelSuccessRates(variables: [String: Any] = [:]) async throws -> JSON {
        let query = """
        query ObserveChannelSuccessRates($timeWindow: String, $limit: Int) {
            channelSuccessRates(timeWindow: $timeWindow, limit: $limit) {
              channelId
              channelName
              channelType
              channelDisabled
              successCount
              failedCount
              totalCount
              successRate
            }
          }
        """
        return try await graphql(query: query, variables: variables)
    }

    func observeUsageStatsByUser(variables: [String: Any] = [:]) async throws -> JSON {
        let query = """
        query ObserveUsageStatsByUser($timeWindow: String) {
            usageStatsByUser(timeWindow: $timeWindow) {
              userId
              userName
              requestCount
              totalTokens
              totalCost
            }
          }
        """
        return try await graphql(query: query, variables: variables)
    }

    func observeModelPerformanceStats(variables: [String: Any] = [:]) async throws -> JSON {
        let query = """
        query ObserveModelPerformanceStats {
            modelPerformanceStats {
              date
              modelId
              throughput
              ttftMs
              requestCount
            }
          }
        """
        return try await graphql(query: query, variables: variables)
    }

    func observeChannelPerformanceStats(variables: [String: Any] = [:]) async throws -> JSON {
        let query = """
        query ObserveChannelPerformanceStats {
            channelPerformanceStats {
              date
              channelId
              channelName
              throughput
              ttftMs
              requestCount
            }
          }
        """
        return try await graphql(query: query, variables: variables)
    }

    func observeTokenStats(variables: [String: Any] = [:]) async throws -> JSON {
        let query = """
        query ObserveTokenStats {
            tokenStats {
              totalInputTokensToday
              totalOutputTokensToday
              totalCachedTokensToday
              totalInputTokensThisWeek
              totalOutputTokensThisWeek
              totalCachedTokensThisWeek
              totalInputTokensThisMonth
              totalOutputTokensThisMonth
              totalCachedTokensThisMonth
              totalInputTokensAllTime
              totalOutputTokensAllTime
              totalCachedTokensAllTime
              lastUpdated
            }
          }
        """
        return try await graphql(query: query, variables: variables)
    }

    func observeFastestChannels(variables: [String: Any] = [:]) async throws -> JSON {
        let query = """
        query ObserveFastestChannels($input: FastestChannelsInput!) {
            fastestChannels(input: $input) {
              channelId
              channelName
              channelType
              throughput
              tokensCount
              latencyMs
              requestCount
            }
          }
        """
        return try await graphql(query: query, variables: variables)
    }

    func observeFastestModels(variables: [String: Any] = [:]) async throws -> JSON {
        let query = """
        query ObserveFastestModels($input: FastestChannelsInput!) {
            fastestModels(input: $input) {
              modelId
              modelName
              throughput
              tokensCount
              latencyMs
              requestCount
            }
          }
        """
        return try await graphql(query: query, variables: variables)
    }

}
