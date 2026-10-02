import SwiftUI

struct ManagementInstanceControls: View {
    @ObservedObject var store: AxonStore
    @State private var adding = false
    @State private var editing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "server.rack").font(.title2).foregroundStyle(Color.accentColor)
                    .frame(width: 36, height: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.selectedInstance?.name ?? "AxonHub").font(.headline)
                    Text(store.selectedInstance?.address ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                if store.loading { ProgressView() }

            }
            Picker("当前实例", selection: $store.selectedID) {
                ForEach(store.instances) { instance in Text(instance.name).tag(instance.id) }
            }.disabled(store.managementBusy || store.loading)
            if let error = store.error { ObservabilityErrorView(message: error) }

        }.symbolVariant(.fill).padding(18).neutralCard()
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button { Task { await store.refresh() } } label: { Label("重新连接", systemImage: "arrow.clockwise") }
                .tint(Color(.darkGray)).disabled(store.loading || store.managementBusy)
            Button { editing = true } label: { Label("编辑连接", systemImage: "pencil") }
                .tint(Color(.systemGray)).disabled(store.selectedInstance == nil || store.managementBusy)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button { adding = true } label: { Label("新增实例", systemImage: "plus") }
                .tint(Color(.systemGray)).disabled(store.managementBusy)
        }
        .contextMenu {
            Button { Task { await store.refresh() } } label: { Label("重新连接", systemImage: "arrow.clockwise") }
                .disabled(store.loading || store.managementBusy)
            Button { editing = true } label: { Label("编辑连接", systemImage: "pencil") }
                .disabled(store.selectedInstance == nil || store.managementBusy)
            Button { adding = true } label: { Label("新增实例", systemImage: "plus") }
                .disabled(store.managementBusy)
        }
        .sheet(isPresented: $adding) { AddInstanceSheet(store: store) }
        .sheet(isPresented: $editing) { if let instance = store.selectedInstance { AddInstanceSheet(store: store, instance: instance) } }

    }
}
