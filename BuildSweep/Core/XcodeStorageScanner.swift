import Foundation

actor XcodeStorageScanner: StorageScanner {
    let category: StorageCategoryID
    private let fileManager: FileManager
    private let sizer: DirectorySizer
    private let simulatorController: SimulatorControlling

    init(
        category: StorageCategoryID,
        fileManager: FileManager = .default,
        sizer: DirectorySizer = DirectorySizer(),
        simulatorController: SimulatorControlling = SimctlController()
    ) {
        self.category = category
        self.fileManager = fileManager
        self.sizer = sizer
        self.simulatorController = simulatorController
    }

    func scan(in context: ScanContext) async throws -> StorageCategorySnapshot {
        try Task.checkCancellation()
        switch category {
        case .derivedData: return try await scanDerivedData(context)
        case .archives: return try await scanArchives(context)
        case .deviceSupport: return try await scanDeviceSupport(context)
        case .cachesAndLogs: return try await scanCachesAndLogs(context)
        case .simulators: return try await scanSimulators(context)
        case .overview, .history, .aiTools:
            return StorageCategorySnapshot(category: category, items: [], scannedAt: .now, warnings: [])
        }
    }

    private func scanDerivedData(_ context: ScanContext) async throws -> StorageCategorySnapshot {
        let root = context.developerRoot.appending(path: "Xcode/DerivedData", directoryHint: .isDirectory)
        let children = directoryChildren(at: root)
        let cacheNames: Set<String> = ["ModuleCache.noindex", "SDKStatCaches.noindex", "CompilationCache.noindex", "SymbolCache.noindex"]
        var items: [StorageItem] = []
        for child in children where !cacheNames.contains(child.lastPathComponent) {
            try Task.checkCancellation()
            let infoURL = child.appending(path: "info.plist")
            let info = (NSDictionary(contentsOf: infoURL) as? [String: Any]) ?? [:]
            let workspace = (info["WorkspacePath"] as? String).flatMap { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }
            let lastAccess = info["LastAccessedDate"] as? Date
            let values = try? child.resourceValues(forKeys: [.contentModificationDateKey])
            let size = try await sizer.allocatedSize(of: child)
            items.append(StorageItem(
                category: .derivedData,
                kind: .derivedData,
                displayName: workspace ?? readableDerivedDataName(child.lastPathComponent),
                url: child,
                size: size,
                modifiedAt: values?.contentModificationDate,
                lastUsedAt: lastAccess,
                risk: .regenerates,
                action: .trash,
                isDefaultSelected: false,
                metadata: ["Workspace": workspace ?? "Unknown", "Folder": child.lastPathComponent]
            ))
        }
        return snapshot(items: items)
    }

    private func scanArchives(_ context: ScanContext) async throws -> StorageCategorySnapshot {
        let root = context.developerRoot.appending(path: "Xcode/Archives", directoryHint: .isDirectory)
        var items: [StorageItem] = []
        for url in archiveURLs(at: root) {
            try Task.checkCancellation()
            let info = (NSDictionary(contentsOf: url.appending(path: "Info.plist")) as? [String: Any]) ?? [:]
            let appProperties = info["ApplicationProperties"] as? [String: Any] ?? [:]
            let name = (info["Name"] as? String) ?? url.deletingPathExtension().lastPathComponent
            let version = appProperties["CFBundleShortVersionString"] as? String ?? "—"
            let build = appProperties["CFBundleVersion"] as? String ?? "—"
            let bundleID = appProperties["CFBundleIdentifier"] as? String ?? "Unknown"
            let signing = appProperties["SigningIdentity"] as? String ?? "Unknown"
            let dSYMs = directoryChildren(at: url.appending(path: "dSYMs", directoryHint: .isDirectory))
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            let size = try await sizer.allocatedSize(of: url)
            items.append(StorageItem(
                category: .archives,
                kind: .archive,
                displayName: "\(name) \(version) (\(build))",
                url: url,
                size: size,
                modifiedAt: values?.contentModificationDate,
                risk: .important,
                action: .trash,
                metadata: [
                    "Bundle ID": bundleID,
                    "Signing": signing,
                    "dSYM": dSYMs.isEmpty ? "Not found" : "Included"
                ]
            ))
        }
        return snapshot(items: items)
    }

    private func scanDeviceSupport(_ context: ScanContext) async throws -> StorageCategorySnapshot {
        let candidates = [
            "Xcode/iOS DeviceSupport", "Xcode/watchOS DeviceSupport", "Xcode/tvOS DeviceSupport",
            "Xcode/visionOS DeviceSupport", "Xcode/DeviceSupport"
        ]
        var items: [StorageItem] = []
        for relative in candidates {
            let root = context.developerRoot.appending(path: relative, directoryHint: .isDirectory)
            let children = directoryChildren(at: root).sorted {
                let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
            for (index, child) in children.enumerated() {
                try Task.checkCancellation()
                let values = try? child.resourceValues(forKeys: [.contentModificationDateKey])
                let size = try await sizer.allocatedSize(of: child)
                items.append(StorageItem(
                    category: .deviceSupport,
                    kind: .deviceSupport,
                    displayName: child.lastPathComponent,
                    url: child,
                    size: size,
                    modifiedAt: values?.contentModificationDate,
                    risk: .reviewFirst,
                    action: .trash,
                    metadata: [
                        "Platform": root.lastPathComponent.replacingOccurrences(of: " DeviceSupport", with: ""),
                        "Newest for platform": index == 0 ? "Yes — preserve unless you have a specific reason" : "No"
                    ]
                ))
            }
        }
        return snapshot(items: items.sorted { ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast) })
    }

    private func scanCachesAndLogs(_ context: ScanContext) async throws -> StorageCategorySnapshot {
        var items: [StorageItem] = []
        let derivedRoot = context.developerRoot.appending(path: "Xcode/DerivedData", directoryHint: .isDirectory)
        let cacheNames = ["ModuleCache.noindex", "SDKStatCaches.noindex", "CompilationCache.noindex", "SymbolCache.noindex"]
        for name in cacheNames {
            let url = derivedRoot.appending(path: name, directoryHint: .isDirectory)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            let size = try await sizer.allocatedSize(of: url)
            items.append(StorageItem(category: .cachesAndLogs, kind: .compilerCache, displayName: name, url: url, size: size, risk: .regenerates, action: .trash))
        }

        let documentationRoots = ["Shared/Documentation/DocSets", "Xcode/DocumentationCache"]
        for relative in documentationRoots {
            let root = context.developerRoot.appending(path: relative, directoryHint: .isDirectory)
            for child in directoryChildren(at: root) {
                let size = try await sizer.allocatedSize(of: child)
                items.append(StorageItem(category: .cachesAndLogs, kind: .documentation, displayName: child.lastPathComponent, url: child, size: size, risk: .redownloads, action: .trash))
            }
        }

        let logsRoot = context.developerRoot.appending(path: "Xcode/iOS Device Logs", directoryHint: .isDirectory)
        for child in directoryChildren(at: logsRoot) {
            let values = try? child.resourceValues(forKeys: [.contentModificationDateKey])
            let size = try await sizer.allocatedSize(of: child)
            items.append(StorageItem(category: .cachesAndLogs, kind: .deviceLog, displayName: child.lastPathComponent, url: child, size: size, modifiedAt: values?.contentModificationDate, risk: .reviewFirst, action: .trash))
        }

        let previewsRoot = context.developerRoot.appending(path: "Xcode/UserData/Previews", directoryHint: .isDirectory)
        if fileManager.fileExists(atPath: previewsRoot.path) {
            let size = try await sizer.allocatedSize(of: previewsRoot)
            items.append(StorageItem(category: .cachesAndLogs, kind: .previewData, displayName: "SwiftUI Preview Data", url: previewsRoot, size: size, risk: .inspectionOnly, action: .inspectionOnly, metadata: ["Reason": "Deletion awaits signed sandbox validation"] ))
        }

        if let cacheRoot = context.xcodeCacheRoot {
            for child in directoryChildren(at: cacheRoot) {
                let size = try await sizer.allocatedSize(of: child)
                let knownNames: Set<String> = ["Cache.db", "Cache.db-shm", "Cache.db-wal", "TestReport", "fsCachedData"]
                let isKnown = knownNames.contains(child.lastPathComponent)
                items.append(StorageItem(
                    category: .cachesAndLogs,
                    kind: .xcodeCache,
                    displayName: child.lastPathComponent,
                    url: child,
                    size: size,
                    risk: isKnown ? .regenerates : .inspectionOnly,
                    action: isKnown ? .trash : .inspectionOnly,
                    metadata: isKnown ? [:] : ["Reason": "Unknown Xcode cache item; cleanup fails closed"]
                ))
            }
        }
        return snapshot(items: items)
    }

    private func scanSimulators(_ context: ScanContext) async throws -> StorageCategorySnapshot {
        do {
            let inventory = try await simulatorController.inventory()
            var items = inventory.devices.map { device in
                StorageItem(
                    id: device.id,
                    category: .simulators,
                    kind: .simulatorDevice,
                    displayName: device.name,
                    url: device.dataPath,
                    size: device.size,
                    risk: .reviewFirst,
                    action: inventory.deletionIsAvailable ? .permanentSimulatorDeletion : .inspectionOnly,
                    metadata: ["Runtime": device.runtime, "State": device.state]
                )
            }
            items += inventory.runtimes.map { runtime in
                StorageItem(
                    id: runtime.id,
                    category: .simulators,
                    kind: .simulatorRuntime,
                    displayName: runtime.name,
                    url: nil,
                    size: 0,
                    risk: .inspectionOnly,
                    action: .inspectionOnly,
                    metadata: ["Version": runtime.version, "Management": "Open Xcode Settings › Components"]
                )
            }
            return StorageCategorySnapshot(category: category, items: items, scannedAt: .now, warnings: inventory.limitation.map { [$0] } ?? [])
        } catch {
            return StorageCategorySnapshot(category: category, items: [], scannedAt: .now, warnings: ["Simulator inventory is unavailable in this sandboxed build. Manage runtimes in Xcode Settings › Components."])
        }
    }

    private func snapshot(items: [StorageItem]) -> StorageCategorySnapshot {
        StorageCategorySnapshot(category: category, items: items.sorted { $0.size > $1.size }, scannedAt: .now, warnings: [])
    }

    private func directoryChildren(at url: URL) -> [URL] {
        (try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    private func archiveURLs(at root: URL) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var archives: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "xcarchive" {
            archives.append(url)
            enumerator.skipDescendants()
        }
        return archives
    }

    private func readableDerivedDataName(_ folder: String) -> String {
        guard let separator = folder.lastIndex(of: "-") else { return folder }
        return String(folder[..<separator])
    }
}
