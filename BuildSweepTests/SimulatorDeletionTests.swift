import XCTest
@testable import BuildSweep

final class SimulatorDeletionTests: XCTestCase {
    private let deviceUDID = "A1B2C3D4-E5F6-7890-ABCD-EF1234567890"

    func testRejectsBroadAndNonDeviceTargets() {
        for target in ["all", "ALL", "unavailable", "Unavailable", "", "iPhone 16", "\(deviceUDID),\(deviceUDID)", "com.apple.CoreSimulator.SimRuntime.iOS-18-0"] {
            XCTAssertThrowsError(try SimulatorDeviceIDPolicy.validate(target), target) { error in
                let controllerError = error as? SimulatorControllerError
                XCTAssertTrue(
                    controllerError == .broadDeletionTarget || controllerError == .invalidDeviceID,
                    "\(target) produced \(String(describing: error))"
                )
            }
        }
    }

    func testRejectsBroadTargetsEvenWhenListed() {
        XCTAssertThrowsError(try SimulatorDeviceIDPolicy.confirm("all", listedDeviceIDs: ["all"])) { error in
            XCTAssertEqual(error as? SimulatorControllerError, .broadDeletionTarget)
        }
        XCTAssertThrowsError(try SimulatorDeviceIDPolicy.confirm("unavailable", listedDeviceIDs: ["unavailable", deviceUDID])) { error in
            XCTAssertEqual(error as? SimulatorControllerError, .broadDeletionTarget)
        }
    }

    func testConfirmRequiresTheUDIDInAFreshInventory() throws {
        XCTAssertEqual(try SimulatorDeviceIDPolicy.confirm(deviceUDID.lowercased(), listedDeviceIDs: [deviceUDID]), deviceUDID.lowercased())
        XCTAssertThrowsError(try SimulatorDeviceIDPolicy.confirm(deviceUDID, listedDeviceIDs: [])) { error in
            XCTAssertEqual(error as? SimulatorControllerError, .deviceNotInInventory)
        }
    }

    func testPlannerRejectsPermanentDeletionOfNonDevicesAndBroadIDs() {
        let runtime = StorageItem(id: "com.apple.CoreSimulator.SimRuntime.iOS-18-0", category: .simulators, kind: .simulatorRuntime, displayName: "iOS", url: nil, size: 0, risk: .inspectionOnly, action: .permanentSimulatorDeletion)
        let broad = StorageItem(id: "all", category: .simulators, kind: .simulatorDevice, displayName: "All", url: nil, size: 0, risk: .reviewFirst, action: .permanentSimulatorDeletion)
        let device = StorageItem(id: deviceUDID, category: .simulators, kind: .simulatorDevice, displayName: "iPhone", url: nil, size: 0, risk: .reviewFirst, action: .permanentSimulatorDeletion)

        XCTAssertThrowsError(try plan(runtime))
        XCTAssertThrowsError(try plan(broad)) { error in
            XCTAssertEqual(error as? SimulatorControllerError, .broadDeletionTarget)
        }
        XCTAssertThrowsError(try plan(device)) { error in
            XCTAssertEqual(error as? CleanupPolicyError, .inspectionOnly("iPhone"))
        }
    }

    func testDeleteDeviceRejectsBroadTargetsWhileDeletionStaysDisabled() async {
        let controller = SimctlController()
        do {
            try await controller.deleteDevice(id: "all")
            XCTFail("Expected broad deletion to be rejected")
        } catch let error as SimulatorControllerError {
            XCTAssertEqual(error, .broadDeletionTarget)
        } catch {
            XCTFail("Unexpected error \(error)")
        }
        XCTAssertFalse(SimulatorFeaturePolicy.deletionEnabled)
    }

    private func plan(_ item: StorageItem) throws -> CleanupPlan {
        let root = AuthorizedRoot(id: UUID(), kind: .developerDirectory, url: URL(fileURLWithPath: "/tmp"), bookmark: Data(), grantedAt: .now)
        let snapshot = ScanSnapshot(generationID: UUID(), startedAt: .now, completedAt: .now, categories: [
            .simulators: StorageCategorySnapshot(category: .simulators, items: [item], scannedAt: .now, warnings: [])
        ])
        return try DefaultCleanupPlanner().makePlan(from: CleanupSelection(itemIDs: [item.id]), snapshot: snapshot, roots: [root])
    }
}
