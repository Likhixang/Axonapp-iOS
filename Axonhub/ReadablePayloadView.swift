import SwiftUI

/// Sanitized data only; translation never changes the stored or exported JSON.
struct ReadablePayloadView: View {
    let value: JSON
    var key = ""
    var depth = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if depth >= 16 {
                Text(obsText("内容层级较深，请展开原始 JSON 查看。"))
            } else {
                switch value {
                case .object(let fields):
                    ForEach(fields.keys.sorted(), id: \.self) { field in
                        if let item = fields[field] {
                            if case .object = item {
                                DisclosureGroup(NativeAdminLabels.field(field)) {
                                    AnyView(ReadablePayloadView(value: item, key: field, depth: depth + 1))
                                }
                            } else if case .array = item {
                                DisclosureGroup(NativeAdminLabels.field(field)) {
                                    AnyView(ReadablePayloadView(value: item, key: field, depth: depth + 1))
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(NativeAdminLabels.field(field)).font(.caption).foregroundStyle(.secondary)
                                    if NativeAdminLabels.fields[field] == nil {
                                        Text(field).font(.caption.monospaced()).foregroundStyle(.secondary)
                                    }
                                    Text(NativeAdminLabels.scalar(item, key: field)).textSelection(.enabled)
                                }
                            }
                        }
                    }
                case .array(let items):
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        if case .object = item {
                            DisclosureGroup(String(format: obsText("第 %lld 项"), Int64(index + 1))) {
                                AnyView(ReadablePayloadView(value: item, key: key, depth: depth + 1))
                            }
                        } else if case .array = item {
                            AnyView(ReadablePayloadView(value: item, key: key, depth: depth + 1))
                        } else { Text(NativeAdminLabels.scalar(item, key: key)).textSelection(.enabled) }
                    }
                    if items.isEmpty { Text(obsText("空列表")).foregroundStyle(.secondary) }
                default: Text(NativeAdminLabels.scalar(value, key: key)).textSelection(.enabled)
                }
            }
        }.font(.subheadline)
    }
}
