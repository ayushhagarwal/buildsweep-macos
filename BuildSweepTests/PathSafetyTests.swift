import XCTest
@testable import BuildSweep

final class PathSafetyTests: XCTestCase {
    private var fixtureRoot: URL!

    override func setUpWithError() throws {
        fixtureRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: fixtureRoot.appending(path: "Xcode/DerivedData/Atlas-hash"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fixtureRoot)
    }

    func testAllowsExactDerivedDataChild() throws {
        let url = fixtureRoot.appending(path: "Xcode/DerivedData/Atlas-hash")
        let item = StorageItem(category: .derivedData, kind: .derivedData, displayName: "Atlas", url: url, size: 10, risk: .regenerates, action: .trash)
        XCTAssertEqual(try CleanupPathPolicy().validate(item, inside: fixtureRoot), url.canonicalFileURL)
    }

    func testRealUserHomeIsNotSandboxContainer() {
        XCTAssertFalse(RealUserHome.directory.path.contains("/Library/Containers/"))
        XCTAssertEqual(RealUserHome.developerDirectory.lastPathComponent, "Developer")
        XCTAssertEqual(RealUserHome.developerDirectory.deletingLastPathComponent().lastPathComponent, "Library")
        XCTAssertEqual(RealUserHome.cursorHomeDirectory.lastPathComponent, ".cursor")
        XCTAssertEqual(RealUserHome.codexHomeDirectory.lastPathComponent, ".codex")
        XCTAssertEqual(RealUserHome.claudeHomeDirectory.lastPathComponent, ".claude")
    }

    func testBlocksBroadDeveloperRoot() throws {
        let homeDeveloper = RealUserHome.developerDirectory
        let item = StorageItem(category: .derivedData, kind: .derivedData, displayName: "Developer", url: homeDeveloper, size: 10, risk: .regenerates, action: .trash)
        XCTAssertThrowsError(try CleanupPathPolicy().validate(item, inside: homeDeveloper))
    }

    func testBlocksSourceProjectEvenInsideAuthorizedRoot() throws {
        let url = fixtureRoot.appending(path: "Xcode/DerivedData/Project.xcodeproj")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let item = StorageItem(category: .derivedData, kind: .derivedData, displayName: "Project", url: url, size: 10, risk: .regenerates, action: .trash)
        XCTAssertThrowsError(try CleanupPathPolicy().validate(item, inside: fixtureRoot))
    }

    func testBlocksSymlinkEscape() throws {
        let link = fixtureRoot.appending(path: "Xcode/DerivedData/Escape-hash")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: FileManager.default.homeDirectoryForCurrentUser)
        let item = StorageItem(category: .derivedData, kind: .derivedData, displayName: "Escape", url: link, size: 10, risk: .regenerates, action: .trash)
        XCTAssertThrowsError(try CleanupPathPolicy().validate(item, inside: fixtureRoot))
    }

    func testAllowsOnlyExactDeviceSupportChildren() throws {
        let valid = fixtureRoot.appending(path: "Xcode/iOS DeviceSupport/26.0")
        try FileManager.default.createDirectory(at: valid, withIntermediateDirectories: true)
        let validItem = StorageItem(category: .deviceSupport, kind: .deviceSupport, displayName: "26.0", url: valid, size: 10, risk: .reviewFirst, action: .trash)
        XCTAssertNoThrow(try CleanupPathPolicy().validate(validItem, inside: fixtureRoot))

        let forged = fixtureRoot.appending(path: "Other/DeviceSupport/26.0")
        try FileManager.default.createDirectory(at: forged, withIntermediateDirectories: true)
        let forgedItem = StorageItem(category: .deviceSupport, kind: .deviceSupport, displayName: "26.0", url: forged, size: 10, risk: .reviewFirst, action: .trash)
        XCTAssertThrowsError(try CleanupPathPolicy().validate(forgedItem, inside: fixtureRoot))
    }

    func testXcodeCacheAllowsKnownDirectChildrenAndBlocksUnknownOnes() throws {
        let cacheRoot = fixtureRoot.appending(path: "Cache")
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        let known = cacheRoot.appending(path: "Cache.db")
        let unknown = cacheRoot.appending(path: "FutureUnknown")
        XCTAssertTrue(FileManager.default.createFile(atPath: known.path, contents: Data()))
        try FileManager.default.createDirectory(at: unknown, withIntermediateDirectories: true)

        let knownItem = StorageItem(category: .cachesAndLogs, kind: .xcodeCache, displayName: "Cache.db", url: known, size: 10, risk: .regenerates, action: .trash)
        let unknownItem = StorageItem(category: .cachesAndLogs, kind: .xcodeCache, displayName: "FutureUnknown", url: unknown, size: 10, risk: .regenerates, action: .trash)
        XCTAssertNoThrow(try CleanupPathPolicy().validate(knownItem, inside: cacheRoot))
        XCTAssertThrowsError(try CleanupPathPolicy().validate(unknownItem, inside: cacheRoot))
    }

    func testAllowsCursorCacheChild() throws {
        let root = fixtureRoot.appending(path: "Cursor")
        let url = root.appending(path: "Cache")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let item = StorageItem(category: .aiTools, kind: .cursorCache, displayName: "Cursor Cache", url: url, size: 10, risk: .regenerates, action: .trash)
        XCTAssertEqual(try CleanupPathPolicy().validate(item, inside: root), url.canonicalFileURL)
    }

    func testBlocksCursorSkills() throws {
        let root = fixtureRoot.appending(path: ".cursor")
        let url = root.appending(path: "skills")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let item = StorageItem(category: .aiTools, kind: .cursorCache, displayName: "skills", url: url, size: 10, risk: .regenerates, action: .trash)
        XCTAssertThrowsError(try CleanupPathPolicy().validate(item, inside: root))
    }

    func testBlocksCodexAuthJSON() throws {
        let root = fixtureRoot.appending(path: ".codex")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appending(path: "auth.json")
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data()))
        let item = StorageItem(category: .aiTools, kind: .codexCache, displayName: "auth.json", url: url, size: 10, risk: .regenerates, action: .trash)
        XCTAssertThrowsError(try CleanupPathPolicy().validate(item, inside: root))
    }

    func testBlocksClaudeSessions() throws {
        let root = fixtureRoot.appending(path: ".claude")
        let url = root.appending(path: "sessions")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let item = StorageItem(category: .aiTools, kind: .claudeCache, displayName: "sessions", url: url, size: 10, risk: .regenerates, action: .trash)
        XCTAssertThrowsError(try CleanupPathPolicy().validate(item, inside: root))
    }

    func testBlocksDeletingCursorHome() throws {
        let root = fixtureRoot.appending(path: ".cursor")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let item = StorageItem(category: .aiTools, kind: .cursorCache, displayName: ".cursor", url: root, size: 10, risk: .regenerates, action: .trash)
        XCTAssertThrowsError(try CleanupPathPolicy().validate(item, inside: root))
        XCTAssertThrowsError(try CleanupPathPolicy().validate(
            StorageItem(category: .aiTools, kind: .cursorCache, displayName: "Cursor home", url: RealUserHome.cursorHomeDirectory, size: 10, risk: .regenerates, action: .trash),
            inside: RealUserHome.cursorHomeDirectory
        ))
    }

    func testPlannerMapsCursorCacheToCursorRoot() throws {
        let root = fixtureRoot.appending(path: "Cursor")
        let url = root.appending(path: "Cache")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let item = StorageItem(category: .aiTools, kind: .cursorCache, displayName: "Cursor Cache", url: url, size: 10, risk: .regenerates, action: .trash)
        let snapshot = ScanSnapshot(
            generationID: UUID(),
            startedAt: .now,
            completedAt: .now,
            categories: [.aiTools: StorageCategorySnapshot(category: .aiTools, items: [item], scannedAt: .now, warnings: [])]
        )
        let authorized = AuthorizedRoot(id: UUID(), kind: .cursorSupport, url: root, bookmark: Data(), grantedAt: .now)
        let plan = try DefaultCleanupPlanner().makePlan(from: CleanupSelection(itemIDs: [item.id]), snapshot: snapshot, roots: [authorized])
        XCTAssertEqual(plan.items.first?.authorizedRoot.canonicalFileURL, root.canonicalFileURL)
    }

    func testPackageCachePolicyAllowsOnlyEachExactCacheRoot() throws {
        let home = fixtureRoot.appending(path: "fixture-home", directoryHint: .isDirectory)
        let policy = CleanupPathPolicy(developerHome: home)

        for group in DeveloperCacheGroup.allCases {
            let cache = group.url(home: home)
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            let item = StorageItem(
                category: .developerCaches,
                kind: .packageManagerCache,
                displayName: "\(group.title) cache",
                url: cache,
                size: 1,
                risk: .redownloads,
                action: .trash
            )
            XCTAssertEqual(try policy.validate(item, inside: cache), cache.canonicalFileURL, "\(group.title) cache should be allowlisted")
        }

        let parent = DeveloperCacheGroup.npm.url(home: home).deletingLastPathComponent()
        let forgedItem = StorageItem(
            category: .developerCaches,
            kind: .packageManagerCache,
            displayName: "npm parent",
            url: parent,
            size: 1,
            risk: .redownloads,
            action: .trash
        )
        XCTAssertThrowsError(try policy.validate(forgedItem, inside: parent))
    }
}
