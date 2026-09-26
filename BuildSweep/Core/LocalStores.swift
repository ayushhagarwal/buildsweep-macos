import Foundation

actor CleanupHistoryStore {
    private let defaults: UserDefaults
    private let key = "cleanupHistory.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [CleanupSessionResult] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([CleanupSessionResult].self, from: data)) ?? []
    }

    func append(_ result: CleanupSessionResult) {
        var history = load()
        history.insert(result, at: 0)
        history = Array(history.prefix(100))
        defaults.set(try? JSONEncoder().encode(history), forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}

actor ScanCacheStore {
    private let defaults: UserDefaults
    private let key = "lastScanSnapshot.v2"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(maximumAge: TimeInterval? = nil, now: Date = .now) -> ScanSnapshot? {
        guard let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(ScanSnapshot.self, from: data),
              let completed = snapshot.completedAt else { return nil }
        if let maximumAge, now.timeIntervalSince(completed) > maximumAge { return nil }
        return snapshot
    }

    func save(_ snapshot: ScanSnapshot) {
        defaults.set(try? JSONEncoder().encode(snapshot), forKey: key)
    }
}
