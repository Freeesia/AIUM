import Foundation

/// Persists and retrieves UsageSnapshots so that both the app and widgets
/// can share the latest cached data without performing network calls.
///
/// Uses an App Group container JSON file so the widget extension can read
/// the same data as the main app.
///
/// Replace `appGroupIdentifier` with your real App Group ID (e.g. "group.io.github.freeesia.aium").
@MainActor
final class UsageStore: ObservableObject {
    // MARK: - Singleton

    static let shared = UsageStore()

    // MARK: - Configuration

    /// The App Group identifier shared between the app and the widget extension.
    /// Set this to your real App Group ID.
    static let appGroupIdentifier = "group.io.github.freeesia.aium"

    // MARK: - Published state

    @Published private(set) var snapshots: [UsageSnapshot] = []

    // MARK: - Private

    private let storeURL: URL?

    private init() {
        if let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier
        ) {
            storeURL = container.appendingPathComponent("usage_snapshots.json")
        } else {
            // Fall back to app's Documents directory (widget won't see this).
            storeURL = FileManager.default
                .urls(for: .documentDirectory, in: .userDomainMask)
                .first?
                .appendingPathComponent("usage_snapshots.json")
        }
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
            try? data.write(to: url, options: .atomicWrite)
        }
    }
}

// MARK: - Widget read-only access

extension UsageStore {
    /// Loads snapshots directly from the shared container without needing a
    /// live `UsageStore` instance. Intended for use by the widget extension's
    /// timeline provider.
    static func loadSnapshotsFromSharedContainer() -> [UsageSnapshot] {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else { return [] }

        let url = container.appendingPathComponent("usage_snapshots.json")
        guard let data = try? Data(contentsOf: url) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([UsageSnapshot].self, from: data)) ?? []
    }
}
