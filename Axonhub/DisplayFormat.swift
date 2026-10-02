import Foundation

/// UI-only formatting. Never use abbreviated values in API payloads or editors.
enum DisplayFormat {
    static func compact(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        let magnitude = abs(value)
        let scales: [(Double, String)] = [(1_000, "K"), (1_000_000, "M"), (1_000_000_000, "B")]
        var index = scales.lastIndex(where: { magnitude >= $0.0 })
        if let selected = index, selected < scales.count - 1,
           (magnitude / scales[selected].0 * 10).rounded() / 10 >= 1_000 {
            index = selected + 1
        }
        let divisor = index.map { scales[$0].0 } ?? 1
        let suffix = index.map { scales[$0].1 } ?? ""
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = index == nil ? 0 : 1
        return (formatter.string(from: NSNumber(value: value / divisor)) ?? "—") + suffix
    }

    static func isTokenQuantity(_ key: String) -> Bool {
        let key = key.lowercased()
        return key.contains("tokens") && !key.contains("persecond") || ["maxtoken", "tokenlimit", "tokenquota"].contains(key)
    }

    static func date(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.calendar = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: value)
    }

    static func date(_ text: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let value = iso.date(from: text) ?? ISO8601DateFormatter().date(from: text) {
            return date(value)
        }
        // Server daily buckets are date-only labels, not UTC instants.
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.calendar = Calendar(identifier: .gregorian)
        parser.timeZone = .autoupdatingCurrent
        parser.dateFormat = "yyyy-MM-dd"
        parser.isLenient = false
        if text.count == 10, let value = parser.date(from: text), parser.string(from: value) == text {
            let formatter = DateFormatter()
            formatter.locale = .autoupdatingCurrent
            formatter.calendar = .autoupdatingCurrent
            formatter.timeZone = .autoupdatingCurrent
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: value)
        }
        return text
    }
}
