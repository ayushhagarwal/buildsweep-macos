import Foundation
import Security

enum FreeCleanupPolicy {
    static let limit = 3
}

protocol FreeCleanupAccounting: Sendable {
    func usedCount() async -> Int
    func recordUse() async throws
}

actor KeychainFreeCleanupStore: FreeCleanupAccounting {
    static let service = "com.ayush.buildsweep.free-cleanup"
    private let account = "first-successful-cleanup"

    func usedCount() -> Int {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { return 0 }
        if value == "consumed" { return 1 }
        return Int(value) ?? 0
    }

    func recordUse() throws {
        let next = usedCount() + 1
        let data = Data(String(next).utf8)
        var add = baseQuery
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            guard updateStatus == errSecSuccess else { throw KeychainError.status(updateStatus) }
        } else if status != errSecSuccess {
            throw KeychainError.status(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account
        ]
    }
}

enum KeychainError: LocalizedError {
    case status(OSStatus)

    var errorDescription: String? {
        switch self {
        case .status(let status): "Keychain operation failed (\(status))."
        }
    }
}

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
    private let key = "lastScanSnapshot.v1"

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

struct ReviewPromptPolicy {
    struct State: Codable, Equatable {
        var launches = 0
        var successfulCleanups = 0
        var recoveredBytes: Int64 = 0
        var lastAttemptDate: Date?
        var attemptedVersion: String?
    }

    static let minimumLaunches = 3
    static let minimumCleanups = 2
    static let minimumRecoveredBytes: Int64 = 1_000_000_000
    static let cooldown: TimeInterval = 150 * 24 * 60 * 60

    static func isEligible(
        state: State,
        version: String,
        now: Date = .now,
        adjacentPaywall: Bool = false
    ) -> Bool {
        guard !adjacentPaywall else { return false }
        guard state.launches >= minimumLaunches,
              state.successfulCleanups >= minimumCleanups,
              state.recoveredBytes >= minimumRecoveredBytes,
              state.attemptedVersion != version else { return false }
        if let last = state.lastAttemptDate, now.timeIntervalSince(last) < cooldown { return false }
        return true
    }
}

@MainActor
final class ReviewMetricsStore {
    private let defaults: UserDefaults
    private let key = "reviewPromptState.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var state: ReviewPromptPolicy.State {
        get {
            guard let data = defaults.data(forKey: key) else { return .init() }
            return (try? JSONDecoder().decode(ReviewPromptPolicy.State.self, from: data)) ?? .init()
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: key) }
    }

    func recordLaunch() {
        var value = state
        value.launches += 1
        state = value
    }

    func recordSuccessfulCleanup(bytes: Int64) {
        var value = state
        value.successfulCleanups += 1
        value.recoveredBytes += bytes
        state = value
    }

    func recordAttempt(version: String, date: Date = .now) {
        var value = state
        value.attemptedVersion = version
        value.lastAttemptDate = date
        state = value
    }
}
