import Foundation

/// The condition (`when`) editor of a model association, matching the web console's filter builder
/// in models-association-dialog.tsx: an AND of groups, each group an AND/OR of conditions.
enum ConditionValueType: Sendable { case number, boolean, string }

struct ConditionField: Identifiable, Hashable, Sendable {
    let value: String
    let label: String
    let type: ConditionValueType
    let operators: [String]
    var options: [String] = []
    var placeholder: String = ""
    var subFieldSuggestions: [String]? = nil
    var id: String { value }
}

enum ConditionCatalog {
    static let requestFormats = [
        "openai/chat_completions", "openai/completions", "openai/responses", "openai/responses_compact",
        "openai/image_generation", "openai/image_edit", "openai/image_variation", "openai/embeddings", "openai/video",
        "openai/moderations", "openai/alpha_search", "openai/decisions", "openai/audio_speech",
        "openai/audio_transcriptions", "openai/audio_translations", "anthropic/messages", "gemini/contents",
        "gemini/embeddings", "aisdk/text", "aisdk/datastream", "jina/rerank", "jina/embeddings", "typesafe/systemone",
        "ollama/chat", "seedance/video",
    ]

    static let headerSuggestions = [
        "User-Agent", "X-Model", "X-Request-Id", "X-Trace-Id", "Accept", "Accept-Language", "Content-Type", "Origin", "Referer",
    ]

    static let headerPrefix = "request_header."

    private static let equality = ["eq", "ne"]

    static let fields: [ConditionField] = [
        ConditionField(value: "prompt_tokens", label: "提示词的词元", type: .number, operators: ["lt", "lte", "gt", "gte"], placeholder: "输入词元阈值"),
        ConditionField(value: "stream", label: "流式", type: .boolean, operators: equality),
        ConditionField(value: "has_image", label: "包含图片", type: .boolean, operators: equality),
        ConditionField(value: "has_video", label: "包含视频", type: .boolean, operators: equality),
        ConditionField(value: "has_document", label: "包含文档", type: .boolean, operators: equality),
        ConditionField(value: "has_audio", label: "包含音频", type: .boolean, operators: equality),
        ConditionField(value: "request_format", label: "请求格式", type: .string, operators: equality, options: requestFormats, placeholder: "选择请求格式"),
        ConditionField(value: "reasoning_effort", label: "推理强度", type: .string, operators: equality, placeholder: "例如 high、xhigh、max"),
        ConditionField(value: "daily_time", label: "每日时间段", type: .string, operators: ["within", "not_within"], placeholder: "HH:mm-HH:mm"),
        ConditionField(value: "request_header", label: "请求头", type: .string,
                       operators: ["eq", "ne", "contains", "not_contains", "start_with", "end_with"],
                       placeholder: "头部值", subFieldSuggestions: headerSuggestions),
    ]

    static let operatorLabels: [String: String] = [
        "lt": "< 小于", "lte": "<= 小于等于", "gt": "> 大于", "gte": ">= 大于等于", "eq": "= 等于", "ne": "!= 不等于",
        "within": "位于时间段", "not_within": "不在时间段", "contains": "包含", "not_contains": "不包含",
        "start_with": "开头为", "end_with": "结尾为",
    ]

    /// The field definition for a condition's field, including `request_header.<name>`.
    static func field(for name: String) -> ConditionField? {
        if let exact = fields.first(where: { $0.value == name }) { return exact }
        if name.hasPrefix(headerPrefix) { return fields.first { $0.value == "request_header" } }
        return nil
    }

    static func isValidOperator(field name: String, op: String) -> Bool {
        Self.field(for: name)?.operators.contains(op) ?? false
    }

    static func isValidDailyTime(_ text: String) -> Bool {
        guard text.range(of: #"^([01]\d|2[0-3]):[0-5]\d-([01]\d|2[0-3]):[0-5]\d$"#, options: .regularExpression) != nil else { return false }
        let parts = text.split(separator: "-")
        return parts.count == 2 && parts[0] != parts[1]
    }
}

struct AssociationCondition: Identifiable, Hashable, Sendable {
    var id = UUID()
    var field: String
    var op: String
    var value: JSONValue

    /// A new condition starts on the first field, as on the web.
    static func makeDefault() -> AssociationCondition {
        AssociationCondition(field: "prompt_tokens", op: "lt", value: .string(""))
    }

    var definition: ConditionField? { ConditionCatalog.field(for: field) }

    /// Base field (`request_header` for `request_header.X-Model`).
    var baseField: String { field.hasPrefix(ConditionCatalog.headerPrefix) ? "request_header" : field }

    var headerName: String {
        get { field.hasPrefix(ConditionCatalog.headerPrefix) ? String(field.dropFirst(ConditionCatalog.headerPrefix.count)) : "" }
        set { field = ConditionCatalog.headerPrefix + newValue }
    }

    /// Switch the field, resetting operator and value as the web filter builder does.
    mutating func setBaseField(_ name: String) {
        guard let def = ConditionCatalog.fields.first(where: { $0.value == name }) else { return }
        field = def.subFieldSuggestions != nil ? ConditionCatalog.headerPrefix : name
        op = def.operators.first ?? "eq"
        value = def.type == .boolean ? .bool(true) : .string("")
    }

    var textValue: String {
        switch value {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() ? String(Int64(n)) : String(n)
        case .bool(let b): return b ? "true" : "false"
        default: return ""
        }
    }

    mutating func setText(_ text: String) {
        if definition?.type == .number {
            let t = text.trimmingCharacters(in: .whitespaces)
            value = t.isEmpty ? .string("") : (Double(t).map { .number($0) } ?? .string(t))
        } else {
            value = .string(text)
        }
    }

    /// Returns a problem description, or nil when the condition can be saved.
    var validationError: String? {
        guard let def = definition else { return "未知字段 \(field)" }
        if !def.operators.contains(op) { return "请选择运算符" }
        if def.subFieldSuggestions != nil && headerName.trimmingCharacters(in: .whitespaces).isEmpty { return "请填写头部名称" }
        switch def.type {
        case .number:
            if case .number = value { return nil }
            return textValue.isEmpty ? "请填写值" : "值必须是数字"
        case .boolean:
            if case .bool = value { return nil }
            return "值必须是是或否"
        case .string:
            if textValue.isEmpty { return "请填写值" }
            if field == "daily_time" && !ConditionCatalog.isValidDailyTime(textValue) { return "时间段格式为 HH:mm-HH:mm，且起止不同" }
            return nil
        }
    }

    var summary: String {
        let name: String
        if baseField == "request_header" { name = "请求头 \(headerName)" } else { name = definition?.label ?? field }
        let opLabel = ConditionCatalog.operatorLabels[op] ?? op
        let v: String
        if case .bool(let b) = value { v = b ? "是" : "否" } else { v = textValue }
        return "\(name) \(opLabel) \(v)"
    }

    var json: JSONValue {
        .object(["type": .string("condition"), "field": .string(field), "operator": .string(op), "value": value])
    }
}

struct AssociationConditionGroup: Identifiable, Hashable, Sendable {
    var id = UUID()
    var logic: String = "and"
    var conditions: [AssociationCondition] = []

    var json: JSONValue {
        .object(["type": .string("group"), "logic": .string(logic == "or" ? "or" : "and"), "conditions": .array(conditions.map(\.json))])
    }
}

struct AssociationWhen: Hashable, Sendable {
    var enabled = false
    var groups: [AssociationConditionGroup] = []

    /// Reads `when` the way `readPromptTokensCondition` does: groups one level deep, unknown
    /// fields and operators dropped, nested groups flattened into their parent group.
    init(enabled: Bool = false, groups: [AssociationConditionGroup] = []) {
        self.enabled = enabled
        self.groups = groups
    }

    init(_ when: JSONValue?) {
        guard case .object(let o)? = when else { return }
        enabled = o["enabled"]?.boolValue ?? false
        guard enabled, let condition = o["condition"] else { return }
        if condition["type"]?.stringValue == "group" {
            let children: [JSONValue]
            if case .array(let a)? = condition["conditions"] { children = a } else { children = [] }
            for child in children {
                if child["type"]?.stringValue == "group" {
                    groups.append(AssociationConditionGroup(logic: child["logic"]?.stringValue == "or" ? "or" : "and",
                                                            conditions: Self.leafConditions(child)))
                } else if let leaf = Self.leaf(child) {
                    // A bare condition at the top level becomes its own group.
                    groups.append(AssociationConditionGroup(conditions: [leaf]))
                }
            }
        } else if let leaf = Self.leaf(condition) {
            groups.append(AssociationConditionGroup(conditions: [leaf]))
        }
    }

    private static func leafConditions(_ node: JSONValue) -> [AssociationCondition] {
        guard case .array(let a)? = node["conditions"] else { return [] }
        return a.flatMap { child -> [AssociationCondition] in
            if child["type"]?.stringValue == "group" { return leafConditions(child) }
            return leaf(child).map { [$0] } ?? []
        }
    }

    private static func leaf(_ node: JSONValue) -> AssociationCondition? {
        guard let field = node["field"]?.stringValue, let op = node["operator"]?.stringValue,
              ConditionCatalog.isValidOperator(field: field, op: op) else { return nil }
        var value = node["value"] ?? .string("")
        if field == "prompt_tokens", let n = value.doubleValue { value = .number(n) }
        return AssociationCondition(field: field, op: op, value: value)
    }

    /// `buildAssociationWhen`: drops empty conditions and groups; nil when disabled or empty.
    var json: JSONValue? {
        let cleaned = groups.compactMap { group -> AssociationConditionGroup? in
            var g = group
            g.conditions = group.conditions.filter { c in
                if c.textValue.isEmpty { return false }
                if c.field.hasPrefix(ConditionCatalog.headerPrefix) && c.headerName.isEmpty { return false }
                return c.definition != nil
            }
            return g.conditions.isEmpty ? nil : g
        }
        guard enabled, !cleaned.isEmpty else { return nil }
        return .object([
            "enabled": .bool(true),
            "condition": .object(["type": .string("group"), "logic": .string("and"), "conditions": .array(cleaned.map(\.json))]),
        ])
    }

    var validationError: String? {
        guard enabled else { return nil }
        if groups.isEmpty { return "至少添加一个条件" }
        for group in groups {
            if group.conditions.isEmpty { return "每个条件组至少要有一个条件" }
            if let error = group.conditions.lazy.compactMap(\.validationError).first { return error }
        }
        return nil
    }

    var usesDailyTime: Bool { groups.contains { $0.conditions.contains { $0.field == "daily_time" } } }
}
