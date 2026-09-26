import Foundation

enum AIToolAllowlist {
    static let cursorSupport = [
        "Cache", "CachedData", "CachedExtensionVSIXs", "Code Cache", "GPUCache",
        "DawnGraphiteCache", "DawnWebGPUCache", "Crashpad", "logs", "blob_storage"
    ]
    static let cursorHome = ["ai-tracking", "debug-logs"]
    static let codexHome = ["cache", ".tmp"]
    static let claudeHome = ["cache"]
    static let claudeSupport = ["Cache", "CachedData", "GPUCache", "logs"]
    static let systemCacheFolderNames: Set<String> = [
        "com.openai.codex", "Codex", "com.anthropic.claudefordesktop"
    ]
    static let forbiddenNames: Set<String> = [
        "User", "Session Storage", "skills", "skills-cursor", "projects", "plans",
        "plugins", "auth.json", "config.toml", "sessions", "archived_sessions",
        "cookies", "IndexedDB"
    ]

    static var cursorChildNames: Set<String> { Set(cursorSupport + cursorHome) }
    static var codexChildNames: Set<String> { Set(codexHome) }
    static var claudeChildNames: Set<String> { Set(claudeHome + claudeSupport) }

    static func scope(for name: String) -> AIToolDataScope {
        let value = name.lowercased()
        return value.contains("log") || value.contains("crash") || value.contains("tracking") ? .logs : .cache
    }
}

actor AIToolStorageScanner: StorageScanner {
    let category: StorageCategoryID = .aiTools
    private let fileManager: FileManager
    private let sizer: DirectorySizer

    init(fileManager: FileManager = .default, sizer: DirectorySizer = DirectorySizer()) {
        self.fileManager = fileManager
        self.sizer = sizer
    }

    func scan(in context: ScanContext) async throws -> StorageCategorySnapshot {
        try Task.checkCancellation()
        var items: [StorageItem] = []
        var warnings: [String] = []

        items += try await scanChildren(
            root: context.cursorSupportRoot,
            names: AIToolAllowlist.cursorSupport,
            kind: .cursorCache,
            tool: "Cursor",
            context: context
        )
        items += try await scanChildren(
            root: context.cursorHomeRoot,
            names: AIToolAllowlist.cursorHome,
            kind: .cursorCache,
            tool: "Cursor",
            context: context
        )
        items += try await scanChildren(
            root: context.codexHomeRoot,
            names: AIToolAllowlist.codexHome,
            kind: .codexCache,
            tool: "Codex",
            context: context
        )
        for cacheRoot in context.codexSystemCacheRoots {
            if let item = try await scanExactRoot(
                cacheRoot,
                kind: .codexCache,
                displayName: cacheRoot.lastPathComponent == "Codex" ? "Codex Library Cache" : "Codex system cache",
                tool: "Codex",
                context: context
            ) {
                items.append(item)
            }
        }
        items += try await scanChildren(
            root: context.claudeHomeRoot,
            names: AIToolAllowlist.claudeHome,
            kind: .claudeCache,
            tool: "Claude",
            context: context
        )
        if let item = try await scanExactRoot(
            context.claudeSystemCacheRoot,
            kind: .claudeCache,
            displayName: "Claude desktop cache",
            tool: "Claude",
            context: context
        ) {
            items.append(item)
        }
        items += try await scanChildren(
            root: context.claudeSupportRoot,
            names: AIToolAllowlist.claudeSupport,
            kind: .claudeCache,
            tool: "Claude",
            context: context
        )

        if context.cursorIsRunning {
            warnings.append("Cursor is running. Its caches are listed but not preselected.")
        }
        if context.codexIsRunning {
            warnings.append("Codex is running. Its caches are listed but not preselected.")
        }
        if context.claudeIsRunning {
            warnings.append("Claude is running. Its caches are listed but not preselected.")
        }

        return StorageCategorySnapshot(
            category: .aiTools,
            items: items.sorted { $0.size > $1.size },
            scannedAt: .now,
            warnings: warnings
        )
    }

    private func scanChildren(
        root: URL?,
        names: [String],
        kind: StorageItemKind,
        tool: String,
        context: ScanContext
    ) async throws -> [StorageItem] {
        guard let root else { return [] }
        var items: [StorageItem] = []
        for name in names {
            try Task.checkCancellation()
            let url = root.appending(path: name, directoryHint: .isDirectory)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            guard !containsForbiddenName(url) else { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            let size = try await sizer.allocatedSize(of: url)
            let scope = AIToolAllowlist.scope(for: name)
            let scopeEnabled = context.isAIToolScopeEnabled(tool: tool, scope: scope)
            let newestDate = scope == .logs ? try await sizer.newestModificationDate(of: url) : values?.contentModificationDate
            let retentionCutoff = Date.now.addingTimeInterval(-Double(context.aiLogRetentionDays) * 86_400)
            let protectedByRetention = scope == .logs && context.aiLogRetentionDays > 0
                && (newestDate.map { $0 >= retentionCutoff } ?? true)
            let isCleanable = scopeEnabled && !protectedByRetention
            items.append(StorageItem(
                category: .aiTools,
                kind: kind,
                displayName: "\(tool) \(name)",
                url: url,
                size: size,
                modifiedAt: newestDate,
                risk: isCleanable ? .regenerates : .inspectionOnly,
                action: isCleanable ? .trash : .inspectionOnly,
                isDefaultSelected: false,
                metadata: [
                    "Tool": tool,
                    "Scope": scope.title,
                    "Folder": name,
                    "Cleanup": !scopeEnabled ? "Disabled in Settings" : (protectedByRetention ? "Preserved by log retention" : "Available")
                ]
            ))
        }
        return items
    }

    private func scanExactRoot(
        _ root: URL?,
        kind: StorageItemKind,
        displayName: String,
        tool: String,
        context: ScanContext
    ) async throws -> StorageItem? {
        guard let root, fileManager.fileExists(atPath: root.path) else { return nil }
        guard AIToolAllowlist.systemCacheFolderNames.contains(root.lastPathComponent) else { return nil }
        let values = try? root.resourceValues(forKeys: [.contentModificationDateKey])
        let size = try await sizer.allocatedSize(of: root)
        let scopeEnabled = context.isAIToolScopeEnabled(tool: tool, scope: .cache)
        return StorageItem(
            category: .aiTools,
            kind: kind,
            displayName: displayName,
            url: root,
            size: size,
            modifiedAt: values?.contentModificationDate,
            risk: scopeEnabled ? .regenerates : .inspectionOnly,
            action: scopeEnabled ? .trash : .inspectionOnly,
            isDefaultSelected: false,
            metadata: ["Tool": tool, "Scope": AIToolDataScope.cache.title, "Folder": root.lastPathComponent, "Cleanup": scopeEnabled ? "Available" : "Disabled in Settings"]
        )
    }

    private func containsForbiddenName(_ url: URL) -> Bool {
        url.pathComponents.contains(where: AIToolAllowlist.forbiddenNames.contains)
    }
}
