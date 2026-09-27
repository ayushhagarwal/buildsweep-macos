import AppKit
import Foundation
import Observation

enum CleanupPreset: String, CaseIterable, Identifiable {
    case xcodeRebuildable
    case packageManagerDownloads

    var id: String { rawValue }

    var title: String {
        switch self {
        case .xcodeRebuildable: "Review Xcode Rebuildable Caches"
        case .packageManagerDownloads: "Review Package Manager Caches"
        }
    }

    var explanation: String {
        switch self {
        case .xcodeRebuildable: "Derived Data and compiler caches; Xcode may take longer to rebuild afterward."
        case .packageManagerDownloads: "Individually approved Swift, CocoaPods, Carthage, npm, Yarn, pnpm, and Bun caches; packages may need to download or rebuild again."
        }
    }

    func includes(_ item: StorageItem) -> Bool {
        guard item.action == .trash else { return false }
        switch self {
        case .xcodeRebuildable:
            return item.kind == .derivedData || item.kind == .compilerCache
        case .packageManagerDownloads:
            return item.kind == .packageManagerCache
        }
    }
}

@MainActor
@Observable
final class AppModel {
    enum ScanState: Equatable {
        case idle
        case scanning(completed: Int, total: Int)
        case complete
        case failed(String)
    }

    var selection: StorageCategoryID = .overview
    var authorizedRoots: [AuthorizedRoot] = []
    var snapshot: ScanSnapshot = .empty
    var scanState: ScanState = .idle
    var selectedItemIDs: Set<String> = []
    var searchText = ""
    var showingCleanupReview = false
    var preservedPlan: CleanupPlan?
    var latestCleanupResult: CleanupSessionResult?
    var history: [CleanupSessionResult] = []
    var appMessage: String?
    var launchAtLogin = false
    var mcpEnabled = false
    var mcpServiceStatus = "Off"
    var onboardingCompleted = false
    var isBootstrapped = false

    private let authorizer: FolderAccessAuthorizer
    private let planner: CleanupPlanning
    private let executor: CleanupExecuting
    private let historyStore: CleanupHistoryStore
    private let scanCache: ScanCacheStore
    private let loginService: LaunchAtLoginService
    private let defaults: UserDefaults
    private let mcpServer = MCPAgentSocketServer()
    private let onboardingKey = "onboardingCompleted.v1"
    private let aiLogRetentionKey = "aiLogRetentionDays.v1"
    private let mcpEnabledKey = "mcpEnabled.v1"
    private var scanTask: Task<Void, Never>?
    private var mcpItemRegistry = MCPAgentItemRegistry()
    private var mcpReviewStates: [UUID: MCPReviewState] = [:]
    private var pendingMCPReviewID: UUID?
    var openMainWindow: (() -> Void)?

    init(
        authorizer: FolderAccessAuthorizer? = nil,
        planner: CleanupPlanning = DefaultCleanupPlanner(),
        historyStore: CleanupHistoryStore = CleanupHistoryStore(),
        scanCache: ScanCacheStore = ScanCacheStore(),
        loginService: LaunchAtLoginService? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.authorizer = authorizer ?? FolderAccessAuthorizer()
        self.planner = planner
        self.historyStore = historyStore
        self.scanCache = scanCache
        self.loginService = loginService ?? LaunchAtLoginService()
        self.defaults = defaults
        self.executor = DefaultCleanupExecutor()
    }

    var developerRoot: AuthorizedRoot? { authorizedRoots.first { $0.kind == .developerDirectory } }
    var xcodeCacheRoot: AuthorizedRoot? { authorizedRoots.first { $0.kind == .xcodeCache } }
    var xcodeAuthorizedRoots: [AuthorizedRoot] { authorizedRoots.filter { $0.kind == .developerDirectory || $0.kind == .xcodeCache } }
    var hasAnyAIRoot: Bool { authorizedRoots.contains { $0.kind.isAI } }
    var needsOnboarding: Bool { developerRoot == nil || !onboardingCompleted }
    var selectedItems: [StorageItem] { snapshot.allItems.filter { selectedItemIDs.contains($0.id) } }
    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }
    var xcodeIsRunning: Bool {
        isAppRunning(bundleIDs: ["com.apple.dt.Xcode"], names: ["Xcode"])
    }
    var simulatorIsRunning: Bool {
        isAppRunning(bundleIDs: ["com.apple.iphonesimulator"], names: ["Simulator"])
    }
    var cursorIsRunning: Bool {
        isAppRunning(bundleIDs: ["com.todesktop.230313mzl4w4u92", "com.cursor.Cursor"], names: ["Cursor"])
    }
    var codexIsRunning: Bool {
        isAppRunning(bundleIDs: ["com.openai.codex", "com.openai.Codex"], names: ["Codex"])
    }
    var claudeIsRunning: Bool {
        isAppRunning(bundleIDs: ["com.anthropic.claudefordesktop"], names: ["Claude"])
    }
    var availableDiskSpace: Int64 {
        let values = try? RealUserHome.directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    func bootstrap() async {
        guard !isBootstrapped else { return }
        isBootstrapped = true
        authorizedRoots = await authorizer.restoreAuthorizedRoots()
        history = await historyStore.load()
        launchAtLogin = loginService.isEnabled
        onboardingCompleted = defaults.bool(forKey: onboardingKey)
        mcpEnabled = defaults.bool(forKey: mcpEnabledKey)

        if let cached = await scanCache.load(maximumAge: 60 * 60) {
            snapshot = cached
            scanState = .complete
        }
        if developerRoot != nil, snapshot.categories.isEmpty {
            startScan()
        }
        if mcpEnabled { startMCPService() }
    }

    func grantDeveloperAccess() async {
        do {
            let root = try await authorizer.requestDeveloperDirectory()
            authorizedRoots.removeAll { $0.kind == .developerDirectory }
            authorizedRoots.append(root)
            appMessage = nil
            startScan()
        } catch FolderAuthorizationError.cancelled {
            return
        } catch {
            appMessage = error.localizedDescription
        }
    }

    func grantXcodeCacheAccess() async {
        do {
            let root = try await authorizer.requestXcodeCacheDirectory()
            authorizedRoots.removeAll { $0.kind == .xcodeCache }
            authorizedRoots.append(root)
            startScan()
        } catch FolderAuthorizationError.cancelled {
            return
        } catch {
            appMessage = error.localizedDescription
        }
    }

    func packageCacheRoot(for group: DeveloperCacheGroup) -> AuthorizedRoot? {
        authorizedRoots.first { $0.kind == .developerPackageCache && $0.url.canonicalFileURL == group.url.canonicalFileURL }
    }

    func grantPackageCacheAccess(_ group: DeveloperCacheGroup) async {
        do {
            let root = try await authorizer.requestAuthorizedFolder(kind: .developerPackageCache, preferring: group.url)
            authorizedRoots.removeAll { $0.kind == .developerPackageCache && $0.url.canonicalFileURL == group.url.canonicalFileURL }
            authorizedRoots.append(root)
            startScan()
        } catch FolderAuthorizationError.cancelled {
            return
        } catch {
            appMessage = error.localizedDescription
        }
    }

    func roots(in group: AIToolGroup) -> [AuthorizedRoot] {
        authorizedRoots.filter { group.kinds.contains($0.kind) }
    }

    func hasGranted(_ group: AIToolGroup) -> Bool {
        !roots(in: group).isEmpty
    }

    func hasMissingGrant(in group: AIToolGroup) -> Bool {
        group.grantTargets.contains { target in
            !authorizedRoots.contains { matchesGrant($0, target: target) }
        }
    }

    func grantAIToolGroup(_ group: AIToolGroup) async {
        var grantedAny = false
        for target in group.grantTargets {
            if authorizedRoots.contains(where: { matchesGrant($0, target: target) }) { continue }
            do {
                let root = try await authorizer.requestAuthorizedFolder(kind: target.kind, preferring: target.url)
                authorizedRoots.removeAll { matchesGrant($0, target: target) }
                authorizedRoots.append(root)
                grantedAny = true
            } catch FolderAuthorizationError.cancelled {
                if grantedAny { startScan() }
                return
            } catch {
                appMessage = error.localizedDescription
                if grantedAny { startScan() }
                return
            }
        }
        if grantedAny { startScan() }
    }

    func forgetAIToolGroup(_ group: AIToolGroup) async {
        for root in roots(in: group) {
            await authorizer.forget(root)
            authorizedRoots.removeAll { $0.id == root.id }
        }
        selectedItemIDs.removeAll()
        startScan()
    }

    func isAIToolScopeEnabled(_ scope: AIToolDataScope, for group: AIToolGroup) -> Bool {
        defaults.object(forKey: aiScopePreferenceKey(scope, group: group)) as? Bool ?? true
    }

    func setAIToolScopeEnabled(_ enabled: Bool, scope: AIToolDataScope, for group: AIToolGroup) {
        defaults.set(enabled, forKey: aiScopePreferenceKey(scope, group: group))
        startScan()
    }

    var aiLogRetentionDays: Int {
        defaults.object(forKey: aiLogRetentionKey) == nil ? 30 : defaults.integer(forKey: aiLogRetentionKey)
    }

    func setAILogRetentionDays(_ days: Int) {
        guard [0, 7, 30, 90].contains(days) else { return }
        defaults.set(days, forKey: aiLogRetentionKey)
        startScan()
    }

    func forgetRoot(_ root: AuthorizedRoot) async {
        await authorizer.forget(root)
        authorizedRoots.removeAll { $0.id == root.id }
        selectedItemIDs.removeAll()
        if root.kind == .developerDirectory {
            onboardingCompleted = false
            defaults.set(false, forKey: onboardingKey)
            snapshot = .empty
            scanState = .idle
        } else {
            startScan()
        }
    }

    func completeOnboarding() {
        guard developerRoot != nil else { return }
        onboardingCompleted = true
        defaults.set(true, forKey: onboardingKey)
        selection = .overview
    }

    func startScan() {
        guard let developerRoot else { return }
        scanTask?.cancel()
        let generation = UUID()
        let context = ScanContext(
            developerRoot: developerRoot.url,
            xcodeCacheRoot: xcodeCacheRoot?.url,
            generationID: generation,
            xcodeIsRunning: xcodeIsRunning,
            cursorSupportRoot: rootURL(for: .cursorSupport),
            cursorHomeRoot: rootURL(for: .cursorHome),
            codexHomeRoot: rootURL(for: .codexHome),
            codexSystemCacheRoots: authorizedRoots.filter { $0.kind == .codexSystemCache }.map(\.url),
            claudeHomeRoot: rootURL(for: .claudeHome),
            claudeSystemCacheRoot: rootURL(for: .claudeSystemCache),
            claudeSupportRoot: rootURL(for: .claudeSupport),
            cursorIsRunning: cursorIsRunning,
            codexIsRunning: codexIsRunning,
            claudeIsRunning: claudeIsRunning,
            disabledAIToolScopes: Set(AIToolGroup.allCases.flatMap { group in
                AIToolDataScope.allCases.compactMap { scope in
                    isAIToolScopeEnabled(scope, for: group) ? nil : "\(group.rawValue).\(scope.rawValue)"
                }
            }),
            aiLogRetentionDays: aiLogRetentionDays,
            developerPackageCacheRoots: authorizedRoots
                .filter { $0.kind == .developerPackageCache }
                .map(\.url)
        )
        var categories = StorageCategoryID.allCases.filter { $0.isScannable && $0 != .aiTools }
        if context.hasAIRoots {
            categories.append(.aiTools)
        }
        snapshot = ScanSnapshot(generationID: generation, startedAt: .now, completedAt: nil, categories: [:])
        scanState = .scanning(completed: 0, total: categories.count)
        selectedItemIDs.removeAll()

        scanTask = Task { [weak self] in
            guard let self else { return }
            await withTaskGroup(of: StorageCategorySnapshot.self) { group in
                for category in categories {
                    group.addTask {
                        do {
                            if category == .aiTools {
                                return try await AIToolStorageScanner().scan(in: context)
                            }
                            return try await XcodeStorageScanner(category: category).scan(in: context)
                        } catch {
                            return StorageCategorySnapshot(category: category, items: [], scannedAt: .now, warnings: [error.localizedDescription], status: .failed)
                        }
                    }
                }

                var completed = 0
                for await categorySnapshot in group {
                    guard !Task.isCancelled, self.snapshot.generationID == generation else { continue }
                    self.snapshot.categories[categorySnapshot.category] = categorySnapshot
                    completed += 1
                    self.scanState = .scanning(completed: completed, total: categories.count)
                    for item in categorySnapshot.items where item.isDefaultSelected {
                        self.selectedItemIDs.insert(item.id)
                    }
                }
            }
            guard !Task.isCancelled, self.snapshot.generationID == generation else { return }
            self.snapshot.completedAt = .now
            self.scanState = .complete
            await self.scanCache.save(self.snapshot)
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        scanState = .idle
    }

    func toggleSelection(_ item: StorageItem) {
        guard item.action != .inspectionOnly else { return }
        if selectedItemIDs.contains(item.id) { selectedItemIDs.remove(item.id) }
        else { selectedItemIDs.insert(item.id) }
    }

    func selectXcodeRebuildableCaches() {
        let safeKinds: Set<StorageItemKind> = [.derivedData, .compilerCache]
        selectedItemIDs = Set(snapshot.allItems.compactMap { item in
            safeKinds.contains(item.kind) && item.action == .trash ? item.id : nil
        })
    }

    func prepareCleanup() {
        do {
            let plan = try planner.makePlan(
                from: CleanupSelection(itemIDs: selectedItemIDs),
                snapshot: snapshot,
                roots: authorizedRoots
            )
            preservedPlan = plan
            showingCleanupReview = true
        } catch {
            appMessage = error.localizedDescription
        }
    }

    func setMCPEnabled(_ enabled: Bool) {
        guard enabled != mcpEnabled else { return }
        mcpEnabled = enabled
        defaults.set(enabled, forKey: mcpEnabledKey)
        if enabled {
            startMCPService()
        } else {
            mcpServer.stop()
            mcpServiceStatus = "Off"
            if let pendingMCPReviewID {
                mcpReviewStates[pendingMCPReviewID] = .cancelled
                showingCleanupReview = false
                preservedPlan = nil
            }
            pendingMCPReviewID = nil
        }
    }

    func configureMainWindowOpener(_ opener: @escaping () -> Void) {
        openMainWindow = opener
    }

    func cancelCleanupReview() {
        showingCleanupReview = false
        preservedPlan = nil
        if let pendingMCPReviewID {
            mcpReviewStates[pendingMCPReviewID] = .cancelled
            self.pendingMCPReviewID = nil
        }
    }

    func cleanupReviewWasDismissed() {
        guard let pendingMCPReviewID, mcpReviewStates[pendingMCPReviewID] == .waitingForReview else { return }
        mcpReviewStates[pendingMCPReviewID] = .cancelled
        self.pendingMCPReviewID = nil
        preservedPlan = nil
    }

    func prepareCleanup(preset: CleanupPreset) {
        let items = snapshot.allItems.filter(preset.includes)
        guard !items.isEmpty else {
            appMessage = "No eligible items are available for ‘\(preset.title)’. Scan storage and grant access to the locations you want included."
            return
        }
        selectedItemIDs = Set(items.map(\.id))
        prepareCleanup()
    }

    func executePreservedCleanup() async {
        guard let plan = preservedPlan else { return }
        let xcodeSensitiveKinds: Set<StorageItemKind> = [.derivedData, .compilerCache, .documentation, .previewData, .xcodeCache]
        if plan.items.contains(where: { xcodeSensitiveKinds.contains($0.item.kind) }), xcodeIsRunning {
            appMessage = "Quit Xcode before cleaning Derived Data or shared caches."
            return
        }
        if !plan.permanentItems.isEmpty, simulatorIsRunning {
            appMessage = "Quit Simulator before deleting a Simulator device."
            return
        }
        if plan.items.contains(where: { $0.item.kind == .cursorCache }), cursorIsRunning {
            appMessage = "Quit Cursor before cleaning its caches."
            return
        }
        if plan.items.contains(where: { $0.item.kind == .codexCache }), codexIsRunning {
            appMessage = "Quit Codex before cleaning its caches."
            return
        }
        if plan.items.contains(where: { $0.item.kind == .claudeCache }), claudeIsRunning {
            appMessage = "Quit Claude before cleaning its caches."
            return
        }
        let result = await executor.execute(plan)
        await historyStore.append(result)
        history = await historyStore.load()
        if result.hadAnySuccess {
            selectedItemIDs.subtract(result.succeededItems.map(\.itemID))
        }
        preservedPlan = nil
        if let pendingMCPReviewID {
            mcpReviewStates[pendingMCPReviewID] = .completed(
                movedToTrash: result.succeededItems.count,
                failed: result.failedItems.count
            )
            self.pendingMCPReviewID = nil
        }
        latestCleanupResult = result
        showingCleanupReview = false
        startScan()
    }

    func clearHistory() async {
        await historyStore.clear()
        history = []
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try loginService.setEnabled(enabled)
            launchAtLogin = loginService.isEnabled
        } catch {
            launchAtLogin = loginService.isEnabled
            appMessage = error.localizedDescription
        }
    }

    func reveal(_ item: StorageItem) {
        guard let url = item.url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copyPath(_ item: StorageItem) {
        guard let path = item.url?.path else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }

    func copyDiagnostics() {
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        let xcodeVersion: String = {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.dt.Xcode"),
                  let bundle = Bundle(url: url) else { return "Not found" }
            let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
            let build = bundle.object(forInfoDictionaryKey: "ProductBuildVersion") as? String ?? "Unknown"
            return "\(version) (\(build))"
        }()
        let warnings = snapshot.categories.values.flatMap(\.warnings)
        let summary = [
            "BuildSweep \(appVersion) (\(build))",
            "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Xcode \(xcodeVersion)",
            "Simulator deletion: \(SimulatorFeaturePolicy.deletionEnabled ? "validated" : "inspection only")",
            "Scan warnings: \(warnings.isEmpty ? "None" : warnings.joined(separator: " | "))"
        ].joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)
        appMessage = "Diagnostics copied. Review them before sharing; no project paths are included."
    }

    func openXcodeComponents() {
        guard let xcodeURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.dt.Xcode") else { return }
        NSWorkspace.shared.open(xcodeURL)
    }

    private func rootURL(for kind: AuthorizedRootKind) -> URL? {
        authorizedRoots.first { $0.kind == kind }?.url
    }

    private func aiScopePreferenceKey(_ scope: AIToolDataScope, group: AIToolGroup) -> String {
        "aiCleanup.\(group.rawValue).\(scope.rawValue).enabled.v1"
    }

    private func matchesGrant(_ root: AuthorizedRoot, target: (kind: AuthorizedRootKind, url: URL)) -> Bool {
        guard root.kind == target.kind else { return false }
        return root.url.standardizedFileURL.path == target.url.standardizedFileURL.path
            || root.url.canonicalFileURL.path == target.url.canonicalFileURL.path
    }

    private func isAppRunning(bundleIDs: [String], names: [String]) -> Bool {
        NSWorkspace.shared.runningApplications.contains { application in
            if let identifier = application.bundleIdentifier, bundleIDs.contains(identifier) { return true }
            if let name = application.localizedName, names.contains(name) { return true }
            return false
        }
    }
}

private enum MCPReviewState: Equatable {
    case waitingForReview
    case cancelled
    case completed(movedToTrash: Int, failed: Int)
}

private struct MCPAgentArguments: Decodable {
    let category: String?
    let limit: Int?
    let cursor: String?
    let itemID: String?
    let itemIDs: [String]?
    let snapshotGeneration: String?
    let reviewID: String?
}

private struct MCPAgentItemSummary: Encodable {
    let id: String
    let name: String
    let category: String
    let kind: String
    let estimatedBytes: Int64
    let risk: String
    let action: String
}

private struct MCPAgentChildSummary: Encodable {
    let name: String
    let isDirectory: Bool
    let isSymbolicLink: Bool
    let estimatedBytes: Int64?
    let modifiedAt: Date?
}

extension AppModel {
    private func startMCPService() {
        do {
            try mcpServer.start { [weak self] request in
                guard let self else {
                    return MCPBridgeResponse(id: request.id, result: nil, error: "BuildSweep is unavailable.")
                }
                return await self.handleMCPRequest(request)
            }
            mcpServiceStatus = "Enabled · waiting for a local client"
        } catch {
            mcpServiceStatus = "Unavailable · \(error.localizedDescription)"
        }
    }

    private func handleMCPRequest(_ request: MCPBridgeRequest) async -> MCPBridgeResponse {
        guard mcpEnabled else {
            return MCPBridgeResponse(id: request.id, result: nil, error: "MCP is disabled in BuildSweep Settings.")
        }
        do {
            let arguments = try JSONDecoder().decode(MCPAgentArguments.self, from: Data(request.arguments.utf8))
            let value: Any
            switch request.operation {
            case "status": value = agentStatus()
            case "scan":
                guard developerRoot != nil else { throw MCPAgentError.onboardingRequired }
                if case .scanning = scanState {} else { startScan() }
                value = agentStatus()
            case "list": value = try agentList(arguments)
            case "inspect": value = try await agentInspect(arguments)
            case "prepare": value = try prepareAgentCleanup(arguments)
            case "cleanupStatus": value = try agentCleanupStatus(arguments)
            default: throw MCPAgentError.unknownOperation
            }
            let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
            return MCPBridgeResponse(id: request.id, result: String(decoding: data, as: UTF8.self), error: nil)
        } catch {
            return MCPBridgeResponse(id: request.id, result: nil, error: error.localizedDescription)
        }
    }

    private func agentStatus() -> [String: Any] {
        let scanDescription: String
        switch scanState {
        case .idle: scanDescription = "not_scanned"
        case .scanning(let completed, let total): scanDescription = "scanning \(completed) of \(total) categories"
        case .complete: scanDescription = "complete"
        case .failed: scanDescription = "failed"
        }
        return [
            "enabled": mcpEnabled,
            "service": mcpServiceStatus,
            "appOpen": true,
            "onboardingComplete": !needsOnboarding,
            "scanState": scanDescription,
            "scanGeneration": snapshot.generationID.uuidString,
            "scanCompletedAt": snapshot.completedAt?.ISO8601Format() as Any? ?? NSNull(),
            "scanAgeSeconds": snapshot.completedAt.map { max(0, Int(Date.now.timeIntervalSince($0))) } as Any? ?? NSNull(),
            "authorizedRootCount": authorizedRoots.count,
            "categories": StorageCategoryID.allCases.filter(\.isScannable).map { category in
                let result = snapshot.categories[category]
                return [
                    "id": category.rawValue,
                    "name": category.title,
                    "status": result.map { $0.status.rawValue } ?? "not_scanned",
                    "itemCount": result?.items.count ?? 0,
                    "estimatedBytes": result?.totalSize ?? 0,
                    "warningCount": result?.warnings.count ?? 0
                ] as [String: Any]
            }
        ]
    }

    private func agentList(_ arguments: MCPAgentArguments) throws -> [String: Any] {
        guard case .complete = scanState, let completedAt = snapshot.completedAt else {
            throw MCPAgentError.scanNotReady
        }
        if Date.now.timeIntervalSince(completedAt) > 60 * 60 { throw MCPAgentError.scanStale }
        mcpItemRegistry.beginGeneration(snapshot.generationID)
        let category: StorageCategoryID?
        if let rawCategory = arguments.category {
            guard let parsed = StorageCategoryID(rawValue: rawCategory), parsed.isScannable else {
                throw MCPAgentError.invalidCategory
            }
            category = parsed
        } else {
            category = nil
        }
        let items = snapshot.allItems.filter { category == nil || $0.category == category }
            .sorted {
                let nameOrder = $0.displayName.localizedStandardCompare($1.displayName)
                if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
                if $0.category != $1.category { return $0.category.rawValue < $1.category.rawValue }
                return $0.id < $1.id
            }
        let categoryCursorKey = category?.rawValue ?? "all"
        let offset: Int
        if let cursor = arguments.cursor {
            let components = cursor.split(separator: ":", omittingEmptySubsequences: false)
            guard components.count == 3,
                  components[0] == snapshot.generationID.uuidString,
                  components[1] == categoryCursorKey,
                  let parsedOffset = Int(components[2]), parsedOffset >= 0,
                  parsedOffset <= items.count else {
                throw MCPAgentError.invalidCursor
            }
            offset = parsedOffset
        } else {
            offset = 0
        }
        let limit = MCPAgentItemRegistry.boundedPageSize(arguments.limit)
        let page = Array(items.dropFirst(offset).prefix(limit))
        let summaries = page.map { item -> MCPAgentItemSummary in
            let opaqueID = mcpItemRegistry.opaqueID(for: item.id, generation: snapshot.generationID)
            return MCPAgentItemSummary(
                id: opaqueID,
                name: item.displayName,
                category: item.category.rawValue,
                kind: item.kind.rawValue,
                estimatedBytes: item.size,
                risk: item.risk.rawValue,
                action: item.action.rawValue
            )
        }
        return [
            "generation": snapshot.generationID.uuidString,
            "items": try jsonObject(summaries),
            "nextCursor": offset + page.count < items.count ? "\(snapshot.generationID.uuidString):\(categoryCursorKey):\(offset + page.count)" as Any : NSNull(),
            "totalCount": items.count
        ]
    }

    private func agentInspect(_ arguments: MCPAgentArguments) async throws -> [String: Any] {
        guard case .complete = scanState, let completedAt = snapshot.completedAt else { throw MCPAgentError.scanNotReady }
        if Date.now.timeIntervalSince(completedAt) > 60 * 60 { throw MCPAgentError.scanStale }
        guard let opaqueID = arguments.itemID,
              let storageID = mcpItemRegistry.itemID(for: opaqueID, generation: snapshot.generationID),
              let item = snapshot.allItems.first(where: { $0.id == storageID }) else { throw MCPAgentError.staleItem }
        var children: [MCPAgentChildSummary] = []
        var childCount = 0
        if let url = item.url {
            let inspection = try await DirectorySizer().inspectImmediateChildren(of: url, limit: MCPAgentItemRegistry.maximumInspectionChildren)
            childCount = inspection.totalCount
            children = inspection.children.map {
                MCPAgentChildSummary(name: String($0.name.prefix(160)), isDirectory: $0.isDirectory,
                                     isSymbolicLink: $0.isSymbolicLink, estimatedBytes: $0.size, modifiedAt: $0.modifiedAt)
            }
        }
        let safeMetadataKeys: Set<String> = [
            "Workspace", "Folder", "Bundle ID", "Signing", "dSYM", "Platform", "Newest for platform",
            "Runtime", "State", "Availability", "Version", "Devices", "Storage", "Management",
            "Tool", "Scope", "Effect", "Cleanup", "Reason"
        ]
        let safeMetadata = item.metadata
            .filter { safeMetadataKeys.contains($0.key) && !$0.value.hasPrefix("/") }
            .sorted { $0.key < $1.key }
            .prefix(20)
            .reduce(into: [String: String]()) {
                $0[String($1.key.prefix(80))] = String($1.value.prefix(160))
            }
        return [
            "id": opaqueID, "name": item.displayName, "category": item.category.rawValue,
            "kind": item.kind.rawValue, "estimatedBytes": item.size,
            "modifiedAt": item.modifiedAt?.ISO8601Format() as Any? ?? NSNull(),
            "risk": item.risk.rawValue, "action": item.action.rawValue,
            "metadata": safeMetadata,
            "children": try jsonObject(children), "childCount": childCount,
            "childrenTruncated": childCount > children.count
        ]
    }

    private func prepareAgentCleanup(_ arguments: MCPAgentArguments) throws -> [String: Any] {
        guard pendingMCPReviewID == nil else { throw MCPAgentError.reviewAlreadyOpen }
        guard case .complete = scanState else { throw MCPAgentError.scanNotReady }
        guard let completedAt = snapshot.completedAt, Date.now.timeIntervalSince(completedAt) <= 60 * 60 else {
            throw MCPAgentError.scanStale
        }
        guard let generation = arguments.snapshotGeneration,
              generation == snapshot.generationID.uuidString,
              let opaqueIDs = arguments.itemIDs, !opaqueIDs.isEmpty,
              opaqueIDs.count <= MCPAgentItemRegistry.maximumCleanupItems,
              Set(opaqueIDs).count == opaqueIDs.count else { throw MCPAgentError.invalidSelection }
        let itemIDs = try opaqueIDs.map { opaqueID -> String in
            guard let storageID = mcpItemRegistry.itemID(for: opaqueID, generation: snapshot.generationID),
                  let item = snapshot.allItems.first(where: { $0.id == storageID }),
                  item.action == .trash else { throw MCPAgentError.itemNotEligible }
            return storageID
        }
        let plan = try planner.makePlan(
            from: CleanupSelection(itemIDs: Set(itemIDs)),
            snapshot: snapshot,
            roots: authorizedRoots
        )
        let reviewID = UUID()
        mcpReviewStates[reviewID] = .waitingForReview
        if mcpReviewStates.count > 20 {
            for key in Array(mcpReviewStates.keys) where key != pendingMCPReviewID { mcpReviewStates.removeValue(forKey: key) }
        }
        pendingMCPReviewID = reviewID
        selectedItemIDs = Set(itemIDs)
        preservedPlan = plan
        openMainWindow?()
        NSApp.activate(ignoringOtherApps: true)
        showingCleanupReview = true
        return [
            "reviewID": reviewID.uuidString,
            "status": "waiting_for_person_in_buildsweep",
            "itemCount": plan.items.count,
            "estimatedBytes": plan.selectedSize,
            "message": "BuildSweep is showing this exact plan. A person must confirm it in the app; this MCP request cannot approve or execute cleanup."
        ]
    }

    private func agentCleanupStatus(_ arguments: MCPAgentArguments) throws -> [String: Any] {
        guard let rawID = arguments.reviewID, let id = UUID(uuidString: rawID),
              let state = mcpReviewStates[id] else { throw MCPAgentError.unknownReview }
        switch state {
        case .waitingForReview: return ["reviewID": rawID, "status": "waiting_for_person_in_buildsweep"]
        case .cancelled: return ["reviewID": rawID, "status": "cancelled"]
        case .completed(let moved, let failed): return ["reviewID": rawID, "status": "completed", "movedToTrash": moved, "failed": failed]
        }
    }

    private func jsonObject<T: Encodable>(_ value: T) throws -> Any {
        let data = try JSONEncoder().encode(value)
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }
}

private enum MCPAgentError: LocalizedError {
    case onboardingRequired, scanNotReady, scanStale, invalidCategory, invalidCursor
    case staleItem, invalidSelection, itemNotEligible, unknownReview, reviewAlreadyOpen, unknownOperation

    var errorDescription: String? {
        switch self {
        case .onboardingRequired: "Complete BuildSweep onboarding and authorize the Developer folder first."
        case .scanNotReady: "No completed scan is available. Call scan_storage, then check get_status before listing items."
        case .scanStale: "The scan is more than one hour old. Scan again before continuing."
        case .invalidCategory: "Unknown or non-scannable category."
        case .invalidCursor: "The page cursor is invalid or belongs to an older scan."
        case .staleItem: "The item ID is unknown or belongs to an older scan. List items again."
        case .invalidSelection: "The cleanup selection is empty, too large, duplicated, or belongs to an older scan."
        case .itemNotEligible: "At least one item is not eligible for cleanup. BuildSweep did not stage a plan."
        case .unknownReview: "The review ID is unknown or has expired."
        case .reviewAlreadyOpen: "A cleanup review is already open in BuildSweep. Finish or cancel it before staging another plan."
        case .unknownOperation: "Unknown local MCP operation."
        }
    }
}
