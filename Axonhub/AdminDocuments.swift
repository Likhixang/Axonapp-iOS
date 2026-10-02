import Foundation

// Generated from official beta10 frontend documents + SDL. Do not interpolate GraphQL.
enum AdminDocuments {
    static let adminGetApiKeys = """
    query AdminGetApiKeys($first: Int, $after: Cursor, $orderBy: APIKeyOrder, $where: APIKeyWhereInput) {
      apiKeys(first: $first, after: $after, orderBy: $orderBy, where: $where) {
        edges {
          node {
            id
            createdAt
            updatedAt
            name
            type
            status
            scopes
            allowedIps
            profiles {
              activeProfile
              profiles {
                name
                templateID
                templateName
              }
            }
            projectID
          }
          cursor
        }
        pageInfo {
          hasNextPage
          hasPreviousPage
          startCursor
          endCursor
        }
        totalCount
      }
    }
    """

    static let adminCreateAPIKey = """
    mutation AdminCreateAPIKey($input: CreateAPIKeyInput!) {
      createAPIKey(input: $input) {
        id
        createdAt
        updatedAt
        key
        name
        type
        status
        scopes
        allowedIps
      }
    }
    """

    static let adminUpdateAPIKey = """
    mutation AdminUpdateAPIKey($id: ID!, $input: UpdateAPIKeyInput!) {
      updateAPIKey(id: $id, input: $input) {
        id
        createdAt
        updatedAt
        key
        name
        type
        status
        scopes
        allowedIps
      }
    }
    """

    static let adminUpdateAPIKeyStatus = """
    mutation AdminUpdateAPIKeyStatus($id: ID!, $status: APIKeyStatus!) {
      updateAPIKeyStatus(id: $id, status: $status) {
        id
        status
      }
    }
    """

    static let adminUpdateAPIKeyProfiles = """
    mutation AdminUpdateAPIKeyProfiles($id: ID!, $input: UpdateAPIKeyProfilesInput!) {
      updateAPIKeyProfiles(id: $id, input: $input) {
        id
        name
        status
        profiles {
          activeProfile
          profiles {
            name
            templateID
            templateName
            modelMappings {
              from
              to
            }
            channelIDs
            channelTags
            channelTagsMatchMode
            modelIDs
            loadBalanceStrategy
            traceStickyMode
            quota {
              requests
              totalTokens
              cost
              period {
                type
                pastDuration {
                  value
                  unit
                }
                calendarDuration {
                  unit
                }
              }
            }
          }
        }
      }
    }
    """

    static let adminBulkDisableAPIKeys = """
    mutation AdminBulkDisableAPIKeys($ids: [ID!]!) {
      bulkDisableAPIKeys(ids: $ids)
    }
    """

    static let adminBulkEnableAPIKeys = """
    mutation AdminBulkEnableAPIKeys($ids: [ID!]!) {
      bulkEnableAPIKeys(ids: $ids)
    }
    """

    static let adminBulkArchiveAPIKeys = """
    mutation AdminBulkArchiveAPIKeys($ids: [ID!]!) {
      bulkArchiveAPIKeys(ids: $ids)
    }
    """

    static let adminRotateAPIKey = """
    mutation AdminRotateAPIKey($id: ID!) {
      rotateAPIKey(id: $id) {
        id
        key
        name
        type
        status
        scopes
        createdAt
        updatedAt
      }
    }
    """

    static let adminAPIKeyQuotaUsages = """
    query AdminAPIKeyQuotaUsages($apiKeyId: ID!) {
      apiKeyQuotaUsages(apiKeyId: $apiKeyId) {
        profileName
        quota {
          requests
          totalTokens
          cost
          period {
            type
            pastDuration {
              value
              unit
            }
            calendarDuration {
              unit
            }
          }
        }
        window {
          start
          end
        }
        usage {
          requestCount
          totalTokens
          totalCost
        }
      }
    }
    """

    static let adminAPIKeyTokenUsageStats = """
    query AdminAPIKeyTokenUsageStats($input: APIKeyTokenUsageStatsInput) {
      apiKeyTokenUsageStats(input: $input) {
        apiKeyId
        inputTokens
        outputTokens
        cachedTokens
        reasoningTokens
        topModels {
          modelId
          inputTokens
          outputTokens
          cachedTokens
          reasoningTokens
        }
      }
    }
    """

    static let adminApiKeyProfileTemplates = """
    query AdminApiKeyProfileTemplates($where: APIKeyProfileTemplateWhereInput, $first: Int, $after: Cursor) {
      apiKeyProfileTemplates(where: $where, first: $first, after: $after) {
        edges {
          node {
            id
            createdAt
            updatedAt
            name
            description
            projectID
            linkedProfilesCount
            profile {
              name
              modelMappings {
                from
                to
              }
              channelIDs
              channelTags
              channelTagsMatchMode
              modelIDs
              loadBalanceStrategy
              traceStickyMode
              quota {
                requests
                totalTokens
                cost
                period {
                  type
                  pastDuration {
                    value
                    unit
                  }
                  calendarDuration {
                    unit
                  }
                }
              }
            }
          }
        }
        totalCount
        pageInfo {
          hasNextPage
          endCursor
        }
      }
    }
    """

    static let adminCreateApiKeyProfileTemplate = """
    mutation AdminCreateApiKeyProfileTemplate($input: CreateAPIKeyProfileTemplateInput!, $profile: APIKeyProfileInput!) {
      createApiKeyProfileTemplate(input: $input, profile: $profile) {
        id
        createdAt
        updatedAt
        name
        description
        linkedProfilesCount
        profile {
          name
        }
      }
    }
    """

    static let adminUpdateApiKeyProfileTemplate = """
    mutation AdminUpdateApiKeyProfileTemplate($id: ID!, $input: UpdateAPIKeyProfileTemplateInput!, $profile: APIKeyProfileInput) {
      updateApiKeyProfileTemplate(id: $id, input: $input, profile: $profile) {
        id
        createdAt
        updatedAt
        name
        description
        linkedProfilesCount
        profile {
          name
        }
      }
    }
    """

    static let adminDeleteApiKeyProfileTemplate = """
    mutation AdminDeleteApiKeyProfileTemplate($id: ID!) {
      deleteApiKeyProfileTemplate(id: $id) {
        id
        name
      }
    }
    """

    static let adminLoadApiKeyProfileTemplate = """
    mutation AdminLoadApiKeyProfileTemplate($input: LoadApiKeyProfileTemplateInput!) {
      loadApiKeyProfileTemplate(input: $input) {
        id
        name
        status
        profiles {
          activeProfile
          profiles {
            name
            templateID
            templateName
            modelMappings {
              from
              to
            }
            channelIDs
            channelTags
            channelTagsMatchMode
            modelIDs
            loadBalanceStrategy
            traceStickyMode
            quota {
              requests
              totalTokens
              cost
              period {
                type
                pastDuration {
                  value
                  unit
                }
                calendarDuration {
                  unit
                }
              }
            }
          }
        }
      }
    }
    """

    static let adminDataStorages = """
    query AdminDataStorages($first: Int, $after: Cursor, $where: DataStorageWhereInput, $orderBy: DataStorageOrder) {
      dataStorages(first: $first, after: $after, where: $where, orderBy: $orderBy) {
        edges {
          node {
            id
            name
            description
            type
            primary
            status
            settings {
              directory
              s3 {
                bucketName
                endpoint
                region
                pathStyle
              }
              gcs {
                bucketName
              }
            }
            createdAt
            updatedAt
          }
        }
        pageInfo {
          hasNextPage
          hasPreviousPage
          startCursor
          endCursor
        }
        totalCount
      }
    }
    """

    static let adminCreateDataStorage = """
    mutation AdminCreateDataStorage($input: CreateDataStorageInput!) {
      createDataStorage(input: $input) {
        id
        name
        description
        type
        primary
        status
        settings {
          directory
          s3 {
            bucketName
            endpoint
            region
          }
          gcs {
            bucketName
          }
        }
        createdAt
        updatedAt
      }
    }
    """

    static let adminUpdateDataStorage = """
    mutation AdminUpdateDataStorage($id: ID!, $input: UpdateDataStorageInput!) {
      updateDataStorage(id: $id, input: $input) {
        id
        name
        description
        type
        primary
        status
        settings {
          directory
          s3 {
            bucketName
            endpoint
            region
          }
          gcs {
            bucketName
          }
        }
        createdAt
        updatedAt
      }
    }
    """

    static let adminAddUserToProject = """
    mutation AdminAddUserToProject($input: AddUserToProjectInput!) {
      addUserToProject(input: $input) {
        id
        userID
        projectID
        isOwner
        scopes
      }
    }
    """

    static let adminRemoveUserFromProject = """
    mutation AdminRemoveUserFromProject($input: RemoveUserFromProjectInput!) {
      removeUserFromProject(input: $input)
    }
    """

    static let adminUpdateProjectUser = """
    mutation AdminUpdateProjectUser($input: UpdateProjectUserInput!) {
      updateProjectUser(input: $input) {
        id
        userID
        projectID
        isOwner
        scopes
      }
    }
    """

    static let adminAllUsers = """
    query AdminAllUsers($first: Int, $after: Cursor, $where: UserWhereInput) {
      users(first: $first, after: $after, where: $where) {
        edges {
          node {
            id
            email
            firstName
            lastName
            status
          }
        }
        pageInfo {
          hasNextPage
          hasPreviousPage
          startCursor
          endCursor
        }
      }
    }
    """

    static let adminGetProjectRoles = """
    query AdminGetProjectRoles($first: Int, $after: Cursor, $orderBy: RoleOrder, $where: RoleWhereInput) {
      roles(first: $first, after: $after, orderBy: $orderBy, where: $where) {
        edges {
          node {
            id
            createdAt
            updatedAt
            name
            scopes
            projectID
            level
          }
          cursor
        }
        pageInfo {
          hasNextPage
          hasPreviousPage
          startCursor
          endCursor
        }
        totalCount
      }
    }
    """

    static let adminCreateRole = """
    mutation AdminCreateRole($input: CreateRoleInput!) {
      createRole(input: $input) {
        id
        name
        scopes
        createdAt
        updatedAt
      }
    }
    """

    static let adminUpdateRole = """
    mutation AdminUpdateRole($id: ID!, $input: UpdateRoleInput!) {
      updateRole(id: $id, input: $input) {
        id
        name
        scopes
        createdAt
        updatedAt
      }
    }
    """

    static let adminDeleteRole = """
    mutation AdminDeleteRole($id: ID!) {
      deleteRole(id: $id)
    }
    """

    static let adminGetProjects = """
    query AdminGetProjects($first: Int, $after: Cursor, $orderBy: ProjectOrder, $where: ProjectWhereInput) {
      projects(first: $first, after: $after, orderBy: $orderBy, where: $where) {
        edges {
          node {
            id
            createdAt
            updatedAt
            name
            description
            status
            profiles {
              activeProfile
              profiles {
                name
                channelIDs
                channelTags
                channelTagsMatchMode
              }
            }
          }
          cursor
        }
        pageInfo {
          hasNextPage
          hasPreviousPage
          startCursor
          endCursor
        }
        totalCount
      }
    }
    """

    static let adminCreateProject = """
    mutation AdminCreateProject($input: CreateProjectInput!) {
      createProject(input: $input) {
        id
        name
        description
        status
        createdAt
        updatedAt
      }
    }
    """

    static let adminUpdateProject = """
    mutation AdminUpdateProject($id: ID!, $input: UpdateProjectInput!) {
      updateProject(id: $id, input: $input) {
        id
        name
        description
        status
        createdAt
        updatedAt
      }
    }
    """

    static let adminUpdateProjectStatus = """
    mutation AdminUpdateProjectStatus($id: ID!, $status: ProjectStatus!) {
      updateProjectStatus(id: $id, status: $status) {
        id
        name
        description
        status
        createdAt
        updatedAt
      }
    }
    """

    static let adminDeleteProject = """
    mutation AdminDeleteProject($id: ID!) {
      deleteProject(id: $id)
    }
    """

    static let adminMyProjects = """
    query AdminMyProjects {
      myProjects {
        id
        name
        description
        status
        createdAt
        updatedAt
      }
    }
    """

    static let adminUpdateProjectProfiles = """
    mutation AdminUpdateProjectProfiles($id: ID!, $input: UpdateProjectProfilesInput!) {
      updateProjectProfiles(id: $id, input: $input) {
        id
        name
        profiles {
          activeProfile
          profiles {
            name
            channelIDs
            channelTags
            channelTagsMatchMode
          }
        }
      }
    }
    """

    static let adminGetPromptProtectionRules = """
    query AdminGetPromptProtectionRules($first: Int, $after: Cursor, $last: Int, $before: Cursor, $where: PromptProtectionRuleWhereInput, $orderBy: PromptProtectionRuleOrder) {
      promptProtectionRules(
        first: $first
        after: $after
        last: $last
        before: $before
        where: $where
        orderBy: $orderBy
      ) {
        edges {
          node {
            id
            createdAt
            updatedAt
            name
            description
            pattern
            status
            settings {
              action
              replacement
              scopes
            }
          }
          cursor
        }
        pageInfo {
          hasNextPage
          hasPreviousPage
          startCursor
          endCursor
        }
        totalCount
      }
    }
    """

    static let adminCreatePromptProtectionRule = """
    mutation AdminCreatePromptProtectionRule($input: CreatePromptProtectionRuleInput!) {
      createPromptProtectionRule(input: $input) {
        id
        createdAt
        updatedAt
        name
        description
        pattern
        status
        settings {
          action
          replacement
          scopes
        }
      }
    }
    """

    static let adminUpdatePromptProtectionRule = """
    mutation AdminUpdatePromptProtectionRule($id: ID!, $input: UpdatePromptProtectionRuleInput!) {
      updatePromptProtectionRule(id: $id, input: $input) {
        id
        createdAt
        updatedAt
        name
        description
        pattern
        status
        settings {
          action
          replacement
          scopes
        }
      }
    }
    """

    static let adminDeletePromptProtectionRule = """
    mutation AdminDeletePromptProtectionRule($id: ID!) {
      deletePromptProtectionRule(id: $id)
    }
    """

    static let adminUpdatePromptProtectionRuleStatus = """
    mutation AdminUpdatePromptProtectionRuleStatus($id: ID!, $status: PromptProtectionRuleStatus!) {
      updatePromptProtectionRuleStatus(id: $id, status: $status)
    }
    """

    static let adminBulkDeletePromptProtectionRules = """
    mutation AdminBulkDeletePromptProtectionRules($ids: [ID!]!) {
      bulkDeletePromptProtectionRules(ids: $ids)
    }
    """

    static let adminBulkEnablePromptProtectionRules = """
    mutation AdminBulkEnablePromptProtectionRules($ids: [ID!]!) {
      bulkEnablePromptProtectionRules(ids: $ids)
    }
    """

    static let adminBulkDisablePromptProtectionRules = """
    mutation AdminBulkDisablePromptProtectionRules($ids: [ID!]!) {
      bulkDisablePromptProtectionRules(ids: $ids)
    }
    """

    static let adminPreviewPromptProtectionRule = """
    mutation AdminPreviewPromptProtectionRule($input: PromptProtectionRulePreviewInput!) {
      previewPromptProtectionRule(input: $input) {
        result
        hasMatch
      }
    }
    """

    static let adminGetPrompts = """
    query AdminGetPrompts($first: Int, $after: Cursor, $last: Int, $before: Cursor, $where: PromptWhereInput, $orderBy: PromptOrder) {
      prompts(
        first: $first
        after: $after
        last: $last
        before: $before
        where: $where
        orderBy: $orderBy
      ) {
        edges {
          node {
            id
            createdAt
            updatedAt
            projectID
            name
            description
            role
            content
            status
            order
            settings {
              action {
                type
              }
              conditions {
                conditions {
                  type
                  modelId
                  modelPattern
                  apiKeyId
                }
              }
            }
          }
          cursor
        }
        pageInfo {
          hasNextPage
          hasPreviousPage
          startCursor
          endCursor
        }
        totalCount
      }
    }
    """

    static let adminCreatePrompt = """
    mutation AdminCreatePrompt($input: CreatePromptInput!) {
      createPrompt(input: $input) {
        id
        createdAt
        updatedAt
        projectID
        name
        description
        role
        content
        status
        order
        settings {
          action {
            type
          }
          conditions {
            conditions {
              type
              modelId
              modelPattern
              apiKeyId
            }
          }
        }
      }
    }
    """

    static let adminUpdatePrompt = """
    mutation AdminUpdatePrompt($id: ID!, $input: UpdatePromptInput!) {
      updatePrompt(id: $id, input: $input) {
        id
        createdAt
        updatedAt
        projectID
        name
        description
        role
        content
        status
        order
        settings {
          action {
            type
          }
          conditions {
            conditions {
              type
              modelId
              modelPattern
              apiKeyId
            }
          }
        }
      }
    }
    """

    static let adminDeletePrompt = """
    mutation AdminDeletePrompt($id: ID!) {
      deletePrompt(id: $id)
    }
    """

    static let adminUpdatePromptStatus = """
    mutation AdminUpdatePromptStatus($id: ID!, $status: PromptStatus!) {
      updatePromptStatus(id: $id, status: $status)
    }
    """

    static let adminBulkDeletePrompts = """
    mutation AdminBulkDeletePrompts($ids: [ID!]!) {
      bulkDeletePrompts(ids: $ids)
    }
    """

    static let adminBulkDisablePrompts = """
    mutation AdminBulkDisablePrompts($ids: [ID!]!) {
      bulkDisablePrompts(ids: $ids)
    }
    """

    static let adminBulkEnablePrompts = """
    mutation AdminBulkEnablePrompts($ids: [ID!]!) {
      bulkEnablePrompts(ids: $ids)
    }
    """

    static let adminBulkDeleteRoles = """
    mutation AdminBulkDeleteRoles($ids: [ID!]!) {
      bulkDeleteRoles(ids: $ids)
    }
    """

    static let adminSystemVersion = """
    query AdminSystemVersion {
      systemVersion {
        version
        commit
        buildTime
        goVersion
        platform
        uptime
      }
    }
    """

    static let adminCheckForUpdate = """
    query AdminCheckForUpdate($includeBeta: Boolean! = false) {
      checkForUpdate(includeBeta: $includeBeta) {
        currentVersion
        latestVersion
        hasUpdate
        releaseUrl
      }
    }
    """

    static let adminGetCacheDiagnostics = """
    query AdminGetCacheDiagnostics($input: GetCacheDiagnosticsInput) {
      getCacheDiagnostics(input: $input) {
        fileName
        content
        targets
      }
    }
    """

    static let adminClearCache = """
    mutation AdminClearCache($input: ClearCacheInput!) {
      clearCache(input: $input) {
        success
        message
        targets
      }
    }
    """

    static let adminBrandSettings = """
    query AdminBrandSettings {
      brandSettings {
        brandName
        brandLogo
        title
      }
    }
    """

    static let adminStoragePolicy = """
    query AdminStoragePolicy {
      storagePolicy {
        storeChunks
        livePreview
        storeRequestBody
        storeResponseBody
        cleanupOptions {
          resourceType
          enabled
          cleanupDays
        }
      }
    }
    """

    static let adminUpdateBrandSettings = """
    mutation AdminUpdateBrandSettings($input: UpdateBrandSettingsInput!) {
      updateBrandSettings(input: $input)
    }
    """

    static let adminUpdateStoragePolicy = """
    mutation AdminUpdateStoragePolicy($input: UpdateStoragePolicyInput!) {
      updateStoragePolicy(input: $input)
    }
    """

    static let adminRetryPolicy = """
    query AdminRetryPolicy {
      retryPolicy {
        maxChannelRetries
        maxSingleChannelRetries
        retryDelayMs
        streamFirstEventTimeoutSeconds
        nonStreamResponseTimeoutSeconds
        loadBalancerStrategy
        traceStickyMode
        enabled
        emptyResponseDetection
        upstreamErrorPolicy {
          mode
          customMessage
        }
        autoDisableChannel {
          enabled
          statuses {
            status
            times
          }
        }
      }
    }
    """

    static let adminUpdateRetryPolicy = """
    mutation AdminUpdateRetryPolicy($input: UpdateRetryPolicyInput!) {
      updateRetryPolicy(input: $input)
    }
    """

    static let adminWebhookNotifierConfig = """
    query AdminWebhookNotifierConfig {
      webhookNotifierConfig {
        targets {
          name
          enabled
          url
          proxy {
            type
            url
            username
          }
          timeoutMs
          headers {
            value
          }
          body
        }
        subscriptions {
          event
          targetNames
        }
      }
    }
    """

    static let adminUpdateWebhookNotifierConfig = """
    mutation AdminUpdateWebhookNotifierConfig($input: WebhookNotifierConfigInput!) {
      updateWebhookNotifierConfig(input: $input)
    }
    """

    static let adminDefaultDataStorageID = """
    query AdminDefaultDataStorageID {
      defaultDataStorageID
    }
    """

    static let adminUpdateDefaultDataStorage = """
    mutation AdminUpdateDefaultDataStorage($input: UpdateDefaultDataStorageInput!) {
      updateDefaultDataStorage(input: $input)
    }
    """

    static let adminOnboardingInfo = """
    query AdminOnboardingInfo {
      onboardingInfo {
        onboarded
        completedAt
        systemModelSetting {
          onboarded
          completedAt
        }
        autoDisableChannel {
          onboarded
          completedAt
        }
      }
    }
    """

    static let adminCompleteOnboarding = """
    mutation AdminCompleteOnboarding($input: CompleteOnboardingInput!) {
      completeOnboarding(input: $input)
    }
    """

    static let adminCompleteSystemModelSettingOnboarding = """
    mutation AdminCompleteSystemModelSettingOnboarding($input: CompleteSystemModelSettingOnboardingInput!) {
      completeSystemModelSettingOnboarding(input: $input)
    }
    """

    static let adminCompleteAutoDisableChannelOnboarding = """
    mutation AdminCompleteAutoDisableChannelOnboarding($input: CompleteAutoDisableChannelOnboardingInput!) {
      completeAutoDisableChannelOnboarding(input: $input)
    }
    """

    static let adminTriggerGcCleanup = """
    mutation AdminTriggerGcCleanup($input: TriggerGcCleanupInput!) {
      triggerGcCleanup(input: $input)
    }
    """

    static let adminPreviewGcCleanup = """
    query AdminPreviewGcCleanup($input: TriggerGcCleanupInput!) {
      previewGcCleanup(input: $input) {
        resourceType
        estimatedCount
        cutoffTime
        retentionDays
      }
    }
    """

    static let adminModelSettings = """
    query AdminModelSettings {
      systemModelSettings {
        fallbackToChannelsOnModelNotFound
        queryAllChannelModels
        defaultModelAPIIncludeAll
        autoReasoningEffort
        modelBlacklistRegex
        hideUnroutableModelsInList
        developerSettings {
          developer
          associations {
            type
            priority
            disabled
            when {
              enabled
              condition {
                type
                logic
                field
                operator
                value
                conditions {
                  type
                  logic
                  field
                  operator
                  value
                  conditions {
                    type
                    logic
                    field
                    operator
                    value
                    conditions {
                      type
                      logic
                      field
                      operator
                      value
                      conditions {
                        type
                        logic
                        field
                        operator
                        value
                        conditions {
                          type
                          logic
                          field
                          operator
                          value
                          conditions {
                            type
                            logic
                            field
                            operator
                            value
                            conditions {
                              type
                              logic
                              field
                              operator
                              value
                              conditions {
                                type
                                logic
                                field
                                operator
                                value
                                conditions {
                                  type
                                  logic
                                  field
                                  operator
                                  value
                                  conditions {
                                    type
                                    logic
                                    field
                                    operator
                                    value
                                    conditions {
                                      type
                                      logic
                                      field
                                      operator
                                      value
                                      conditions {
                                        type
                                        logic
                                        field
                                        operator
                                        value
                                        conditions {
                                          type
                                          logic
                                          field
                                          operator
                                          value
                                          conditions {
                                            type
                                            logic
                                            field
                                            operator
                                            value
                                            conditions {
                                              type
                                              logic
                                              field
                                              operator
                                              value
                                              conditions {
                                                __typename
                                              }
                                            }
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
            channelModel {
              channelId
              modelId
            }
            channelRegex {
              channelId
              pattern
            }
            regex {
              pattern
              exclude {
                channelNamePattern
                channelIds
                channelTags
              }
            }
            modelId {
              modelId
              exclude {
                channelNamePattern
                channelIds
                channelTags
              }
            }
            channelTagsModel {
              channelTags
              modelId
            }
            channelTagsRegex {
              channelTags
              pattern
            }
          }
        }
      }
    }
    """

    static let adminUpdateModelSettings = """
    mutation AdminUpdateModelSettings($input: UpdateSystemModelSettingsInput!) {
      updateSystemModelSettings(input: $input)
    }
    """

    static let adminSystemChannelSettings = """
    query AdminSystemChannelSettings {
      systemChannelSettings {
        probe {
          enabled
          frequency
        }
        autoSync {
          frequency
        }
        testSystemPrompt
        testUserPrompt
      }
    }
    """

    static let adminUpdateChannelSettings = """
    mutation AdminUpdateChannelSettings($input: UpdateSystemChannelSettingsInput!) {
      updateSystemChannelSettings(input: $input)
    }
    """

    static let adminSystemGeneralSettings = """
    query AdminSystemGeneralSettings {
      systemGeneralSettings {
        currencyCode
        timezone
      }
    }
    """

    static let adminUpdateSystemGeneralSettings = """
    mutation AdminUpdateSystemGeneralSettings($input: UpdateSystemGeneralSettingsInput!) {
      updateSystemGeneralSettings(input: $input)
    }
    """

    static let adminVideoStorageSettings = """
    query AdminVideoStorageSettings {
      videoStorageSettings {
        enabled
        dataStorageID
        scanIntervalMinutes
        scanLimit
      }
    }
    """

    static let adminUpdateVideoStorageSettings = """
    mutation AdminUpdateVideoStorageSettings($input: UpdateVideoStorageSettingsInput!) {
      updateVideoStorageSettings(input: $input)
    }
    """

    static let adminSecuritySettings = """
    query AdminSecuritySettings {
      securitySettings {
        blockedIPs
        showRequestLogIPBanIcon
      }
    }
    """

    static let adminUpdateSecuritySettings = """
    mutation AdminUpdateSecuritySettings($input: UpdateSecuritySettingsInput!) {
      updateSecuritySettings(input: $input)
    }
    """

    static let adminBackup = """
    mutation AdminBackup($input: BackupOptionsInput!) {
      backup(input: $input) {
        success
        data
        message
      }
    }
    """

    static let adminRestore = """
    mutation AdminRestore($file: Upload!, $input: RestoreOptionsInput!) {
      restore(file: $file, input: $input) {
        success
        message
      }
    }
    """

    static let adminAutoBackupSettings = """
    query AdminAutoBackupSettings {
      autoBackupSettings {
        includeSystemConfigs
        enabled
        frequency
        dataStorageID
        includeChannels
        includeModels
        includeAPIKeys
        includeModelPrices
        includeUsageStats
        includeRequestLogs
        retentionDays
        lastBackupAt
        lastBackupError
      }
    }
    """

    static let adminUpdateAutoBackupSettings = """
    mutation AdminUpdateAutoBackupSettings($input: UpdateAutoBackupSettingsInput!) {
      updateAutoBackupSettings(input: $input)
    }
    """

    static let adminTriggerAutoBackup = """
    mutation AdminTriggerAutoBackup {
      triggerAutoBackup {
        success
        message
      }
    }
    """

    static let adminProxyPresets = """
    query AdminProxyPresets {
      proxyPresets {
        name
        url
        username
      }
    }
    """

    static let adminSaveProxyPreset = """
    mutation AdminSaveProxyPreset($input: SaveProxyPresetInput!) {
      saveProxyPreset(input: $input)
    }
    """

    static let adminDeleteProxyPreset = """
    mutation AdminDeleteProxyPreset($url: String!) {
      deleteProxyPreset(url: $url)
    }
    """

    static let adminUserAgentPassThroughSettings = """
    query AdminUserAgentPassThroughSettings {
      userAgentPassThroughSettings {
        enabled
      }
    }
    """

    static let adminUpdateUserAgentPassThroughSettings = """
    mutation AdminUpdateUserAgentPassThroughSettings($input: UpdateUserAgentPassThroughSettingsInput!) {
      updateUserAgentPassThroughSettings(input: $input)
    }
    """

    static let adminPassThroughSettings = """
    query AdminPassThroughSettings {
      passThroughSettings {
        enabled
      }
    }
    """

    static let adminUpdatePassThroughSettings = """
    mutation AdminUpdatePassThroughSettings($input: UpdatePassThroughSettingsInput!) {
      updatePassThroughSettings(input: $input)
    }
    """

    static let adminUsageCostInjectionSettings = """
    query AdminUsageCostInjectionSettings {
      usageCostInjectionSettings {
        enabled
      }
    }
    """

    static let adminUpdateUsageCostInjectionSettings = """
    mutation AdminUpdateUsageCostInjectionSettings($input: UpdateUsageCostInjectionSettingsInput!) {
      updateUsageCostInjectionSettings(input: $input)
    }
    """

    static let adminQuotaEnforcementSettings = """
    query AdminQuotaEnforcementSettings {
      quotaEnforcementSettings {
        enabled
        mode
        allowedChannelIDs
      }
    }
    """

    static let adminUpdateQuotaEnforcementSettings = """
    mutation AdminUpdateQuotaEnforcementSettings($input: UpdateQuotaEnforcementSettingsInput!) {
      updateQuotaEnforcementSettings(input: $input)
    }
    """

    static let adminProviderQuotaCollectionSettings = """
    query AdminProviderQuotaCollectionSettings {
      providerQuotaCollectionSettings {
        enabled
        providers {
          provider
          enabled
        }
      }
    }
    """

    static let adminUpdateProviderQuotaCollectionSettings = """
    mutation AdminUpdateProviderQuotaCollectionSettings($input: UpdateProviderQuotaCollectionSettingsInput!) {
      updateProviderQuotaCollectionSettings(input: $input)
    }
    """

    static let adminCatalogSettings = """
    query AdminCatalogSettings {
      catalogSettings {
        upstreamURL
        refreshSeconds
      }
    }
    """

    static let adminUpdateCatalogSettings = """
    mutation AdminUpdateCatalogSettings($input: UpdateCatalogSettingsInput!) {
      updateCatalogSettings(input: $input)
    }
    """

    static let adminAllScopes = """
    query AdminAllScopes($level: String) {
      allScopes(level: $level) {
        scope
        description
        levels
      }
    }
    """

    static let adminMe = """
    query AdminMe {
      me {
        id
        email
        firstName
        lastName
        isOwner
        scopes
        preferLanguage
        avatar
        hasPassword
        oidcIdentities {
          id
          idpName
          issuer
          subject
          email
        }
        roles {
          name
        }
        projects {
          projectID
          isOwner
          scopes
          effectiveScopes
          roles {
            name
          }
        }
      }
    }
    """

    static let adminCreateUser = """
    mutation AdminCreateUser($input: CreateUserInput!) {
      createUser(input: $input) {
        id
        createdAt
        updatedAt
        email
        status
        firstName
        lastName
        isOwner
        preferLanguage
        scopes
        roles {
          edges {
            node {
              id
              name
            }
          }
        }
      }
    }
    """

    static let adminUpdateUser = """
    mutation AdminUpdateUser($id: ID!, $input: UpdateUserInput!) {
      updateUser(id: $id, input: $input) {
        id
        createdAt
        updatedAt
        email
        status
        firstName
        lastName
        isOwner
        preferLanguage
        scopes
        roles {
          edges {
            node {
              id
              name
            }
          }
        }
      }
    }
    """

    static let adminUpdateUserStatus = """
    mutation AdminUpdateUserStatus($id: ID!, $status: UserStatus!) {
      updateUserStatus(id: $id, status: $status) {
        id
        createdAt
        updatedAt
        email
        status
        firstName
        lastName
        isOwner
        preferLanguage
        scopes
        roles {
          edges {
            node {
              id
              name
            }
          }
        }
      }
    }
    """

    static let adminDeleteUser = """
    mutation AdminDeleteUser($id: ID!) {
      deleteUser(id: $id)
    }
    """

    static let adminSystemStatus = """
    query AdminSystemStatus {
      systemStatus {
        isInitialized
      }
    }
    """

    static let adminUpdateMe = """
    mutation AdminUpdateMe($input: UpdateMeInput!) {
      updateMe(input: $input) {
        email
        firstName
        lastName
        isOwner
        preferLanguage
        avatar
      }
    }
    """

    static let adminUpdateMyPassword = """
    mutation AdminUpdateMyPassword($input: UpdateMyPasswordInput!) {
      updateMyPassword(input: $input)
    }
    """

    static let adminUnlinkOIDCIdentity = """
    mutation AdminUnlinkOIDCIdentity($id: ID!) {
      unlinkOIDCIdentity(id: $id)
    }
    """

    static let adminProjectUsers = """
    query AdminProjectUsers($projectId: ID!) {
      node(id: $projectId) {
        ... on Project {
          id
          name
          projectUsers {
            id
            userID
            projectID
            isOwner
            scopes
            user {
              id
              email
              status
              firstName
              lastName
              preferLanguage
              roles {
                edges {
                  node {
                    id
                    name
                    level
                    projectID
                  }
                }
              }
            }
          }
        }
      }
    }
    """

    static let adminDetailAPIKey = """
    query AdminDetailAPIKey($id: ID!) {
      node(id: $id) {
        ... on APIKey {
          id
          createdAt
          updatedAt
          name
          type
          status
          scopes
          allowedIps
          projectID
          userID
          profiles {
            activeProfile
            profiles {
              name
              templateID
              templateName
              modelMappings {
                from
                to
              }
              channelIDs
              channelTags
              channelTagsMatchMode
              modelIDs
              loadBalanceStrategy
              traceStickyMode
              quota {
                requests
                totalTokens
                cost
                period {
                  type
                  pastDuration {
                    value
                    unit
                  }
                  calendarDuration {
                    unit
                  }
                }
              }
            }
          }
        }
      }
    }
    """

    static let adminDetailAPIKeyProfileTemplate = """
    query AdminDetailAPIKeyProfileTemplate($id: ID!) {
      node(id: $id) {
        ... on APIKeyProfileTemplate {
          id
          name
          description
          projectID
          linkedProfilesCount
          profile {
            name
            templateID
            templateName
            modelMappings {
              from
              to
            }
            channelIDs
            channelTags
            channelTagsMatchMode
            modelIDs
            loadBalanceStrategy
            traceStickyMode
            quota {
              requests
              totalTokens
              cost
              period {
                type
                pastDuration {
                  value
                  unit
                }
                calendarDuration {
                  unit
                }
              }
            }
          }
        }
      }
    }
    """

    static let adminDetailUser = """
    query AdminDetailUser($id: ID!) {
      node(id: $id) {
        ... on User {
          id
          createdAt
          updatedAt
          email
          status
          firstName
          lastName
          isOwner
          preferLanguage
          avatar
          scopes
          roles {
            edges {
              node {
                id
                name
                level
                projectID
              }
            }
          }
        }
      }
    }
    """

    static let adminDetailRole = """
    query AdminDetailRole($id: ID!) {
      node(id: $id) {
        ... on Role {
          id
          name
          level
          projectID
          scopes
          createdAt
          updatedAt
        }
      }
    }
    """

    static let adminDetailProject = """
    query AdminDetailProject($id: ID!) {
      node(id: $id) {
        ... on Project {
          id
          name
          description
          status
          createdAt
          updatedAt
          profiles {
            activeProfile
            profiles {
              name
              channelIDs
              channelTags
              channelTagsMatchMode
            }
          }
          projectUsers {
            id
            userID
            projectID
            isOwner
            scopes
            user {
              id
              email
              firstName
              lastName
              roles {
                edges {
                  node {
                    id
                    name
                    level
                    projectID
                  }
                }
              }
            }
          }
          users {
            edges {
              node {
                id
              }
            }
          }
        }
      }
    }
    """

    static let adminDetailDataStorage = """
    query AdminDetailDataStorage($id: ID!) {
      node(id: $id) {
        ... on DataStorage {
          id
          name
          description
          type
          primary
          status
          createdAt
          updatedAt
          settings {
            directory
            s3 {
              bucketName
              endpoint
              region
              pathStyle
            }
            gcs {
              bucketName
            }
            webdav {
              url
              username
              insecure_skip_tls
              path
            }
          }
        }
      }
    }
    """

    static let adminDetailPrompt = """
    query AdminDetailPrompt($id: ID!) {
      node(id: $id) {
        ... on Prompt {
          id
          createdAt
          updatedAt
          projectID
          name
          description
          role
          content
          status
          order
          settings {
            action {
              type
            }
            conditions {
              conditions {
                type
                modelId
                modelPattern
                apiKeyId
              }
            }
          }
        }
      }
    }
    """

    static let adminDetailPromptProtectionRule = """
    query AdminDetailPromptProtectionRule($id: ID!) {
      node(id: $id) {
        ... on PromptProtectionRule {
          id
          createdAt
          updatedAt
          name
          description
          pattern
          status
          settings {
            action
            replacement
            scopes
          }
        }
      }
    }
    """

    static let adminRevealAPIKey = """
    query AdminRevealAPIKey($id: ID!) {
      node(id: $id) {
        ... on APIKey {
          id
          key
        }
      }
    }
    """

    static let adminRevealWebhookNotifierConfig = """
    query AdminRevealWebhookNotifierConfig {
      webhookNotifierConfig {
        targets {
          name
          enabled
          url
          proxy {
            type
            url
            username
            password
          }
          timeoutMs
          headers {
            key
            value
          }
          body
        }
        subscriptions {
          event
          targetNames
        }
      }
    }
    """

    static let adminRevealProxyPresets = """
    query AdminRevealProxyPresets {
      proxyPresets {
        name
        url
        username
        password
      }
    }
    """

    static let adminProvidersCatalog = """
    query AdminProvidersCatalog {
      providersCatalog {
        data
        fetchedAt
        source
        filtered
      }
    }
    """

    static let adminRefreshProvidersCatalog = """
    mutation AdminRefreshProvidersCatalog {
      refreshProvidersCatalog {
        data
        fetchedAt
        source
        filtered
      }
    }
    """

    static func document(_ key: String) -> String? {
        switch key {
        case "adminGetApiKeys": return adminGetApiKeys
        case "adminCreateAPIKey": return adminCreateAPIKey
        case "adminUpdateAPIKey": return adminUpdateAPIKey
        case "adminUpdateAPIKeyStatus": return adminUpdateAPIKeyStatus
        case "adminUpdateAPIKeyProfiles": return adminUpdateAPIKeyProfiles
        case "adminBulkDisableAPIKeys": return adminBulkDisableAPIKeys
        case "adminBulkEnableAPIKeys": return adminBulkEnableAPIKeys
        case "adminBulkArchiveAPIKeys": return adminBulkArchiveAPIKeys
        case "adminRotateAPIKey": return adminRotateAPIKey
        case "adminAPIKeyQuotaUsages": return adminAPIKeyQuotaUsages
        case "adminAPIKeyTokenUsageStats": return adminAPIKeyTokenUsageStats
        case "adminApiKeyProfileTemplates": return adminApiKeyProfileTemplates
        case "adminCreateApiKeyProfileTemplate": return adminCreateApiKeyProfileTemplate
        case "adminUpdateApiKeyProfileTemplate": return adminUpdateApiKeyProfileTemplate
        case "adminDeleteApiKeyProfileTemplate": return adminDeleteApiKeyProfileTemplate
        case "adminLoadApiKeyProfileTemplate": return adminLoadApiKeyProfileTemplate
        case "adminDataStorages": return adminDataStorages
        case "adminCreateDataStorage": return adminCreateDataStorage
        case "adminUpdateDataStorage": return adminUpdateDataStorage
        case "adminAddUserToProject": return adminAddUserToProject
        case "adminRemoveUserFromProject": return adminRemoveUserFromProject
        case "adminUpdateProjectUser": return adminUpdateProjectUser
        case "adminAllUsers": return adminAllUsers
        case "adminGetProjectRoles": return adminGetProjectRoles
        case "adminCreateRole": return adminCreateRole
        case "adminUpdateRole": return adminUpdateRole
        case "adminDeleteRole": return adminDeleteRole
        case "adminGetProjects": return adminGetProjects
        case "adminCreateProject": return adminCreateProject
        case "adminUpdateProject": return adminUpdateProject
        case "adminUpdateProjectStatus": return adminUpdateProjectStatus
        case "adminDeleteProject": return adminDeleteProject
        case "adminMyProjects": return adminMyProjects
        case "adminUpdateProjectProfiles": return adminUpdateProjectProfiles
        case "adminGetPromptProtectionRules": return adminGetPromptProtectionRules
        case "adminCreatePromptProtectionRule": return adminCreatePromptProtectionRule
        case "adminUpdatePromptProtectionRule": return adminUpdatePromptProtectionRule
        case "adminDeletePromptProtectionRule": return adminDeletePromptProtectionRule
        case "adminUpdatePromptProtectionRuleStatus": return adminUpdatePromptProtectionRuleStatus
        case "adminBulkDeletePromptProtectionRules": return adminBulkDeletePromptProtectionRules
        case "adminBulkEnablePromptProtectionRules": return adminBulkEnablePromptProtectionRules
        case "adminBulkDisablePromptProtectionRules": return adminBulkDisablePromptProtectionRules
        case "adminPreviewPromptProtectionRule": return adminPreviewPromptProtectionRule
        case "adminGetPrompts": return adminGetPrompts
        case "adminCreatePrompt": return adminCreatePrompt
        case "adminUpdatePrompt": return adminUpdatePrompt
        case "adminDeletePrompt": return adminDeletePrompt
        case "adminUpdatePromptStatus": return adminUpdatePromptStatus
        case "adminBulkDeletePrompts": return adminBulkDeletePrompts
        case "adminBulkDisablePrompts": return adminBulkDisablePrompts
        case "adminBulkEnablePrompts": return adminBulkEnablePrompts
        case "adminBulkDeleteRoles": return adminBulkDeleteRoles
        case "adminSystemVersion": return adminSystemVersion
        case "adminCheckForUpdate": return adminCheckForUpdate
        case "adminGetCacheDiagnostics": return adminGetCacheDiagnostics
        case "adminClearCache": return adminClearCache
        case "adminBrandSettings": return adminBrandSettings
        case "adminStoragePolicy": return adminStoragePolicy
        case "adminUpdateBrandSettings": return adminUpdateBrandSettings
        case "adminUpdateStoragePolicy": return adminUpdateStoragePolicy
        case "adminRetryPolicy": return adminRetryPolicy
        case "adminUpdateRetryPolicy": return adminUpdateRetryPolicy
        case "adminWebhookNotifierConfig": return adminWebhookNotifierConfig
        case "adminUpdateWebhookNotifierConfig": return adminUpdateWebhookNotifierConfig
        case "adminDefaultDataStorageID": return adminDefaultDataStorageID
        case "adminUpdateDefaultDataStorage": return adminUpdateDefaultDataStorage
        case "adminOnboardingInfo": return adminOnboardingInfo
        case "adminCompleteOnboarding": return adminCompleteOnboarding
        case "adminCompleteSystemModelSettingOnboarding": return adminCompleteSystemModelSettingOnboarding
        case "adminCompleteAutoDisableChannelOnboarding": return adminCompleteAutoDisableChannelOnboarding
        case "adminTriggerGcCleanup": return adminTriggerGcCleanup
        case "adminPreviewGcCleanup": return adminPreviewGcCleanup
        case "adminModelSettings": return adminModelSettings
        case "adminUpdateModelSettings": return adminUpdateModelSettings
        case "adminSystemChannelSettings": return adminSystemChannelSettings
        case "adminUpdateChannelSettings": return adminUpdateChannelSettings
        case "adminSystemGeneralSettings": return adminSystemGeneralSettings
        case "adminUpdateSystemGeneralSettings": return adminUpdateSystemGeneralSettings
        case "adminVideoStorageSettings": return adminVideoStorageSettings
        case "adminUpdateVideoStorageSettings": return adminUpdateVideoStorageSettings
        case "adminSecuritySettings": return adminSecuritySettings
        case "adminUpdateSecuritySettings": return adminUpdateSecuritySettings
        case "adminBackup": return adminBackup
        case "adminRestore": return adminRestore
        case "adminAutoBackupSettings": return adminAutoBackupSettings
        case "adminUpdateAutoBackupSettings": return adminUpdateAutoBackupSettings
        case "adminTriggerAutoBackup": return adminTriggerAutoBackup
        case "adminProxyPresets": return adminProxyPresets
        case "adminSaveProxyPreset": return adminSaveProxyPreset
        case "adminDeleteProxyPreset": return adminDeleteProxyPreset
        case "adminUserAgentPassThroughSettings": return adminUserAgentPassThroughSettings
        case "adminUpdateUserAgentPassThroughSettings": return adminUpdateUserAgentPassThroughSettings
        case "adminPassThroughSettings": return adminPassThroughSettings
        case "adminUpdatePassThroughSettings": return adminUpdatePassThroughSettings
        case "adminUsageCostInjectionSettings": return adminUsageCostInjectionSettings
        case "adminUpdateUsageCostInjectionSettings": return adminUpdateUsageCostInjectionSettings
        case "adminQuotaEnforcementSettings": return adminQuotaEnforcementSettings
        case "adminUpdateQuotaEnforcementSettings": return adminUpdateQuotaEnforcementSettings
        case "adminProviderQuotaCollectionSettings": return adminProviderQuotaCollectionSettings
        case "adminUpdateProviderQuotaCollectionSettings": return adminUpdateProviderQuotaCollectionSettings
        case "adminCatalogSettings": return adminCatalogSettings
        case "adminUpdateCatalogSettings": return adminUpdateCatalogSettings
        case "adminAllScopes": return adminAllScopes
        case "adminMe": return adminMe
        case "adminCreateUser": return adminCreateUser
        case "adminUpdateUser": return adminUpdateUser
        case "adminUpdateUserStatus": return adminUpdateUserStatus
        case "adminDeleteUser": return adminDeleteUser
        case "adminSystemStatus": return adminSystemStatus
        case "adminUpdateMe": return adminUpdateMe
        case "adminUpdateMyPassword": return adminUpdateMyPassword
        case "adminUnlinkOIDCIdentity": return adminUnlinkOIDCIdentity
        case "adminProjectUsers": return adminProjectUsers
        case "adminDetailAPIKey": return adminDetailAPIKey
        case "adminDetailAPIKeyProfileTemplate": return adminDetailAPIKeyProfileTemplate
        case "adminDetailUser": return adminDetailUser
        case "adminDetailRole": return adminDetailRole
        case "adminDetailProject": return adminDetailProject
        case "adminDetailDataStorage": return adminDetailDataStorage
        case "adminDetailPrompt": return adminDetailPrompt
        case "adminDetailPromptProtectionRule": return adminDetailPromptProtectionRule
        case "adminRevealAPIKey": return adminRevealAPIKey
        case "adminRevealWebhookNotifierConfig": return adminRevealWebhookNotifierConfig
        case "adminRevealProxyPresets": return adminRevealProxyPresets
        case "adminProvidersCatalog": return adminProvidersCatalog
        case "adminRefreshProvidersCatalog": return adminRefreshProvidersCatalog
        default: return nil
        }
    }
}
