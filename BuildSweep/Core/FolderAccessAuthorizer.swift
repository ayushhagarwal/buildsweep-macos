import AppKit
import Foundation

enum FolderAuthorizationError: LocalizedError {
    case cancelled
    case wrongDeveloperFolder
    case wrongCacheFolder
    case wrongFolder(String)
    case bookmarkFailed

    var errorDescription: String? {
        switch self {
        case .cancelled: "Folder selection was cancelled."
        case .wrongDeveloperFolder: "Choose your Library/Developer folder, not your home or entire Library folder."
        case .wrongCacheFolder: "Choose Library/Caches/com.apple.dt.Xcode exactly."
        case .wrongFolder(let message): message
        case .bookmarkFailed: "BuildSweep could not preserve access to that folder."
        }
    }
}

@MainActor
final class FolderAccessAuthorizer: AccessAuthorizing {
    private let defaults: UserDefaults
    private let storageKey = "authorizedRoots.v1"
    private var activeURLs: [UUID: URL] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func requestDeveloperDirectory() async throws -> AuthorizedRoot {
        try await requestAuthorizedFolder(kind: .developerDirectory, preferring: RealUserHome.developerDirectory)
    }

    func requestXcodeCacheDirectory() async throws -> AuthorizedRoot {
        try await requestAuthorizedFolder(kind: .xcodeCache, preferring: RealUserHome.xcodeCacheDirectory)
    }

    func requestAuthorizedFolder(kind: AuthorizedRootKind, preferring expected: URL? = nil) async throws -> AuthorizedRoot {
        let initial = expected ?? kind.expectedFolders[0]
        let url = try await chooseDirectory(prompt: kind.panelPrompt, initialDirectory: initial)
        guard isExpectedFolder(url, kind: kind) else {
            throw authorizationError(for: kind)
        }
        if let expected, !isSameFolder(url, expected) {
            throw authorizationError(for: kind)
        }
        return try save(url: url, kind: kind)
    }

    func restoreAuthorizedRoots() async -> [AuthorizedRoot] {
        let stored = loadStoredRoots()
        var restored: [AuthorizedRoot] = []
        for root in stored {
            var stale = false
            guard let url = try? URL(
                resolvingBookmarkData: root.bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) else { continue }
            guard validate(url: url, kind: root.kind), url.startAccessingSecurityScopedResource() else { continue }
            activeURLs[root.id] = url
            if stale, let refreshed = try? makeBookmark(for: url) {
                restored.append(AuthorizedRoot(id: root.id, kind: root.kind, url: url, bookmark: refreshed, grantedAt: root.grantedAt))
            } else {
                restored.append(AuthorizedRoot(id: root.id, kind: root.kind, url: url, bookmark: root.bookmark, grantedAt: root.grantedAt))
            }
        }
        persist(restored)
        return restored
    }

    func forget(_ root: AuthorizedRoot) async {
        if let url = activeURLs.removeValue(forKey: root.id) {
            url.stopAccessingSecurityScopedResource()
        }
        persist(loadStoredRoots().filter { $0.id != root.id })
    }

    func releaseAllAccess() {
        for url in activeURLs.values { url.stopAccessingSecurityScopedResource() }
        activeURLs.removeAll()
    }

    private func chooseDirectory(prompt: String, initialDirectory: URL) async throws -> URL {
        let panel = NSOpenPanel()
        panel.title = prompt
        panel.prompt = "Grant Access"
        panel.message = "BuildSweep scans folder metadata locally and never reads source file contents."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = initialDirectory
        let response = await panel.begin()
        guard response == .OK, let url = panel.url else { throw FolderAuthorizationError.cancelled }
        return url.standardizedFileURL
    }

    private func save(url: URL, kind: AuthorizedRootKind) throws -> AuthorizedRoot {
        guard validate(url: url, kind: kind) else {
            throw authorizationError(for: kind)
        }
        let root = AuthorizedRoot(id: UUID(), kind: kind, url: url, bookmark: try makeBookmark(for: url), grantedAt: .now)
        guard url.startAccessingSecurityScopedResource() else { throw FolderAuthorizationError.bookmarkFailed }
        activeURLs[root.id] = url
        let storedRoots = loadStoredRoots()
        let incomingKey = identityKey(url, kind: kind)
        for oldRoot in storedRoots where oldRoot.kind == kind && identityKey(oldRoot.url, kind: kind) == incomingKey {
            if let oldURL = activeURLs.removeValue(forKey: oldRoot.id) {
                oldURL.stopAccessingSecurityScopedResource()
            }
        }
        var roots = storedRoots.filter { $0.kind != kind || identityKey($0.url, kind: kind) != incomingKey }
        roots.append(root)
        persist(roots)
        return root
    }

    private func validate(url: URL, kind: AuthorizedRootKind) -> Bool {
        isExpectedFolder(url, kind: kind)
    }

    private func isExpectedFolder(_ url: URL, kind: AuthorizedRootKind) -> Bool {
        kind.expectedFolders.contains { isSameFolder(url, $0) }
    }

    private func isSameFolder(_ url: URL, _ expected: URL) -> Bool {
        if url.standardizedFileURL.path == expected.standardizedFileURL.path { return true }
        if url.canonicalFileURL.path == expected.canonicalFileURL.path { return true }
        let selectedID = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
        let expectedID = try? expected.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
        if let selectedID, let expectedID { return selectedID.isEqual(expectedID) }
        return false
    }

    private func identityKey(_ url: URL, kind: AuthorizedRootKind) -> String {
        if let match = kind.expectedFolders.first(where: { isSameFolder(url, $0) }) {
            return match.standardizedFileURL.path
        }
        return url.standardizedFileURL.path
    }

    private func authorizationError(for kind: AuthorizedRootKind) -> FolderAuthorizationError {
        switch kind {
        case .developerDirectory: .wrongDeveloperFolder
        case .xcodeCache: .wrongCacheFolder
        default: .wrongFolder(kind.wrongFolderMessage)
        }
    }

    private func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    private func loadStoredRoots() -> [AuthorizedRoot] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([AuthorizedRoot].self, from: data)) ?? []
    }

    private func persist(_ roots: [AuthorizedRoot]) {
        defaults.set(try? JSONEncoder().encode(roots), forKey: storageKey)
    }
}
