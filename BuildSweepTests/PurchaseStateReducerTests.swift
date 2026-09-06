import XCTest
@testable import BuildSweep

final class PurchaseStateReducerTests: XCTestCase {
    func testVerifiedPurchaseUnlocksPro() {
        let state = PurchaseStateReducer.reduce(.init(), event: .verifiedPurchase)
        XCTAssertEqual(state.entitlement, .pro)
        XCTAssertNil(state.message)
    }

    func testPendingDoesNotGrantEntitlement() {
        let state = PurchaseStateReducer.reduce(.init(entitlement: .free), event: .pending)
        XCTAssertEqual(state.entitlement, .free)
        XCTAssertTrue(state.isPending)
    }

    func testRevocationRemovesPro() {
        let state = PurchaseStateReducer.reduce(.init(entitlement: .pro), event: .revoked)
        XCTAssertEqual(state.entitlement, .revoked)
    }

    func testUnverifiedAndUnavailableExposeErrors() {
        XCTAssertNotNil(PurchaseStateReducer.reduce(.init(), event: .unverified).message)
        XCTAssertNotNil(PurchaseStateReducer.reduce(.init(), event: .unavailable).message)
    }

    func testRestoreWithoutEntitlementReturnsFree() {
        let state = PurchaseStateReducer.reduce(.init(entitlement: .unknown), event: .restoreWithoutEntitlement)
        XCTAssertEqual(state.entitlement, .free)
    }
}

