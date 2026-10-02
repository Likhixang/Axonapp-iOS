import SwiftUI

/// Shared, accessible visual language for dashboard and full channel analysis.
struct ChannelHealthRow: View {
    let row: JSON
    private var stats: ChannelHealthStatistics { ChannelHealthStatistics(row) }
    private var tint: Color { stats.rate == nil ? .secondary : stats.failed == 0 ? .green : .orange }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                BrandMark(asset: BrandIdentity.channel(row["channelType"].string), name: row["channelName"].string, size: 28)
                VStack(alignment: .leading, spacing: 5) {
                    Text(row["channelName"].string.isEmpty ? obsText("未命名渠道") : row["channelName"].string)
                        .font(.headline).lineLimit(2)
                    HStack(spacing: 8) {
                        Text(NativeAdminLabels.value(row["channelType"].string)).foregroundStyle(.secondary)
                        if row["channelDisabled"].bool { Label("已禁用", systemImage: "pause.circle").foregroundStyle(.orange) }
                    }.font(.caption)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(stats.percentage).font(.title3.weight(.semibold)).foregroundStyle(tint).monospacedDigit()
                    Text(stats.rate == nil ? "暂无样本" : "成功率").font(.caption2).foregroundStyle(.secondary)
                }
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(stats.total > 0 ? Color.orange.opacity(0.8) : Color.secondary.opacity(0.12))
                    if let rate = stats.rate, rate > 0 {
                        Capsule().fill(Color.green).frame(width: geometry.size.width * rate / 100)
                    }
                }
            }.frame(height: 8).accessibilityHidden(true)
            HStack(spacing: 16) {
                Label(ManagementFormat.number(.number(stats.success)), systemImage: "checkmark.circle").foregroundStyle(.green)
                Label(ManagementFormat.number(.number(stats.failed)), systemImage: "exclamationmark.circle").foregroundStyle(stats.failed > 0 ? Color.orange : .secondary)
                Spacer(minLength: 0)
                Text(obsText("样本") + " " + ManagementFormat.number(.number(stats.total))).foregroundStyle(.secondary)
            }.font(.caption).monospacedDigit()
        }.padding(.vertical, 8)
    }
}

struct ChannelHealthSummary: View {
    let rows: [JSON]
    private var stats: ChannelHealthStatistics { ChannelHealthStatistics(rows: rows) }
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("执行成功率").font(.caption).foregroundStyle(.secondary)
                Text(stats.percentage).font(.largeTitle.weight(.semibold)).monospacedDigit()
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(obsText("成功") + " " + ManagementFormat.number(.number(stats.success))).foregroundStyle(.green)
                Text(obsText("失败") + " " + ManagementFormat.number(.number(stats.failed))).foregroundStyle(stats.failed > 0 ? Color.orange : .secondary)
                Text(obsText("渠道") + " " + String(rows.count)).foregroundStyle(.secondary)
            }.font(.caption).monospacedDigit()
        }
        .accessibilityHint("按渠道执行次数加权；重试可能产生多次执行，不等于客户端请求成功率。")
    }
}
