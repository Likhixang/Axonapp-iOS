import SwiftUI
import UIKit

// MARK: - Theme

enum Theme {
    static let accent = Color("AccentColor")
    static let success = Color.green
    static let warning = Color.orange
    static let danger = Color.red
    static let cardRadius: CGFloat = 16

    static func color(for status: RequestStatus) -> Color {
        switch status {
        case .completed: return success
        case .failed: return danger
        case .canceled: return .secondary
        case .processing: return .blue
        case .pending: return warning
        }
    }

    static func color(for status: ResourceStatus) -> Color {
        switch status {
        case .enabled: return success
        case .disabled: return warning
        case .archived: return .secondary
        }
    }
}

// MARK: - Loading state

enum Loadable<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(String)

    var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

/// Generic cursor-paginated list loader used by every list screen.
@MainActor
@Observable
final class PagedLoader<Item: Identifiable & Sendable> {
    typealias Fetch = (_ cursor: String?) async throws -> Page<Item>

    private(set) var items: [Item] = []
    private(set) var totalCount: Int?
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var error: String?
    private(set) var hasLoaded = false
    private var cursor: String?
    private var hasMore = false
    private var generation = 0

    var fetch: Fetch?

    func reload() async {
        guard let fetch else { return }
        generation += 1
        let current = generation
        isLoading = true
        error = nil
        defer { if current == generation { isLoading = false } }
        do {
            let page = try await fetch(nil)
            guard current == generation else { return }
            items = page.items
            cursor = page.cursor
            hasMore = page.hasMore
            totalCount = page.totalCount
            hasLoaded = true
        } catch is CancellationError {
        } catch {
            guard current == generation else { return }
            if (error as? URLError)?.code == .cancelled { return }
            self.error = error.localizedDescription
            hasLoaded = true
        }
    }

    func loadMoreIfNeeded(current item: Item) async {
        guard hasMore, !isLoadingMore, !isLoading, let fetch,
              let index = items.firstIndex(where: { $0.id == item.id }),
              index >= items.count - 5 else { return }
        isLoadingMore = true
        let current = generation
        defer { isLoadingMore = false }
        do {
            let page = try await fetch(cursor)
            guard current == generation else { return }
            let known = Set(items.map(\.id))
            items.append(contentsOf: page.items.filter { !known.contains($0.id) })
            cursor = page.cursor
            hasMore = page.hasMore
        } catch {
            hasMore = false
        }
    }

    func replace(_ item: Item) {
        if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = item }
    }

    func remove(id: Item.ID) {
        items.removeAll { $0.id == id }
        if let totalCount { self.totalCount = max(totalCount - 1, 0) }
    }

    func prepend(_ item: Item) {
        items.insert(item, at: 0)
        if let totalCount { self.totalCount = totalCount + 1 }
    }
}

// MARK: - Reusable views

struct StatusBadge: View {
    let text: String
    let color: Color

    init(_ text: String, color: Color) {
        self.text = text
        self.color = color
    }

    init(_ status: ResourceStatus) {
        self.init(status.label, color: Theme.color(for: status))
    }

    init(_ status: RequestStatus) {
        self.init(status.label, color: Theme.color(for: status))
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: Capsule())
    }
}

struct StatusDot: View {
    let color: Color
    var body: some View {
        Circle().fill(color).frame(width: 8, height: 8)
    }
}

struct Tag: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption2.monospaced())
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 5))
    }
}

struct Card<Content: View>: View {
    var title: String?
    var systemImage: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Label {
                    Text(title).font(.subheadline.weight(.semibold))
                } icon: {
                    if let systemImage { Image(systemName: systemImage).foregroundStyle(Theme.accent) }
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    var caption: String?
    var systemImage: String
    var tint: Color = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 22, height: 22)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            if let caption {
                Text(caption).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

struct KeyValueRow: View {
    let key: String
    let value: String
    var monospaced = false
    var copyable = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(key).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(monospaced ? .callout.monospaced() : .callout)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .contextMenu {
            if copyable || monospaced {
                Button("拷贝", systemImage: "doc.on.doc") { Clipboard.copy(value) }
            }
        }
    }
}

struct ErrorStateView: View {
    let message: String
    var retry: (() async -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label("加载失败", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            if let retry {
                Button("重试") { Task { await retry() } }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

struct LoadMoreFooter: View {
    let isLoading: Bool
    var body: some View {
        if isLoading {
            HStack { Spacer(); ProgressView(); Spacer() }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
    }
}

/// Overlay used by list screens for the first load / empty / error states.
struct ListStateOverlay<Item: Identifiable & Sendable>: View {
    let loader: PagedLoader<Item>
    let emptyTitle: String
    let emptyImage: String
    var emptyMessage: String?

    var body: some View {
        if loader.items.isEmpty {
            if loader.isLoading && !loader.hasLoaded {
                ProgressView()
            } else if let error = loader.error {
                ErrorStateView(message: error) { await loader.reload() }
            } else if loader.hasLoaded {
                ContentUnavailableView(emptyTitle, systemImage: emptyImage, description: emptyMessage.map { Text($0) })
            }
        }
    }
}

enum Clipboard {
    static func copy(_ text: String) {
        UIPasteboard.general.string = text
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

/// Small toast shown at the bottom of a screen.
struct Toast: Equatable {
    var message: String
    var isError = false
}

struct ToastModifier: ViewModifier {
    @Binding var toast: Toast?

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let toast {
                Label(toast.message, systemImage: toast.isError ? "xmark.octagon.fill" : "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(toast.isError ? Theme.danger : Theme.success)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                    .padding(.bottom, 24)
                    .padding(.horizontal)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: toast) {
                        try? await Task.sleep(for: .seconds(toast.isError ? 4 : 2))
                        withAnimation { self.toast = nil }
                    }
                    .onTapGesture { withAnimation { self.toast = nil } }
            }
        }
        .animation(.spring(duration: 0.35), value: toast)
    }
}

extension View {
    func toast(_ toast: Binding<Toast?>) -> some View { modifier(ToastModifier(toast: toast)) }
}

struct ProviderIcon: View {
    let provider: ChannelProvider
    var size: CGFloat = 34

    private var tint: Color {
        switch provider.format {
        case .openai: return .teal
        case .responses: return .mint
        case .anthropic: return .orange
        case .gemini: return .blue
        case .other: return .gray
        }
    }

    var body: some View {
        Text(String(provider.name.prefix(1)).uppercased())
            .font(.system(size: size * 0.45, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}
