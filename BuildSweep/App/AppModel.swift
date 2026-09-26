import AppKit
import Foundation
import Observation

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
    var onboardingCompleted = false
    var isBootstrapped = false

    private let authorizer: FolderAccessAuthorizer
    private let planner: CleanupPlanning
    private let executor: CleanupExecuting
    private let historyStore: CleanupHistoryStore
    private let scanCache: ScanCacheStore
    private let loginService: LaunchAtLoginService
    private let defaults: UserDefaults
    private let onboardingKey = "onboardingCompleted.v1"
    private var scanTask: Task<Void, Never>?

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
    var xcodeAuthorizedRoots: [AuthorizedRoot] { authorizedRoots.filter { !$0.kind.isAI } }
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

        if let cached = await scanCache.load(maximumAge: 60 * 60) {
            snapshot = cached
            scanState = .complete
        }
        if developerRoot != nil, snapshot.categories.isEmpty {
            startScan()
        }
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
            claudeIsRunning: claudeIsRunning
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
                            return StorageCategorySnapshot(category: category, items: [], scannedAt: .now, warnings: [error.localizedDescription])
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
        showingCleanupReview = false
        let result = await executor.execute(plan)
        latestCleanupResult = result
        await historyStore.append(result)
        history = await historyStore.load()
        if result.hadAnySuccess {
            selectedItemIDs.subtract(result.succeededItems.map(\.itemID))
        }
        preservedPlan = nil
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
