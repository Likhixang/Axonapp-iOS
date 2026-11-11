import Foundation

enum DateParsing {
    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Parses RFC 3339 timestamps as produced by Go (`time.RFC3339Nano`), which may carry
    /// up to nine fractional digits.
    static func parse(_ raw: String) -> Date? {
        let text = normalizeFraction(raw.trimmingCharacters(in: .whitespaces))
        return fractional.date(from: text) ?? plain.date(from: text)
    }

    static func format(_ date: Date) -> String {
        plain.string(from: date)
    }

    static func normalizeFraction(_ text: String) -> String {
        guard let tIndex = text.firstIndex(of: "T"),
              let dot = text[tIndex...].firstIndex(of: ".") else { return text }
        var end = text.index(after: dot)
        while end < text.endIndex, text[end].isNumber { end = text.index(after: end) }
        let digits = text[text.index(after: dot)..<end]
        guard !digits.isEmpty else { return text }
        var fraction = String(digits.prefix(3))
        while fraction.count < 3 { fraction += "0" }
        return String(text[..<dot]) + "." + fraction + String(text[end...])
    }
}

extension JSONDecoder {
    static let axon: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = DateParsing.parse(raw) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(raw)")
        }
        return decoder
    }()
}

enum Fmt {
    static func compact(_ value: Int?) -> String {
        guard let value else { return "—" }
        return compact(Double(value))
    }

    static func compact(_ value: Double) -> String {
        let absValue = abs(value)
        let sign = value < 0 ? "-" : ""
        switch absValue {
        case 1_000_000_000...: return sign + trim(absValue / 1_000_000_000) + "B"
        case 1_000_000...: return sign + trim(absValue / 1_000_000) + "M"
        case 10_000...: return sign + trim(absValue / 1_000) + "K"
        default:
            return sign + grouped(Int(absValue.rounded()))
        }
    }

    static func grouped(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    static func trim(_ value: Double) -> String {
        let text = value >= 100 ? String(format: "%.0f", value) : String(format: "%.1f", value)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }

    static func bytes(_ count: Int) -> String {
        if count < 1024 { return "\(count) B" }
        if count < 1024 * 1024 { return trim(Double(count) / 1024) + " KB" }
        return trim(Double(count) / 1024 / 1024) + " MB"
    }

    static func cost(_ value: Double?) -> String {
        guard let value else { return "—" }
        if value == 0 { return "$0" }
        if abs(value) < 0.01 { return String(format: "$%.4f", value) }
        if abs(value) >= 10_000 { return "$" + compact(value) }
        return String(format: "$%.2f", value)
    }

    /// Formats a fraction (0...1) as a percentage.
    static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        let scaled = value * 100
        return String(format: scaled >= 99.95 || scaled == 0 ? "%.0f%%" : "%.1f%%", scaled)
    }

    static func latency(_ ms: Double?) -> String {
        guard let ms, ms.isFinite else { return "—" }
        if ms >= 10_000 { return String(format: "%.0fs", ms / 1000) }
        if ms >= 1000 { return String(format: "%.2fs", ms / 1000) }
        return String(format: "%.0fms", ms)
    }

    static func latency(_ ms: Int?) -> String {
        latency(ms.map(Double.init))
    }

    static func throughput(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.1f tok/s", value)
    }

    static func relative(_ date: Date?) -> String {
        guard let date else { return "—" }
        #if canImport(Darwin)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
        #else
        return dateTime(date)
        #endif
    }

    static func dateTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    static func shortTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "HH:mm:ss"
        } else {
            formatter.dateFormat = "MM-dd HH:mm"
        }
        return formatter.string(from: date)
    }

    /// Masks a secret, keeping a short prefix and suffix visible.
    static func mask(_ secret: String) -> String {
        guard secret.count > 12 else { return String(repeating: "•", count: max(secret.count, 6)) }
        return String(secret.prefix(6)) + "••••••" + String(secret.suffix(4))
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfBlank: String? { trimmed.isEmpty ? nil : trimmed }

    /// Splits comma / newline separated input into a clean list.
    var listItems: [String] {
        split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == "，" })
            .map { String($0).trimmed }
            .filter { !$0.isEmpty }
    }
}

enum GUID {
    /// AxonHub ids look like `gid://axonhub/channel/12`; returns the trailing numeric part.
    static func numeric(_ id: String) -> Int? {
        guard let last = id.split(separator: "/").last else { return nil }
        return Int(last)
    }

    static func short(_ id: String) -> String {
        numeric(id).map { "#\($0)" } ?? id
    }
}
