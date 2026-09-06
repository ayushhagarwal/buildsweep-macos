import Security
import XCTest
@testable import BuildSweep

private final class TrashSpy: TrashRouting, @unchecked Sendable {
    private(set) var urls: [URL] = []
    func moveToTrash(_ url: URL) throws { urls.append(url) }
}

private actor FreeCleanupSpy: FreeCleanupAccounting {
    var used = 0
    func usedCount() -> Int { used }
    func recordUse() { used += 1 }
}

private actor FailingFreeCleanupSpy: FreeCleanupAccounting {
    func usedCount() -> Int { 0 }
    func recordUse() throws { throw KeychainError.status(errSecInteractionNotAllowed) }
}

final class CleanupTests: XCTestCase {
    func testPartialSuccessConsumesFreeSessionAfterFirstSuccess() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appending(path: "Xcode/DerivedData/First-hash")
        let missing = root.appending(path: "Xcode/DerivedData/Missing-hash")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        let firstItem = StorageItem(category: .derivedData, kind: .derivedData, displayName: "First", url: first, size: 100, risk: .regenerates, action: .trash)
        let missingItem = StorageItem(category: .derivedData, kind: .derivedData, displayName: "Missing", url: missing, size: 200, risk: .regenerates, action: .trash)
        let plan = CleanupPlan(id: UUID(), createdAt: .now, snapshotGenerationID: UUID(), items: [
            CleanupPlanItem(item: firstItem, authorizedRoot: root, canonicalURLAtPlanning: first.canonicalFileURL),
            CleanupPlanItem(item: missingItem, authorizedRoot: root, canonicalURLAtPlanning: missing.canonicalFileURL)
        ])
        let freeStore = FreeCleanupSpy()
        let result = await DefaultCleanupExecutor(trashRouter: TrashSpy(), freeCleanupStore: freeStore).execute(plan)
        XCTAssertEqual(result.succeededItems.count, 1)
        XCTAssertEqual(result.failedItems.count, 1)
        let used = await freeStore.usedCount()
        XCTAssertEqual(used, 1)
    }

    func testPlannerRejectsInspectionOnlyItems() throws {
        let item = StorageItem(id: "runtime", category: .simulators, kind: .simulatorRuntime, displayName: "iOS", url: nil, size: 0, risk: .inspectionOnly, action: .inspectionOnly)
        let snapshot = ScanSnapshot(generationID: UUID(), startedAt: .now, completedAt: .now, categories: [.simulators: StorageCategorySnapshot(category: .simulators, items: [item], scannedAt: .now, warnings: [])])
        XCTAssertThrowsError(try DefaultCleanupPlanner().makePlan(from: CleanupSelection(itemIDs: [item.id]), snapshot: snapshot, roots: []))
    }

    func testSuccessfulTrashMoveIsNotReportedAsFailedWhenAccountingNeedsAttention() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "Xcode/DerivedData/Atlas-hash")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let item = StorageItem(category: .derivedData, kind: .derivedData, displayName: "Atlas", url: url, size: 100, risk: .regenerates, action: .trash)
        let plan = CleanupPlan(id: UUID(), createdAt: .now, snapshotGenerationID: UUID(), items: [
            CleanupPlanItem(item: item, authorizedRoot: root, canonicalURLAtPlanning: url.canonicalFileURL)
        ])

        let result = await DefaultCleanupExecutor(trashRouter: TrashSpy(), freeCleanupStore: FailingFreeCleanupSpy()).execute(plan)

        XCTAssertEqual(result.succeededItems.count, 1)
        XCTAssertTrue(result.results[0].message.contains("marker needs attention"))
    }
}
