import SwiftUI

struct RequestRowView: View {
    let req: RequestLogItem

    var statusColor: Color {
        if req.isSuccess { return .green }
        return .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(req.modelID)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }

                Spacer()

                Text(NativeDisplay.date(req.createdAt))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                if let latency = req.latencyMs {
                    Label(String(format: "%lld ms", Int64(latency)), systemImage: "clock")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if let ttft = req.firstTokenLatencyMs {
                    Label(String(format: "TTFT: %lld ms", Int64(ttft)), systemImage: "bolt")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if req.stream {
                    Text("STREAM")
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.12))
                        .foregroundColor(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            HStack {
                Text(req.clientIP)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text(req.userAgent)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            if let err = req.errorMessage, !err.isEmpty {
                Text(err)
                    .font(.caption2)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .liquidGlass()
    }
}

struct RequestsListView: View {
    @ObservedObject var store: AxonStore
    var body: some View { ObservabilityCenterView(store: store) }
}
