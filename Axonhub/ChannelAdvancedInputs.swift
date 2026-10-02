import SwiftUI

/// Generated from official beta10 SDL at 939b2bc; includes recursive FilterConditionInput.
/// Unknown stored keys are retained, but unknown mutation keys fail validation.
enum ChannelInputSchema {
    static let fields: [String: [String: String]] = [
        "APIKeyAutoDisableRuleInput": ["statusCodes": "[Int!]", "keywordPatterns": "[String!]", "times": "Int!", "action": "APIKeyAutoDisableAction!", "disableDurationMinutes": "Int", "disableUntilCron": "String", "disableUntilTimezone": "String"],
        "BulkCreateChannelsInput": ["type": "ChannelType!", "name": "String!", "tags": "[String!]", "baseURL": "String", "apiKeys": "[String!]!", "supportedModels": "[String!]!", "autoSyncSupportedModels": "Boolean", "defaultTestModel": "String!", "settings": "ChannelSettingsInput", "policies": "ChannelPoliciesInput", "orderingWeight": "Int", "remark": "String"],
        "BulkImportChannelItem": ["type": "String!", "name": "String!", "baseURL": "String", "apiKey": "String", "supportedModels": "[String!]!", "defaultTestModel": "String!"],
        "BulkImportChannelsInput": ["channels": "[BulkImportChannelItem!]!"],
        "BulkUpdateChannelOrderingInput": ["channels": "[ChannelOrderingItem!]!"],
        "ChannelCredentialsInput": ["apiKey": "String", "apiKeys": "[String!]", "gcp": "GCPCredentialInput", "oauth": "OAuthCredentialsInput", "managementApiKey": "String"],
        "ChannelEndpointInput": ["apiFormat": "String!", "path": "String", "baseURL": "String", "transport": "String"],
        "ChannelModelAssociationInput": ["channelId": "Int!", "modelId": "String!"],
        "ChannelOrderingItem": ["id": "ID!", "orderingWeight": "Int!"],
        "ChannelPoliciesInput": ["stream": "CapabilityPolicy", "apiKeyAutoDisableRules": "[APIKeyAutoDisableRuleInput!]"],
        "ChannelProviderQuotaSettingsInput": ["commandCode": "CommandCodeQuotaSettingsInput"],
        "ChannelRateLimitInput": ["rpm": "Int", "tpm": "Int", "maxConcurrent": "Int", "queueSize": "Int", "queueTimeoutMs": "Int"],
        "ChannelRegexAssociationInput": ["channelId": "Int!", "pattern": "String!"],
        "ChannelSettingsInput": ["extraModelPrefix": "String", "modelMappings": "[ModelMappingInput!]", "autoTrimedModelPrefixes": "[String!]", "hideOriginalModels": "Boolean", "hideMappedModels": "Boolean", "lowercaseModelId": "Boolean", "proxy": "ProxyConfigInput", "transformOptions": "TransformOptionsInput", "headerOverrideOperations": "[OverrideOperationInput!]", "bodyOverrideOperations": "[OverrideOperationInput!]", "passThroughUserAgent": "Boolean", "passThroughBody": "Boolean", "rateLimit": "ChannelRateLimitInput", "retryableStatusCodes": "[Int!]", "retryableErrorPatterns": "[RetryableErrorPatternInput!]", "modelProtocols": "[ModelProtocolInput!]", "providerQuota": "ChannelProviderQuotaSettingsInput"],
        "ChannelTagsModelAssociationInput": ["channelTags": "[String!]!", "modelId": "String!"],
        "ChannelTagsRegexAssociationInput": ["channelTags": "[String!]!", "pattern": "String!"],
        "CommandCodeQuotaSettingsInput": ["authCookie": "String"],
        "CreateChannelOverrideTemplateInput": ["name": "String!", "description": "String", "headerOverrideOperations": "[OverrideOperationInput!]", "bodyOverrideOperations": "[OverrideOperationInput!]"],
        "CreateModelInput": ["developer": "String!", "modelID": "String!", "type": "ModelType", "name": "String!", "icon": "String!", "group": "String!", "modelCard": "ModelCardInput!", "settings": "ModelSettingsInput!", "remark": "String"],
        "DailyTimeRangeInput": ["start": "String!", "end": "String!"],
        "DateRangeInput": ["start": "String!", "end": "String!"],
        "ExcludeAssociationInput": ["channelNamePattern": "String", "channelIds": "[Int!]", "channelTags": "[String!]"],
        "FilterConditionInput": ["type": "FilterConditionType!", "logic": "String", "conditions": "[FilterConditionInput!]", "field": "String", "operator": "String", "value": "Any"],
        "GCPCredentialInput": ["region": "String!", "projectID": "String!", "jsonData": "String!"],
        "ModelAssociationInput": ["type": "String!", "priority": "Int", "disabled": "Boolean", "when": "ModelAssociationWhenInput", "channelModel": "ChannelModelAssociationInput", "channelRegex": "ChannelRegexAssociationInput", "regex": "RegexAssociationInput", "modelId": "ModelIDAssociationInput", "channelTagsModel": "ChannelTagsModelAssociationInput", "channelTagsRegex": "ChannelTagsRegexAssociationInput"],
        "ModelAssociationWhenInput": ["enabled": "Boolean", "condition": "FilterConditionInput"],
        "ModelCardCostInput": ["input": "Float", "output": "Float", "cacheRead": "Float", "cacheWrite": "Float"],
        "ModelCardInput": ["reasoning": "ModelCardReasoningInput", "toolCall": "Boolean", "temperature": "Boolean", "modalities": "ModelCardModalitiesInput", "vision": "Boolean", "cost": "ModelCardCostInput", "limit": "ModelCardLimitInput", "knowledge": "String", "releaseDate": "String", "lastUpdated": "String"],
        "ModelCardLimitInput": ["context": "Int", "output": "Int"],
        "ModelCardModalitiesInput": ["input": "[String!]", "output": "[String!]"],
        "ModelCardReasoningInput": ["supported": "Boolean", "default": "Boolean"],
        "ModelIDAssociationInput": ["modelId": "String!", "exclude": "[ExcludeAssociationInput!]"],
        "ModelMappingInput": ["from": "String!", "to": "String!"],
        "ModelPriceInput": ["items": "[ModelPriceItemInput!]!", "schedule": "PriceScheduleInput"],
        "ModelPriceItemInput": ["itemCode": "PriceItemCode!", "pricing": "PricingInput!", "promptWriteCacheVariants": "[PromptWriteCacheVariantInput!]"],
        "ModelProtocolInput": ["model": "String!", "apiFormats": "[String!]!", "enabled": "Boolean"],
        "ModelSettingsInput": ["disableDeveloperSettingsInheritance": "Boolean", "associations": "[ModelAssociationInput!]!", "loadBalancerStrategy": "String", "traceStickyMode": "String"],
        "OAuthCredentialsInput": ["accessToken": "String", "refreshToken": "String", "clientID": "String", "expiresAt": "Time", "tokenType": "String", "scopes": "[String!]"],
        "OverrideMatchInput": ["path": "String!", "eq": "String!"],
        "OverrideOperationInput": ["op": "String!", "path": "String", "from": "String", "to": "String", "value": "String", "condition": "String", "match": "OverrideMatchInput", "index": "Int", "splat": "Boolean"],
        "OverrideWhenInput": ["dailyTime": "DailyTimeRangeInput", "weekdays": "[Int!]", "dateRange": "DateRangeInput"],
        "PriceOverrideInput": ["name": "String!", "priority": "Int!", "when": "OverrideWhenInput!", "items": "[ModelPriceItemInput!]!"],
        "PriceScheduleInput": ["timezone": "String!", "overrides": "[PriceOverrideInput!]!"],
        "PriceTierInput": ["upTo": "Int", "pricePerUnit": "Decimal!"],
        "PricingInput": ["mode": "PricingMode!", "flatFee": "Decimal", "usagePerUnit": "Decimal", "usageTiered": "TieredPricingInput"],
        "PromptWriteCacheVariantInput": ["variantCode": "PromptWriteCacheVariantCode!", "pricing": "PricingInput!"],
        "ProxyConfigInput": ["type": "ProxyType!", "url": "String", "username": "String", "password": "String", "disableConnectionReuse": "Boolean"],
        "ReasoningEffortMappingInput": ["from": "String!", "to": "String!"],
        "RegexAssociationInput": ["pattern": "String!", "exclude": "[ExcludeAssociationInput!]"],
        "RetryableErrorPatternInput": ["pattern": "String!", "regex": "Boolean"],
        "SaveChannelModelPriceInput": ["modelId": "String!", "price": "ModelPriceInput!"],
        "TieredPricingInput": ["tiers": "[PriceTierInput!]!"],
        "TransformOptionsInput": ["forceArrayInstructions": "Boolean", "forceArrayInputs": "Boolean", "replaceDeveloperRoleWithSystem": "Boolean", "reasoningEffortMapping": "[ReasoningEffortMappingInput!]"],
    ]
    static let enums: [String: [String]] = [
        "ChannelType": ChannelType.allCases.map(\.rawValue),
        "ModelType": ModelType.allCases.map(\.rawValue),
        "APIKeyAutoDisableAction": ["temporary_disable", "disable_until_cron", "permanent_disable", "permanent_disable_delete"],
        "APIKeyOrderField": ["CREATED_AT", "UPDATED_AT", "NAME"],
        "APIKeyProfileTemplateOrderField": ["CREATED_AT", "UPDATED_AT"],
        "APIKeyQuotaCalendarDurationUnit": ["day", "month"],
        "APIKeyQuotaPastDurationUnit": ["minute", "hour", "day"],
        "APIKeyQuotaPeriodType": ["all_time", "past_duration", "calendar_duration"],
        "CapabilityPolicy": ["unlimited", "require", "forbid"],
        "ChannelModelPriceOrderField": ["CREATED_AT", "UPDATED_AT"],
        "ChannelModelPriceVersionOrderField": ["CREATED_AT", "UPDATED_AT"],
        "ChannelOrderField": ["CREATED_AT", "UPDATED_AT", "TYPE", "NAME", "STATUS", "ORDERING_WEIGHT"],
        "ChannelOverrideTemplateOrderField": ["CREATED_AT", "UPDATED_AT"],
        "ChannelTagsMatchMode": ["any", "all", "none"],
        "DataStorageOrderField": ["CREATED_AT", "UPDATED_AT"],
        "FilterConditionType": ["condition", "group"],
        "ModelOrderField": ["CREATED_AT", "UPDATED_AT", "NAME"],
        "OIDCIdentityOrderField": ["CREATED_AT", "UPDATED_AT"],
        "OrderDirection": ["ASC", "DESC"],
        "OverrideApplyMode": ["MERGE", "REPLACE"],
        "PriceItemCode": ["prompt_tokens", "completion_tokens", "prompt_cached_tokens", "prompt_write_cached_tokens"],
        "PricingMode": ["flat_fee", "usage_per_unit", "usage_tiered", "usage_volume"],
        "ProjectOrderField": ["CREATED_AT", "UPDATED_AT"],
        "PromptOrderField": ["CREATED_AT", "UPDATED_AT", "ORDER"],
        "PromptProtectionRuleOrderField": ["CREATED_AT", "UPDATED_AT", "NAME"],
        "PromptWriteCacheVariantCode": ["five_min", "one_hour"],
        "ProviderQuotaStatusOrderField": ["CREATED_AT", "UPDATED_AT"],
        "ProxyType": ["DISABLED", "ENVIRONMENT", "URL"],
        "RequestExecutionOrderField": ["CREATED_AT", "UPDATED_AT"],
        "RequestOrderField": ["CREATED_AT", "UPDATED_AT"],
        "RoleOrderField": ["CREATED_AT", "UPDATED_AT"],
        "SystemOrderField": ["CREATED_AT", "UPDATED_AT"],
        "ThreadOrderField": ["CREATED_AT", "UPDATED_AT"],
        "TraceOrderField": ["CREATED_AT", "UPDATED_AT"],
        "UsageLogOrderField": ["CREATED_AT", "UPDATED_AT"],
        "UserOrderField": ["CREATED_AT", "UPDATED_AT"],
        "UserProjectOrderField": ["CREATED_AT", "UPDATED_AT"],
        "UserRoleOrderField": ["CREATED_AT", "UPDATED_AT"],
    ]
    static func validate(_ value: JSON, type: String) throws {
        if value.isNull {
            guard !type.hasSuffix("!") else { throw ManagementError.invalidFields }; return
        }
        let clean = type.hasSuffix("!") ? String(type.dropLast()) : type
        if clean.hasPrefix("[") {
            guard case .array(let values) = value else { throw ManagementError.invalidFields }
            for item in values { try validate(item, type: String(clean.dropFirst().dropLast())) }; return
        }
        if let shape = fields[clean] {
            guard case .object(let object) = value, Set(object.keys).isSubset(of: Set(shape.keys)) else { throw ManagementError.invalidFields }
            for (key, fieldType) in shape {
                if let field = object[key] { try validate(field, type: fieldType) }
                else if fieldType.hasSuffix("!") { throw ManagementError.invalidFields }
            }
        } else if let choices = enums[clean] {
            guard case .string(let s) = value, choices.contains(s) else { throw ManagementError.invalidFields }
        } else {
            switch clean {
            case "Boolean": guard case .bool = value else { throw ManagementError.invalidFields }
            case "Int": guard case .number(let n) = value, n.isFinite, n.rounded() == n, (-2147483648...2147483647).contains(n) else { throw ManagementError.invalidFields }
            case "Float": guard case .number(let n) = value, n.isFinite else { throw ManagementError.invalidFields }
            case "String", "Time", "ID": guard case .string = value else { throw ManagementError.invalidFields }
            case "Decimal":
                let text: String
                if case .number(let n) = value { guard n.isFinite, n >= 0 else { throw ManagementError.invalidFields }; text = String(n) }
                else if case .string(let s) = value { text = s }
                else { throw ManagementError.invalidFields }
                guard let decimal = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), decimal >= 0 else { throw ManagementError.invalidFields }
            default: break // Any custom scalar, further semantic checks follow.
            }
        }
    }
    static func seed(_ type: String) -> JSON {
        let t = type.trimmingCharacters(in: CharacterSet(charactersIn: "!"))
        if t.hasPrefix("[") { return .array([]) }
        if let fields = fields[t] { return .object(fields.filter { $0.value.hasSuffix("!") }.mapValues { seed($0) }) }
        if let first = enums[t]?.first { return .string(first) }
        switch t { case "Boolean": return .bool(false); case "Int", "Float": return .number(0); default: return .string("") }
    }
}

/// Lazy navigation avoids recursively constructing SwiftUI view types. Sensitive strings
/// remain in ephemeral view state and SecureField only; never copied to defaults/logs.
struct ChannelSchemaFields: View {
    @Binding var value: JSON
    let type: String
    var path = ""
    var secure = false
    private var clean: String { type.trimmingCharacters(in: CharacterSet(charactersIn: "!")) }
    var body: some View {
        Group {
            if clean.hasPrefix("[") {
                let element = String(clean.dropFirst().dropLast())
                ForEach(Array(value.array.indices), id: \.self) { index in
                    NavigationLink("\(index + 1)") {
                        Form { ChannelSchemaFields(value: item(index), type: element, path: path, secure: secure) }
                    }
                    Button("移除第 \(index + 1) 项", role: .destructive) { var a = value.array; a.remove(at: index); value = .array(a) }
                }
                Button("添加一项") { value = .array(value.array + [ChannelInputSchema.seed(element)]) }
            } else if let fields = ChannelInputSchema.fields[clean] {
                ForEach(fields.keys.sorted(), id: \.self) { key in
                    let fieldType = fields[key] ?? "String"
                    let sensitive = secure || ["credentials", "proxy", "providerQuota", "headerOverrideOperations", "bodyOverrideOperations"].contains(key)
                    if value.object[key] != nil && !value[key].isNull {
                        NavigationLink(NativeAdminLabels.field(key)) { Form { ChannelSchemaFields(value: field(key), type: fieldType, path: path + "." + key, secure: sensitive) }.navigationTitle(NativeAdminLabels.field(key)) }
                        if !fieldType.hasSuffix("!") { Button(obsText("清除") + " " + NativeAdminLabels.field(key), role: .destructive) { var o = value.object; o.removeValue(forKey: key); value = .object(o) } }
                    } else {
                        Button(obsText("配置") + " " + NativeAdminLabels.field(key)) { var o = value.object; o[key] = ChannelInputSchema.seed(fieldType); value = .object(o) }
                    }
                }
            } else if let choices = ChannelInputSchema.enums[clean] {
                Picker(NativeAdminLabels.path(path), selection: stringBinding) { ForEach(choices, id: \.self) { Text(NativeAdminLabels.value($0)).tag($0) } }
            } else if let choices = stringChoices {
                Picker(NativeAdminLabels.path(path), selection: stringBinding) {
                    if !choices.contains(value.string) { Text(value.string).tag(value.string) }
                    ForEach(choices, id: \.self) { Text(NativeAdminLabels.value($0)).tag($0) }
                }
            } else if clean == "Boolean" {
                Toggle(NativeAdminLabels.path(path), isOn: Binding(get: { value.bool }, set: { value = .bool($0) }))
            } else if ["Int", "Float", "Any", "Decimal"].contains(clean) {
                LabeledEditorField(NativeAdminLabels.path(path), text: Binding(get: { value.prettyJSON }, set: { value = JSON.from($0) ?? .string($0) }))
            } else if secure {
                LabeledEditorField(NativeAdminLabels.path(path), text: stringBinding, secure: true)
            } else {
                LabeledEditorField(NativeAdminLabels.path(path), text: stringBinding)
            }
        }
    }
    private var stringChoices: [String]? {
        if path.hasSuffix("associations.type") { return ["channel_model", "channel_regex", "regex", "model_id", "channel_tags_model", "channel_tags_regex"] }
        if path.hasSuffix("loadBalancerStrategy") { return ["default", "adaptive", "failover", "circuit-breaker", "round-robin"] }
        if path.hasSuffix("traceStickyMode") { return ["default", "disabled", "prefer_previous_channel"] }
        return nil
    }
    private var stringBinding: Binding<String> { Binding(get: { value.string }, set: { value = .string($0) }) }
    private func field(_ key: String) -> Binding<JSON> { Binding(get: { value[key] }, set: { var o = value.object; o[key] = $0; value = .object(o) }) }
    private func item(_ index: Int) -> Binding<JSON> { Binding(get: { value.array.indices.contains(index) ? value.array[index] : .null }, set: { var a = value.array; guard a.indices.contains(index) else { return }; a[index] = $0; value = .array(a) }) }
}
