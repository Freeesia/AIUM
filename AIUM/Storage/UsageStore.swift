import Foundation
import WidgetKit

/// Persists and retrieves UsageSnapshots so that both the app and widgets
/// can share the latest cached data without performing network calls.
///
/// Uses an App Group container JSON file so the widget extension can read
/// the same data as the main app.
///
@MainActor
final class UsageStore: ObservableObject {
    // MARK: - Singleton

    static let shared = UsageStore()

    // MARK: - Configuration

    /// The App Group identifier shared between the app and the widget extension.
    /// This must match both entitlement files:
    /// - AIUM/AIUM.entitlements
    /// - AIUMWidget/AIUMWidget.entitlements
    nonisolated static let appGroupIdentifier = "group.com.studiofreesia.aium"

    private nonisolated static let snapshotsFilename = "usage_snapshots.json"

    /// Whether the configured App Group container is available at runtime.
    ///
    /// When this is false the app falls back to its own Documents directory,
    /// which is intentionally not visible to the widget extension.
    nonisolated static var isSharedContainerAvailable: Bool {
        sharedContainerURL() != nil
    }

    // MARK: - Published state

    @Published private(set) var snapshots: [UsageSnapshot] = []

    // MARK: - Private

    private let storeURL: URL?
    private let reloadWidgetTimelines: () -> Void

    private init() {
        if let sharedStoreURL = Self.sharedStoreURL() {
            storeURL = sharedStoreURL
        } else {
            // Fall back to app's Documents directory (widget won't see this).
            storeURL = Self.documentsStoreURL()
        }
        reloadWidgetTimelines = { WidgetCenter.shared.reloadAllTimelines() }
        load()
    }

    /// Creates an isolated store for unit tests without touching the App Group
    /// container or spending the widget reload budget.
    init(testingStoreURL: URL) {
        storeURL = testingStoreURL
        reloadWidgetTimelines = {}
        load()
    }

    // MARK: - Public API

    /// Saves or replaces the snapshot for the given provider+plan combination.
    func upsert(_ snapshot: UsageSnapshot) {
        if let idx = snapshots.firstIndex(where: { $0.id == snapshot.id }) {
            snapshots[idx] = snapshot
        } else {
            snapshots.append(snapshot)
        }
        persist()
    }

    /// Returns the latest snapshot for a provider, if any.
    func snapshot(for provider: Provider) -> UsageSnapshot? {
        snapshots.first { $0.provider == provider }
    }

    /// Returns all snapshots for a provider.
    func snapshots(for provider: Provider) -> [UsageSnapshot] {
        snapshots.filter { $0.provider == provider }
    }

    /// Replaces all cached snapshots for one provider.
    func replace(provider: Provider, with newSnapshots: [UsageSnapshot]) {
        snapshots.removeAll { $0.provider == provider }
        snapshots.append(contentsOf: newSnapshots)
        persist()
    }

    /// Clears cached snapshots for a provider (e.g. on logout).
    func clear(provider: Provider) {
        snapshots.removeAll { $0.provider == provider }
        persist()
    }

    // MARK: - Persistence

    private func load() {
        guard let url = storeURL,
              let data = try? Data(contentsOf: url)
        else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let loaded = try? decoder.decode([UsageSnapshot].self, from: data) {
            snapshots = loaded
        }
    }

    private func persist() {
        guard let url = storeURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(snapshots) {
            do {
                try data.write(to: url, options: .atomicWrite)
                reloadWidgetTimelines()
            } catch {
                // Persist failures are intentionally ignored for now so usage
                // refreshes do not break the dashboard UI.
            }
        }
    }
}

// MARK: - Widget read-only access

extension UsageStore {
    nonisolated static func sharedContainerURL() -> URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        )
    }

    private nonisolated static func sharedStoreURL() -> URL? {
        sharedContainerURL()?.appendingPathComponent(snapshotsFilename)
    }

    private nonisolated static func documentsStoreURL() -> URL? {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(snapshotsFilename)
    }

    /// Loads snapshots directly from the shared container without needing a
    /// live `UsageStore` instance. Intended for use by the widget extension's
    /// timeline provider.
    /// This method is nonisolated so it can be called from any context, including
    /// WidgetKit's TimelineProvider callbacks.
    nonisolated static func loadSnapshotsFromSharedContainer() -> [UsageSnapshot] {
        guard let url = sharedStoreURL() else { return [] }
        guard let data = try? Data(contentsOf: url) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([UsageSnapshot].self, from: data)) ?? []
    }
}
