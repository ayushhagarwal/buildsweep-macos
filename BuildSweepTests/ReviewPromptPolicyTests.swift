import XCTest
@testable import BuildSweep

final class ReviewPromptPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private var eligible: ReviewPromptPolicy.State {
        ReviewPromptPolicy.State(launches: 3, successfulCleanups: 2, recoveredBytes: 1_000_000_000)
    }

    func testEligibleAtOneGigabyteMilestone() {
        XCTAssertTrue(ReviewPromptPolicy.isEligible(state: eligible, version: "1.0", now: now))
    }

    func testRejectsBelowRecoveredByteFloor() {
        var short = eligible
        short.recoveredBytes = 999_999_999
        XCTAssertFalse(ReviewPromptPolicy.isEligible(state: short, version: "1.0", now: now))
    }

    func testRejectsInsufficientLaunchesOrCleanups() {
        var fewLaunches = eligible
        fewLaunches.launches = 2
        XCTAssertFalse(ReviewPromptPolicy.isEligible(state: fewLaunches, version: "1.0", now: now))

        var fewCleanups = eligible
        fewCleanups.successfulCleanups = 1
        XCTAssertFalse(ReviewPromptPolicy.isEligible(state: fewCleanups, version: "1.0", now: now))
    }

    func testCooldownBlocksUntilOneHundredFiftyDays() {
        var cooling = eligible
        cooling.lastAttemptDate = now.addingTimeInterval(-149 * 24 * 60 * 60)
        cooling.attemptedVersion = "1.0"
        XCTAssertFalse(ReviewPromptPolicy.isEligible(state: cooling, version: "1.1", now: now))

        cooling.lastAttemptDate = now.addingTimeInterval(-150 * 24 * 60 * 60)
        XCTAssertTrue(ReviewPromptPolicy.isEligible(state: cooling, version: "1.1", now: now))
    }

    func testSameVersionIsBlockedEvenAfterCooldown() {
        var sameVersion = eligible
        sameVersion.attemptedVersion = "1.0"
        sameVersion.lastAttemptDate = now.addingTimeInterval(-200 * 24 * 60 * 60)
        XCTAssertFalse(ReviewPromptPolicy.isEligible(state: sameVersion, version: "1.0", now: now))
    }

    func testRejectsPaywallAdjacentMoment() {
        XCTAssertFalse(ReviewPromptPolicy.isEligible(state: eligible, version: "1.0", now: now, adjacentPaywall: true))
    }
}
