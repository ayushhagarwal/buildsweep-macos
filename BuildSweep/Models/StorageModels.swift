import Foundation

enum StorageRisk: String, Codable, CaseIterable, Sendable {
    case regenerates
    case redownloads
    case reviewFirst
    case important
    case inspectionOnly

    var title: String {
        switch self {
        case .regenerates: "Regenerates"
        case .redownloads: "Redownloads"
        case .reviewFirst: "Review First"
        case .important: "Important"
        case .inspectionOnly: "Inspection Only"
        }
    }

    var explanation: String {
        switch self {
        case .regenerates: "This data is recreated when it is needed again."
        case .redownloads: "Xcode may need to download this data again."
        case .reviewFirst: "Check the version, project, and last-used date before deleting."
        case .important: "This may be required to debug, distribute, or symbolicate a build."
        case .inspectionOnly: "BuildSweep does not offer deletion for this item."
        }
    }
}

enum StorageCategoryID: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case overview
    case derivedData
    case simulators
    case archives
    case deviceSupport
    case cachesAndLogs
    case aiTools
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .derivedData: "Derived Data"
        case .simulators: "Simulators"
        case .archives: "Archives"
        case .deviceSupport: "Device Support"
        case .cachesAndLogs: "Caches & Logs"
        case .aiTools: "AI Tools"
        case .history: "History"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "rectangle.3.group"
        case .derivedData: "shippingbox"
        case .simulators: "iphone.gen3"
        case .archives: "archivebox"
        case .deviceSupport: "externaldrive"
        case .cachesAndLogs: "doc.text.magnifyingglass"
        case .aiTools: "cpu"
        case .history: "clock.arrow.circlepath"
        }
    }

    var isScannable: Bool { self != .overview && self != .history }
}

enum StorageItemKind: String, Codable, Sendable {
    case derivedData
    case compilerCache
    case archive
    case deviceSupport
    case documentation
    case deviceLog
    case previewData
    case xcodeCache
    case simulatorDevice
    case simulatorRuntime
    case cursorCache
    case codexCache
    case claudeCache
}

enum CleanupActionKind: String, Codable, Sendable {
    case trash
    case permanentSimulatorDeletion
    case inspectionOnly
}

struct StorageItem: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let category: StorageCategoryID
    let kind: StorageItemKind
    let displayName: String
    let url: URL?
    let size: Int64
    let modifiedAt: Date?
    let lastUsedAt: Date?
    let risk: StorageRisk
    let action: CleanupActionKind
    let isDefaultSelected: Bool
    let metadata: [String: String]

    init(
        id: String? = nil,
        category: StorageCategoryID,
        kind: StorageItemKind,
        displayName: String,
        url: URL?,
        size: Int64,
        modifiedAt: Date? = nil,
        lastUsedAt: Date? = nil,
        risk: StorageRisk,
        action: CleanupActionKind,
        isDefaultSelected: Bool = false,
        metadata: [String: String] = [:]
    ) {
        self.id = id ?? url?.standardizedFileURL.path ?? "\(category.rawValue):\(displayName)"
        self.category = category
        self.kind = kind
        self.displayName = displayName
        self.url = url
        self.size = size
        self.modifiedAt = modifiedAt
        self.lastUsedAt = lastUsedAt
        self.risk = risk
        self.action = action
        self.isDefaultSelected = isDefaultSelected
        self.metadata = metadata
    }
}

struct StorageCategorySnapshot: Identifiable, Codable, Hashable, Sendable {
    var id: StorageCategoryID { category }
    let category: StorageCategoryID
    let items: [StorageItem]
    let scannedAt: Date
    let warnings: [String]

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    var reclaimableSize: Int64 {
        items.filter { $0.action != .inspectionOnly }.reduce(0) { $0 + $1.size }
    }
}

struct ScanSnapshot: Codable, Hashable, Sendable {
    let generationID: UUID
    let startedAt: Date
    var completedAt: Date?
    var categories: [StorageCategoryID: StorageCategorySnapshot]

    static var empty: ScanSnapshot {
        ScanSnapshot(generationID: UUID(), startedAt: .now, completedAt: nil, categories: [:])
    }

    var totalSize: Int64 { categories.values.reduce(0) { $0 + $1.totalSize } }
    var reclaimableSize: Int64 { categories.values.reduce(0) { $0 + $1.reclaimableSize } }
    var allItems: [StorageItem] { categories.values.flatMap(\.items) }
}

enum AuthorizedRootKind: String, Codable, Sendable {
    case developerDirectory
    case xcodeCache
    case cursorSupport
    case cursorHome
    case codexHome
    case codexSystemCache
    case claudeHome
    case claudeSystemCache
    case claudeSupport

    var isAI: Bool {
        switch self {
        case .developerDirectory, .xcodeCache: false
        default: true
        }
    }

    var panelPrompt: String {
        switch self {
        case .developerDirectory: "Choose Library/Developer"
        case .xcodeCache: "Choose com.apple.dt.Xcode"
        case .cursorSupport: "Choose Application Support/Cursor"
        case .cursorHome: "Choose the .cursor folder"
        case .codexHome: "Choose the .codex folder"
        case .codexSystemCache: "Choose a Codex cache folder"
        case .claudeHome: "Choose the .claude folder"
        case .claudeSystemCache: "Choose com.anthropic.claudefordesktop"
        case .claudeSupport: "Choose Application Support/Claude"
        }
    }

    var wrongFolderMessage: String {
        switch self {
        case .developerDirectory: "Choose your Library/Developer folder, not your home or entire Library folder."
        case .xcodeCache: "Choose Library/Caches/com.apple.dt.Xcode exactly."
        case .cursorSupport: "Choose Library/Application Support/Cursor exactly."
        case .cursorHome: "Choose your .cursor folder exactly."
        case .codexHome: "Choose your .codex folder exactly."
        case .codexSystemCache: "Choose Library/Caches/com.openai.codex or Library/Caches/Codex exactly."
        case .claudeHome: "Choose your .claude folder exactly."
        case .claudeSystemCache: "Choose Library/Caches/com.anthropic.claudefordesktop exactly."
        case .claudeSupport: "Choose Library/Application Support/Claude exactly."
        }
    }

    var expectedFolders: [URL] {
        switch self {
        case .developerDirectory: [RealUserHome.developerDirectory]
        case .xcodeCache: [RealUserHome.xcodeCacheDirectory]
        case .cursorSupport: [RealUserHome.cursorSupportDirectory]
        case .cursorHome: [RealUserHome.cursorHomeDirectory]
        case .codexHome: [RealUserHome.codexHomeDirectory]
        case .codexSystemCache: [RealUserHome.codexSystemCacheDirectory, RealUserHome.codexNamedCacheDirectory]
        case .claudeHome: [RealUserHome.claudeHomeDirectory]
        case .claudeSystemCache: [RealUserHome.claudeSystemCacheDirectory]
        case .claudeSupport: [RealUserHome.claudeSupportDirectory]
        }
    }

    var settingsTitle: String {
        switch self {
        case .developerDirectory: "Xcode Developer Data"
        case .xcodeCache: "Optional Xcode App Cache"
        case .cursorSupport: "Cursor Application Support"
        case .cursorHome: "Cursor home"
        case .codexHome: "Codex home"
        case .codexSystemCache: "Codex system cache"
        case .claudeHome: "Claude home"
        case .claudeSystemCache: "Claude system cache"
        case .claudeSupport: "Claude Application Support"
        }
    }
}

enum AIToolGroup: String, CaseIterable, Identifiable, Sendable {
    case cursor
    case codex
    case claude

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cursor: "Cursor"
        case .codex: "Codex"
        case .claude: "Claude"
        }
    }

    var kinds: [AuthorizedRootKind] {
        switch self {
        case .cursor: [.cursorSupport, .cursorHome]
        case .codex: [.codexHome, .codexSystemCache]
        case .claude: [.claudeHome, .claudeSystemCache, .claudeSupport]
        }
    }

    var grantTargets: [(kind: AuthorizedRootKind, url: URL)] {
        switch self {
        case .cursor:
            [(.cursorSupport, RealUserHome.cursorSupportDirectory), (.cursorHome, RealUserHome.cursorHomeDirectory)]
        case .codex:
            [
                (.codexHome, RealUserHome.codexHomeDirectory),
                (.codexSystemCache, RealUserHome.codexSystemCacheDirectory),
                (.codexSystemCache, RealUserHome.codexNamedCacheDirectory)
            ]
        case .claude:
            [
                (.claudeHome, RealUserHome.claudeHomeDirectory),
                (.claudeSystemCache, RealUserHome.claudeSystemCacheDirectory),
                (.claudeSupport, RealUserHome.claudeSupportDirectory)
            ]
        }
    }
}

struct AuthorizedRoot: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let kind: AuthorizedRootKind
    let url: URL
    let bookmark: Data
    let grantedAt: Date
}

struct ScanContext: Sendable {
    let developerRoot: URL
    let xcodeCacheRoot: URL?
    let generationID: UUID
    let xcodeIsRunning: Bool
    let cursorSupportRoot: URL?
    let cursorHomeRoot: URL?
    let codexHomeRoot: URL?
    let codexSystemCacheRoots: [URL]
    let claudeHomeRoot: URL?
    let claudeSystemCacheRoot: URL?
    let claudeSupportRoot: URL?
    let cursorIsRunning: Bool
    let codexIsRunning: Bool
    let claudeIsRunning: Bool

    var hasAIRoots: Bool {
        cursorSupportRoot != nil
            || cursorHomeRoot != nil
            || codexHomeRoot != nil
            || !codexSystemCacheRoots.isEmpty
            || claudeHomeRoot != nil
            || claudeSystemCacheRoot != nil
            || claudeSupportRoot != nil
    }

    init(
        developerRoot: URL,
        xcodeCacheRoot: URL? = nil,
        generationID: UUID,
        xcodeIsRunning: Bool,
        cursorSupportRoot: URL? = nil,
        cursorHomeRoot: URL? = nil,
        codexHomeRoot: URL? = nil,
        codexSystemCacheRoots: [URL] = [],
        claudeHomeRoot: URL? = nil,
        claudeSystemCacheRoot: URL? = nil,
        claudeSupportRoot: URL? = nil,
        cursorIsRunning: Bool = false,
        codexIsRunning: Bool = false,
        claudeIsRunning: Bool = false
    ) {
        self.developerRoot = developerRoot
        self.xcodeCacheRoot = xcodeCacheRoot
        self.generationID = generationID
        self.xcodeIsRunning = xcodeIsRunning
        self.cursorSupportRoot = cursorSupportRoot
        self.cursorHomeRoot = cursorHomeRoot
        self.codexHomeRoot = codexHomeRoot
        self.codexSystemCacheRoots = codexSystemCacheRoots
        self.claudeHomeRoot = claudeHomeRoot
        self.claudeSystemCacheRoot = claudeSystemCacheRoot
        self.claudeSupportRoot = claudeSupportRoot
        self.cursorIsRunning = cursorIsRunning
        self.codexIsRunning = codexIsRunning
        self.claudeIsRunning = claudeIsRunning
    }
}

struct CleanupSelection: Codable, Hashable, Sendable {
    let itemIDs: Set<String>
}

struct CleanupPlanItem: Identifiable, Codable, Hashable, Sendable {
    var id: String { item.id }
    let item: StorageItem
    let authorizedRoot: URL
    let canonicalURLAtPlanning: URL?
}

struct CleanupPlan: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let createdAt: Date
    let snapshotGenerationID: UUID
    let items: [CleanupPlanItem]

    var trashItems: [CleanupPlanItem] { items.filter { $0.item.action == .trash } }
    var permanentItems: [CleanupPlanItem] { items.filter { $0.item.action == .permanentSimulatorDeletion } }
    var selectedSize: Int64 { items.reduce(0) { $0 + $1.item.size } }
}

struct CleanupItemResult: Identifiable, Codable, Hashable, Sendable {
    var id: String { itemID }
    let itemID: String
    let displayName: String
    let size: Int64
    let succeeded: Bool
    let message: String
}

struct CleanupSessionResult: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let startedAt: Date
    let completedAt: Date
    let results: [CleanupItemResult]

    var succeededItems: [CleanupItemResult] { results.filter(\.succeeded) }
    var failedItems: [CleanupItemResult] { results.filter { !$0.succeeded } }
    var recoveredSize: Int64 { succeededItems.reduce(0) { $0 + $1.size } }
    var hadAnySuccess: Bool { !succeededItems.isEmpty }
}

enum ProEntitlementState: String, Codable, Sendable {
    case unknown
    case free
    case pro
    case revoked
}

struct PurchaseProduct: Sendable {
    let displayName: String
    let description: String
    let displayPrice: String
}

enum PurchaseOutcome: Sendable {
    case purchased
    case pending
    case cancelled
}

struct SimulatorDevice: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let runtime: String
    let state: String
    let dataPath: URL?
    let size: Int64
    let isAvailable: Bool
}

struct SimulatorRuntime: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let version: String
    let isAvailable: Bool
}

struct SimulatorInventory: Codable, Hashable, Sendable {
    let devices: [SimulatorDevice]
    let runtimes: [SimulatorRuntime]
    let deletionIsAvailable: Bool
    let limitation: String?
}

protocol StorageScanner: Sendable {
    var category: StorageCategoryID { get }
    func scan(in context: ScanContext) async throws -> StorageCategorySnapshot
}

@MainActor
protocol AccessAuthorizing {
    func requestDeveloperDirectory() async throws -> AuthorizedRoot
    func requestXcodeCacheDirectory() async throws -> AuthorizedRoot
    func requestAuthorizedFolder(kind: AuthorizedRootKind, preferring expected: URL?) async throws -> AuthorizedRoot
    func restoreAuthorizedRoots() async -> [AuthorizedRoot]
    func forget(_ root: AuthorizedRoot) async
}

protocol CleanupPlanning: Sendable {
    func makePlan(from selection: CleanupSelection, snapshot: ScanSnapshot, roots: [AuthorizedRoot]) throws -> CleanupPlan
}

protocol CleanupExecuting: Sendable {
    func execute(_ plan: CleanupPlan) async -> CleanupSessionResult
}

protocol SimulatorControlling: Sendable {
    func inventory() async throws -> SimulatorInventory
    func deleteDevice(id: String) async throws
}

protocol PurchaseClient: Sendable {
    func loadLifetimeProduct() async throws -> PurchaseProduct
    func purchaseLifetime() async throws -> PurchaseOutcome
    func restore() async throws
    func currentEntitlement() async -> ProEntitlementState
}

