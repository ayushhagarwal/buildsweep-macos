import XCTest
@testable import BuildSweep

final class ScannerTests: XCTestCase {
    func testDerivedDataMetadataParsing() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let itemRoot = root.appending(path: "Xcode/DerivedData/Atlas-abcdef")
        try FileManager.default.createDirectory(at: itemRoot, withIntermediateDirectories: true)
        let info: NSDictionary = ["WorkspacePath": "/Projects/Atlas.xcworkspace", "LastAccessedDate": Date(timeIntervalSince1970: 100)]
        XCTAssertTrue(info.write(to: itemRoot.appending(path: "info.plist"), atomically: true))
        try Data(repeating: 1, count: 4096).write(to: itemRoot.appending(path: "object.o"))

        let context = ScanContext(developerRoot: root, xcodeCacheRoot: nil, generationID: UUID(), xcodeIsRunning: false)
        let snapshot = try await XcodeStorageScanner(category: .derivedData).scan(in: context)

        XCTAssertEqual(snapshot.items.count, 1)
        XCTAssertEqual(snapshot.items.first?.displayName, "Atlas")
        XCTAssertEqual(snapshot.items.first?.risk, .regenerates)
        XCTAssertEqual(snapshot.items.first?.isDefaultSelected, false)
    }

    func testArchiveParsingPreservesImportantRisk() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = root.appending(path: "Xcode/Archives/2026-08-08/Atlas.xcarchive")
        try FileManager.default.createDirectory(at: archive.appending(path: "dSYMs/Atlas.app.dSYM"), withIntermediateDirectories: true)
        let info: NSDictionary = [
            "Name": "Atlas",
            "ApplicationProperties": [
                "CFBundleShortVersionString": "2.4", "CFBundleVersion": "118",
                "CFBundleIdentifier": "com.example.atlas", "SigningIdentity": "Apple Distribution"
            ]
        ]
        XCTAssertTrue(info.write(to: archive.appending(path: "Info.plist"), atomically: true))

        let context = ScanContext(developerRoot: root, xcodeCacheRoot: nil, generationID: UUID(), xcodeIsRunning: false)
        let snapshot = try await XcodeStorageScanner(category: .archives).scan(in: context)
        XCTAssertEqual(snapshot.items.first?.displayName, "Atlas 2.4 (118)")
        XCTAssertEqual(snapshot.items.first?.risk, .important)
        XCTAssertEqual(snapshot.items.first?.metadata["dSYM"], "Included")
        XCTAssertFalse(snapshot.items.first?.isDefaultSelected ?? true)
    }

    func testAllocatedSizeIncludesHiddenAndPackageContents() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let package = root.appending(path: "Fixture.app/Contents")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 4096).write(to: package.appending(path: "binary"))
        try Data(repeating: 2, count: 4096).write(to: root.appending(path: ".hidden"))

        let size = try await DirectorySizer().allocatedSize(of: root)

        XCTAssertGreaterThanOrEqual(size, 8192)
    }

    func testAIToolScannerListsAllowlistedFoldersOnly() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appending(path: "Cursor")
        try FileManager.default.createDirectory(at: support.appending(path: "Cache"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: support.appending(path: "skills"), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 4096).write(to: support.appending(path: "Cache/blob"))

        let context = ScanContext(
            developerRoot: root,
            generationID: UUID(),
            xcodeIsRunning: false,
            cursorSupportRoot: support
        )
        let snapshot = try await AIToolStorageScanner().scan(in: context)
        XCTAssertEqual(snapshot.items.map(\.displayName), ["Cursor Cache"])
        XCTAssertEqual(snapshot.items.first?.kind, .cursorCache)
        XCTAssertEqual(snapshot.items.first?.risk, .regenerates)
        XCTAssertFalse(snapshot.items.first?.isDefaultSelected ?? true)
        XCTAssertFalse(snapshot.items.contains { $0.displayName.contains("skills") })
    }

    func testAIToolScannerSkipsDefaultSelectionWhenToolIsRunning() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appending(path: ".codex")
        try FileManager.default.createDirectory(at: home.appending(path: "cache"), withIntermediateDirectories: true)

        let context = ScanContext(
            developerRoot: root,
            generationID: UUID(),
            xcodeIsRunning: false,
            codexHomeRoot: home,
            codexIsRunning: true
        )
        let snapshot = try await AIToolStorageScanner().scan(in: context)
        XCTAssertEqual(snapshot.items.count, 1)
        XCTAssertFalse(snapshot.items.first?.isDefaultSelected ?? true)
        XCTAssertFalse(snapshot.warnings.isEmpty)
    }

    func testPackageCacheScannerIncludesOnlyIndividuallyAuthorizedLocation() async throws {
        let fixture = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let home = fixture.appending(path: "home", directoryHint: .isDirectory)
        let npmCache = DeveloperCacheGroup.npm.url(home: home)
        let yarnCache = DeveloperCacheGroup.yarn.url(home: home)
        try FileManager.default.createDirectory(at: npmCache, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: yarnCache, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 4096).write(to: npmCache.appending(path: "content.bin"))
        try Data(repeating: 2, count: 4096).write(to: yarnCache.appending(path: "content.bin"))

        let context = ScanContext(
            developerRoot: fixture,
            generationID: UUID(),
            xcodeIsRunning: false,
            developerPackageCacheRoots: [npmCache]
        )
        let snapshot = try await XcodeStorageScanner(category: .developerCaches, developerHome: home).scan(in: context)

        XCTAssertEqual(snapshot.items.map(\.displayName), ["npm cache"])
        XCTAssertEqual(snapshot.items.first?.url?.canonicalFileURL, npmCache.canonicalFileURL)
        XCTAssertEqual(snapshot.items.first?.risk, .redownloads)
        XCTAssertFalse(snapshot.items.first?.isDefaultSelected ?? true)
    }
}
