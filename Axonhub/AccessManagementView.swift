import SwiftUI

enum AccessSubTab: String, CaseIterable, Identifiable {
    case apiKeys = "apiKeys"
    case rules = "rules"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apiKeys: return NSLocalizedString("API 密钥", comment: "")
        case .rules: return NSLocalizedString("提示词防护", comment: "")
        }
    }
}

/// Unified Access Management Tab (API Keys + Prompt Protection Rules)
struct AccessManagementView: View {
    @ObservedObject var store: AxonStore
    @State private var selectedTab: AccessSubTab = .apiKeys

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(AccessSubTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)

            Group {
                if selectedTab == .apiKeys {
                    APIKeysListView(store: store)
                } else {
                    PromptProtectionRulesView(store: store)
                }
            }
        }
        .navigationTitle(NSLocalizedString("访问与安全", comment: ""))
    }
}
