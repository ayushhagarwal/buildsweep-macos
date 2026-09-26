import XCTest
@testable import BuildSweep

private final class TrashSpy: TrashRouting, @unchecked Sendable {
    private(set) var urls: [URL] = []
    func moveToTrash(_ url: URL) throws { urls.append(url) }
}

final class CleanupTests: XCTestCase {
    func testPartialSuccessReportsSucceededAndFailedItems() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appending(path: "Xcode/DerivedData/First-hash")
        let missing = root.appending(path: "Xcode/DerivedData/Missing-hash")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        let firstItem = StorageItem(category: .derivedData, kind: .derivedData, displayName: "First", url: first, size: 100, risk: .regenerates, action: .trash)
        let missingItem = StorageItem(category: .derivedData, kind: .derivedData, displayName: "Missing", url: missing, size: 200, risk: .regenerates, action: .trash)
        let plan = CleanupPlan(id: UUID(), createdAt: .now, snapshotGenerationID: UUID(), items: [
            CleanupPlanItem(item: firstItem, authorizedRoot: root, canonicalURLAtPlanning: first.canonicalFileURL, targetIdentity: try CleanupPathPolicy().targetIdentity(of: first)),
            CleanupPlanItem(item: missingItem, authorizedRoot: root, canonicalURLAtPlanning: missing.canonicalFileURL, targetIdentity: nil)
        ])
        let result = await DefaultCleanupExecutor(trashRouter: TrashSpy()).execute(plan)
        XCTAssertEqual(result.succeededItems.count, 1)
        XCTAssertEqual(result.failedItems.count, 1)
        XCTAssertEqual(result.results[0].message, "Moved to Trash")
    }

    func testPlannerRejectsInspectionOnlyItems() throws {
        let item = StorageItem(id: "runtime", category: .simulators, kind: .simulatorRuntime, displayName: "iOS", url: nil, size: 0, risk: .inspectionOnly, action: .inspectionOnly)
        let snapshot = ScanSnapshot(generationID: UUID(), startedAt: .now, completedAt: .now, categories: [.simulators: StorageCategorySnapshot(category: .simulators, items: [item], scannedAt: .now, warnings: [])])
        XCTAssertThrowsError(try DefaultCleanupPlanner().makePlan(from: CleanupSelection(itemIDs: [item.id]), snapshot: snapshot, roots: []))
    }

    func testSuccessfulTrashMoveReportsSuccess() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "Xcode/DerivedData/Atlas-hash")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let item = StorageItem(category: .derivedData, kind: .derivedData, displayName: "Atlas", url: url, size: 100, risk: .regenerates, action: .trash)
        let plan = CleanupPlan(id: UUID(), createdAt: .now, snapshotGenerationID: UUID(), items: [
            CleanupPlanItem(item: item, authorizedRoot: root, canonicalURLAtPlanning: url.canonicalFileURL, targetIdentity: try CleanupPathPolicy().targetIdentity(of: url))
        ])

        let result = await DefaultCleanupExecutor(trashRouter: TrashSpy()).execute(plan)

        XCTAssertEqual(result.succeededItems.count, 1)
        XCTAssertEqual(result.results[0].message, "Moved to Trash")
    }

    func testRejectsTargetReplacedBetweenPlanningAndExecution() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "Xcode/DerivedData/Atlas-hash")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let item = StorageItem(category: .derivedData, kind: .derivedData, displayName: "Atlas", url: url, size: 100, risk: .regenerates, action: .trash)
        let identity = try CleanupPathPolicy().targetIdentity(of: url)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        let trash = TrashSpy()
        let plan = CleanupPlan(id: UUID(), createdAt: .now, snapshotGenerationID: UUID(), items: [
            CleanupPlanItem(item: item, authorizedRoot: root, canonicalURLAtPlanning: url.canonicalFileURL, targetIdentity: identity)
        ])
        let result = await DefaultCleanupExecutor(trashRouter: trash).execute(plan)

        XCTAssertEqual(result.succeededItems.count, 0)
        XCTAssertEqual(result.failedItems.count, 1)
        XCTAssertTrue(result.results[0].message.contains("changed after review"))
        XCTAssertTrue(trash.urls.isEmpty)
    }
}
