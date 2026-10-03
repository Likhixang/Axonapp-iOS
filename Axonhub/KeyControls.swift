import SwiftUI

/// One-row controls shared by channel keys and API keys.
struct KeyEditorField: View {
    let title: String
    @Binding var text: String
    var onRemove: (() -> Void)? = nil
    @State private var visible = false
    @State private var copied = false

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                if visible {
                    TextField(title, text: $text, axis: .vertical)
                        .font(.body.monospaced()).lineLimit(1...6)
                        .accessibilityLabel(title)
                } else {
                    SecureField(title, text: $text).font(.body.monospaced())
                        .accessibilityLabel(title)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button { visible.toggle() } label: {
                Image(systemName: visible ? "eye.slash" : "eye").frame(width: 44, height: 44)
            }.accessibilityLabel(obsText(visible ? "隐藏" : "显示") + " " + title)
            Button { NativeSecretClipboard.copy(text); copied = true } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc").frame(width: 44, height: 44)
            }.disabled(text.isEmpty).accessibilityLabel(obsText(copied ? "已复制" : "复制") + " " + title)
            if let onRemove = onRemove {
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "minus.circle").frame(width: 44, height: 44)
                }.accessibilityLabel(obsText("移除") + " " + title)
            }
        }.buttonStyle(.borderless)
        .textInputAutocapitalization(.never).autocorrectionDisabled()
        .onChange(of: text) { _ in copied = false }
        .onDisappear { visible = false; copied = false }
        .padding(.vertical, 3)
    }
}

struct APIKeyValueRow: View {
    var initialValue = ""
    var maskedValue = "••••••••"
    var initiallyVisible = false
    let read: () async throws -> String
    @State private var key = ""
    @State private var visible = false
    @State private var busy = false
    @State private var copied = false
    @State private var failure: String?
    @State private var generation = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 4) {
                Text(visible ? key : maskedValue)
                    .font(.body.monospaced()).textSelection(.enabled)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                if busy { ProgressView().frame(width: 44, height: 44) }
                else {
                    Button {
                        if visible { visible = false; key = "" }
                        else { Task { await obtain(copy: false) } }
                    } label: {
                        Image(systemName: visible ? "eye.slash" : "eye").frame(width: 44, height: 44)
                    }.accessibilityLabel(obsText(visible ? "隐藏" : "显示"))
                }
                Button { Task { await obtain(copy: true) } } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc").frame(width: 44, height: 44)
                }.disabled(busy).accessibilityLabel(obsText(copied ? "已复制" : "复制"))
            }.buttonStyle(.borderless)
            if let failure = failure { Text(failure).font(.caption).foregroundStyle(.red) }
        }
        .onAppear { visible = initiallyVisible; key = initiallyVisible ? initialValue : "" }
        .onDisappear { generation = UUID(); key = ""; visible = false; copied = false; busy = false }
    }
    @MainActor private func obtain(copy: Bool) async {
        guard !busy else { return }
        let ticket = generation
        busy = true; failure = nil
        defer { if generation == ticket { busy = false } }
        do {
            let value = !key.isEmpty ? key : !initialValue.isEmpty ? initialValue : try await read()
            try Task.checkCancellation()
            guard generation == ticket else { return }
            guard !value.isEmpty else { throw AdminError.notFound }
            if copy { NativeSecretClipboard.copy(value); copied = true }
            else { key = value; visible = true }
        } catch {
            if generation == ticket && !(error is CancellationError) { failure = error.localizedDescription }
        }
    }
}
