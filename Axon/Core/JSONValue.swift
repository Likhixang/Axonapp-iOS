import Foundation

/// A lossless, Codable representation of an arbitrary JSON document.
/// Used for GraphQL variables and for raw payloads (request / response bodies).
enum JSONValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value):
            if value.rounded() == value, abs(value) < 9.0e15 {
                try container.encode(Int64(value))
            } else {
                try container.encode(value)
            }
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral,
    ExpressibleByBooleanLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral, ExpressibleByNilLiteral {
    init(stringLiteral value: String) { self = .string(value) }
    init(integerLiteral value: Int) { self = .number(Double(value)) }
    init(floatLiteral value: Double) { self = .number(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
    init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    init(dictionaryLiteral elements: (String, JSONValue)...) {
        var object: [String: JSONValue] = [:]
        for (key, value) in elements { object[key] = value }
        self = .object(object)
    }
    init(nilLiteral: ()) { self = .null }
}

extension JSONValue {
    static func int(_ value: Int) -> JSONValue { .number(Double(value)) }
    static func strings(_ values: [String]) -> JSONValue { .array(values.map { .string($0) }) }
    static func optional(_ value: String?) -> JSONValue { value.map { .string($0) } ?? .null }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var doubleValue: Double? {
        switch self {
        case .number(let value): return value
        case .string(let value): return Double(value)
        default: return nil
        }
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let object) = self { return object[key] }
        return nil
    }

    /// Foundation representation suitable for `JSONSerialization`.
    var foundationObject: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let value): return NSNumber(value: value)
        case .number(let value):
            if value.rounded() == value, abs(value) < 9.0e15 { return NSNumber(value: Int64(value)) }
            return NSNumber(value: value)
        case .string(let value): return value
        case .array(let value): return value.map { $0.foundationObject }
        case .object(let value): return value.mapValues { $0.foundationObject }
        }
    }

    /// Pretty-printed JSON text. Strings that themselves contain JSON are left as-is.
    var prettyPrinted: String {
        switch self {
        case .string(let value): return value
        case .null: return "null"
        case .bool(let value): return value ? "true" : "false"
        case .number:
            return (try? String(data: JSONEncoder().encode(self), encoding: .utf8)) ?? ""
        case .array, .object:
            let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            guard let data = try? JSONSerialization.data(withJSONObject: foundationObject, options: options),
                  let text = String(data: data, encoding: .utf8) else { return "" }
            return text
        }
    }

    var isEmptyPayload: Bool {
        switch self {
        case .null: return true
        case .string(let value): return value.isEmpty
        case .array(let value): return value.isEmpty
        case .object(let value): return value.isEmpty
        default: return false
        }
    }
}
