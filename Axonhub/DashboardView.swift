import SwiftUI

struct StatCardView: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color
    @ScaledMetric(relativeTo: .body) private var cardHeight: CGFloat = 116

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2, reservesSpace: true)
                Spacer()
                Image(systemName: icon).symbolVariant(.fill)
                    .foregroundStyle(tint)
                    .font(.body)
            }

            Text(value)
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: cardHeight, alignment: .topLeading)
        .neutralCard()
    }
}

/// Unified Dashboard / Overview tab supporting switching between Dashboard, Analytics, and Audit Logs
struct DashboardView: View {
    @ObservedObject var store: AxonStore
    @State private var viewMode: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $viewMode) {
                Text(NSLocalizedString("网关概览", comment: "")).tag(0)
                Text(NSLocalizedString("多维用量", comment: "")).tag(1)
                Text(NSLocalizedString("请求审计", comment: "")).tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)

            Group {
                if viewMode == 0 {
                    ObservabilityDashboardView(store: store)
                } else if viewMode == 1 {
                    ObservabilityAnalyticsView(store: store)
                } else {
                    ObservabilityCenterView(store: store)
                }
            }
            .id(store.selectedInstance)
        }
        .navigationTitle(NSLocalizedString("监控与概览", comment: ""))
    }
}
