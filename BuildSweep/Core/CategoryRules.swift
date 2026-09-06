import Foundation

enum CleanupPolicyError: LocalizedError, Equatable {
    case noSelection
    case itemMissing(String)
    case inspectionOnly(String)
    case missingURL(String)
    case forbiddenRoot(String)
    case outsideAuthorizedRoot(String)
    case symlink(String)
    case ruleMismatch(String)
    case sourcePath(String)

    var errorDescription: String? {
        switch self {
        case .noSelection: "Choose at least one supported item."
        case .itemMissing(let value): "The item no longer exists in this scan: \(value)"
        case .inspectionOnly(let value): "\(value) is inspection-only."
        case .missingURL(let value): "\(value) has no local cleanup URL."
        case .forbiddenRoot(let value): "BuildSweep will never delete a broad folder: \(value)"
        case .outsideAuthorizedRoot(let value): "The item escaped its authorized folder: \(value)"
        case .symlink(let value): "Symbolic-link cleanup is blocked: \(value)"
        case .ruleMismatch(let value): "The item no longer matches a known storage rule: \(value)"
        case .sourcePath(let value): "Source and project paths are always blocked: \(value)"
        }
    }
}

struct CleanupPathPolicy: Sendable {
    private let forbiddenExtensions: Set<String> = ["xcodeproj", "xcworkspace", "git"]
    private let forbiddenNames: Set<String> = [
        "UserData", "Provisioning Profiles", "Accounts", "Xcode Cloud", "Products"
    ]

    func validate(_ item: StorageItem, inside root: URL, fileManager: FileManager = .default) throws -> URL {
        guard let rawURL = item.url else { throw CleanupPolicyError.missingURL(item.displayName) }
        let rootURL = root.canonicalFileURL
        let candidate = rawURL.canonicalFileURL

        guard !isForbiddenBroadRoot(candidate) else {
            throw CleanupPolicyError.forbiddenRoot(candidate.path)
        }
        guard candidate.isDescendant(of: rootURL) || isAllowedExactRoot(item, candidate: candidate, root: rootURL) else {
            throw CleanupPolicyError.outsideAuthorizedRoot(candidate.path)
        }

        let values = try rawURL.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values.isSymbolicLink != true else { throw CleanupPolicyError.symlink(rawURL.path) }

        let components = candidate.pathComponents
        if components.contains(where: forbiddenNames.contains) || forbiddenExtensions.contains(candidate.pathExtension.lowercased()) {
            throw CleanupPolicyError.sourcePath(candidate.path)
        }
        if components.contains(where: { $0 == ".git" || $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }) {
            throw CleanupPolicyError.sourcePath(candidate.path)
        }
        if isAIKind(item.kind), components.contains(where: AIToolAllowlist.forbiddenNames.contains) {
            throw CleanupPolicyError.ruleMismatch(candidate.path)
        }
        guard matchesRule(item, candidate: candidate, root: rootURL) else {
            throw CleanupPolicyError.ruleMismatch(candidate.path)
        }
        guard fileManager.fileExists(atPath: candidate.path) else {
            throw CleanupPolicyError.itemMissing(item.displayName)
        }
        return candidate
    }

    private func isForbiddenBroadRoot(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let home = RealUserHome.directory.path
        let broad = [
            "/",
            home,
            "\(home)/Library",
            "\(home)/Library/Developer",
            "\(home)/Library/Caches",
            "\(home)/Library/Application Support",
            RealUserHome.cursorSupportDirectory.path,
            RealUserHome.cursorHomeDirectory.path,
            RealUserHome.codexHomeDirectory.path,
            RealUserHome.claudeHomeDirectory.path,
            RealUserHome.claudeSupportDirectory.path
        ]
        return broad.contains(path)
    }

    private func isAIKind(_ kind: StorageItemKind) -> Bool {
        kind == .cursorCache || kind == .codexCache || kind == .claudeCache
    }

    private func isAllowedExactRoot(_ item: StorageItem, candidate: URL, root: URL) -> Bool {
        guard candidate == root else { return false }
        switch item.kind {
        case .codexCache, .claudeCache:
            return AIToolAllowlist.systemCacheFolderNames.contains(root.lastPathComponent)
        default:
            return false
        }
    }

    private func isExactAllowlistedChild(_ relative: String, names: Set<String>) -> Bool {
        !relative.contains("/") && names.contains(relative)
    }

    private func matchesRule(_ item: StorageItem, candidate: URL, root: URL) -> Bool {
        let relative = candidate.path.replacingOccurrences(of: root.path + "/", with: "")
        switch item.kind {
        case .derivedData:
            let parts = relative.split(separator: "/")
            return parts.count == 3 && parts[0] == "Xcode" && parts[1] == "DerivedData"
        case .archive:
            return relative.hasPrefix("Xcode/Archives/") && candidate.pathExtension == "xcarchive"
        case .compilerCache:
            let allowed = ["ModuleCache.noindex", "SDKStatCaches.noindex", "CompilationCache.noindex", "SymbolCache.noindex"]
            return relative.hasPrefix("Xcode/DerivedData/") && allowed.contains(candidate.lastPathComponent)
        case .deviceSupport:
            let allowedRoots = [
                "Xcode/iOS DeviceSupport/", "Xcode/watchOS DeviceSupport/",
                "Xcode/tvOS DeviceSupport/", "Xcode/visionOS DeviceSupport/",
                "Xcode/DeviceSupport/"
            ]
            return allowedRoots.contains { prefix in
                guard relative.hasPrefix(prefix) else { return false }
                return !String(relative.dropFirst(prefix.count)).contains("/")
            }
        case .documentation:
            return relative.hasPrefix("Shared/Documentation/DocSets/") || relative.hasPrefix("Xcode/DocumentationCache/")
        case .deviceLog:
            return relative.hasPrefix("Xcode/iOS Device Logs/")
        case .previewData:
            return relative.hasPrefix("Xcode/UserData/Previews/")
        case .xcodeCache:
            let allowed = ["Cache.db", "Cache.db-shm", "Cache.db-wal", "TestReport", "fsCachedData"]
            return candidate.deletingLastPathComponent() == root && allowed.contains(candidate.lastPathComponent)
        case .cursorCache:
            return candidate != root && isExactAllowlistedChild(relative, names: AIToolAllowlist.cursorChildNames)
        case .codexCache:
            if candidate == root {
                return AIToolAllowlist.systemCacheFolderNames.contains(root.lastPathComponent)
            }
            return isExactAllowlistedChild(relative, names: AIToolAllowlist.codexChildNames)
        case .claudeCache:
            if candidate == root {
                return AIToolAllowlist.systemCacheFolderNames.contains(root.lastPathComponent)
            }
            return isExactAllowlistedChild(relative, names: AIToolAllowlist.claudeChildNames)
        case .simulatorDevice, .simulatorRuntime:
            return false
        }
    }
}

struct DefaultCleanupPlanner: CleanupPlanning {
    private let policy = CleanupPathPolicy()

    func makePlan(from selection: CleanupSelection, snapshot: ScanSnapshot, roots: [AuthorizedRoot]) throws -> CleanupPlan {
        guard !selection.itemIDs.isEmpty else { throw CleanupPolicyError.noSelection }
        let lookup = Dictionary(uniqueKeysWithValues: snapshot.allItems.map { ($0.id, $0) })
        let developer = roots.first(where: { $0.kind == .developerDirectory })
        let xcodeCache = roots.first(where: { $0.kind == .xcodeCache })

        let items = try selection.itemIDs.sorted().map { id -> CleanupPlanItem in
            guard let item = lookup[id] else { throw CleanupPolicyError.itemMissing(id) }
            guard item.action != .inspectionOnly else { throw CleanupPolicyError.inspectionOnly(item.displayName) }

            if item.action == .permanentSimulatorDeletion {
                guard let root = developer else { throw CleanupPolicyError.outsideAuthorizedRoot(item.displayName) }
                return CleanupPlanItem(item: item, authorizedRoot: root.url, canonicalURLAtPlanning: nil)
            }

            let root = authorizedRoot(for: item, developer: developer, xcodeCache: xcodeCache, roots: roots)
            guard let root else { throw CleanupPolicyError.outsideAuthorizedRoot(item.displayName) }
            let canonical = try policy.validate(item, inside: root.url)
            return CleanupPlanItem(item: item, authorizedRoot: root.url, canonicalURLAtPlanning: canonical)
        }

        return CleanupPlan(
            id: UUID(),
            createdAt: .now,
            snapshotGenerationID: snapshot.generationID,
            items: items
        )
    }

    private func authorizedRoot(
        for item: StorageItem,
        developer: AuthorizedRoot?,
        xcodeCache: AuthorizedRoot?,
        roots: [AuthorizedRoot]
    ) -> AuthorizedRoot? {
        switch item.kind {
        case .xcodeCache:
            return xcodeCache
        case .cursorCache:
            return matchingAIRoot(item, in: roots, kinds: [.cursorSupport, .cursorHome])
        case .codexCache:
            return matchingAIRoot(item, in: roots, kinds: [.codexHome, .codexSystemCache])
        case .claudeCache:
            return matchingAIRoot(item, in: roots, kinds: [.claudeHome, .claudeSystemCache, .claudeSupport])
        default:
            return developer
        }
    }

    private func matchingAIRoot(_ item: StorageItem, in roots: [AuthorizedRoot], kinds: [AuthorizedRootKind]) -> AuthorizedRoot? {
        guard let url = item.url?.canonicalFileURL else { return nil }
        return roots.first { root in
            guard kinds.contains(root.kind) else { return false }
            let rootURL = root.url.canonicalFileURL
            return url == rootURL || url.isDescendant(of: rootURL)
        }
    }
}
