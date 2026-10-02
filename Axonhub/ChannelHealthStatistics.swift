import Foundation

/// Channel execution statistics, not client request counts. Zero samples are unknown, never 0%.
struct ChannelHealthStatistics {
    let success: Double
    let failed: Double
    init(_ row: JSON) {
        success = max(0, row["successCount"].number)
        failed = max(0, row["failedCount"].number)
    }
    init(rows: [JSON]) {
        success = rows.reduce(0) { $0 + max(0, $1["successCount"].number) }
        failed = rows.reduce(0) { $0 + max(0, $1["failedCount"].number) }
    }
    var total: Double { success + failed }
    var rate: Double? { total > 0 ? success / total * 100 : nil }
    var percentage: String { rate.map { $0.formatted(.number.precision(.fractionLength(1))) + "%" } ?? "—" }
    var needsAttention: Bool { failed > 0 }
}
