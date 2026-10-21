import XCTest
@testable import SessionEngine

final class WorkoutDedupeTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    private let flowBundle = "com.sphericalwave.flow"

    private func interval(_ startMin: Double, _ minutes: Double) -> DateInterval {
        DateInterval(start: t0.addingTimeInterval(startMin * 60), duration: minutes * 60)
    }

    // MARK: - origin

    func testOriginFlowByBundle() {
        XCTAssertEqual(WorkoutDedupe.origin(bundleID: flowBundle, sourceApp: nil, flowBundleID: flowBundle), .flow)
    }

    func testOriginBioMechanicByTag() {
        XCTAssertEqual(WorkoutDedupe.origin(bundleID: "com.example.other", sourceApp: "bioMechanic",
                                            flowBundleID: flowBundle), .bioMechanic)
    }

    func testOriginBioMechanicByWatchBundle() {
        XCTAssertEqual(WorkoutDedupe.origin(bundleID: "com.sphericalwave.fitwrench.torque.watchkitapp",
                                            sourceApp: nil, flowBundleID: flowBundle), .bioMechanic)
    }

    func testOriginOther() {
        XCTAssertEqual(WorkoutDedupe.origin(bundleID: "com.apple.health", sourceApp: nil, flowBundleID: flowBundle),
                       .other)
        XCTAssertEqual(WorkoutDedupe.origin(bundleID: "com.apple.health", sourceApp: "SomethingElse",
                                            flowBundleID: flowBundle), .other)
    }

    // MARK: - kept

    func testBioMechanicOverlappingFlowIsHidden() {
        let kept = WorkoutDedupe.kept([
            (interval(0, 60), .flow),
            (interval(2, 55), .bioMechanic),
        ])
        XCTAssertEqual(kept, [0])
    }

    func testBioMechanicContainingFlowIsHidden() {
        XCTAssertEqual(WorkoutDedupe.kept([(interval(10, 20), .flow), (interval(0, 60), .bioMechanic)]), [0])
    }

    func testBioMechanicAloneIsKept() {
        XCTAssertEqual(WorkoutDedupe.kept([(interval(0, 30), .bioMechanic)]), [0])
    }

    func testBioMechanicNotOverlappingFlowIsKept() {
        let kept = WorkoutDedupe.kept([
            (interval(0, 60), .flow),
            (interval(120, 30), .bioMechanic),
        ])
        XCTAssertEqual(kept, [0, 1])
    }

    func testOverlapOfAMinuteOrLessIsKept() {
        let kept = WorkoutDedupe.kept([
            (interval(0, 60), .flow),
            (interval(59, 30), .bioMechanic),     // exactly 1 min
            (interval(-29.5, 30), .bioMechanic),  // 30 s
        ])
        XCTAssertEqual(kept, [0, 1, 2])
    }

    func testOverlapJustOverAMinuteIsHidden() {
        XCTAssertEqual(WorkoutDedupe.kept([(interval(0, 60), .flow), (interval(58.9, 30), .bioMechanic)]), [0])
    }

    func testTouchingIsKept() {
        XCTAssertEqual(WorkoutDedupe.kept([(interval(0, 60), .flow), (interval(60, 30), .bioMechanic)]), [0, 1])
    }

    func testOtherAppsOverlappingFlowAreKept() {
        let kept = WorkoutDedupe.kept([
            (interval(0, 60), .flow),
            (interval(0, 60), .other),
        ])
        XCTAssertEqual(kept, [0, 1])
    }

    func testBioMechanicOnlyHiddenByFlowNotByOthers() {
        let kept = WorkoutDedupe.kept([
            (interval(0, 60), .other),
            (interval(0, 60), .bioMechanic),
        ])
        XCTAssertEqual(kept, [0, 1])
    }

    func testFlowNeverHidden() {
        let kept = WorkoutDedupe.kept([
            (interval(0, 60), .flow),
            (interval(0, 60), .flow),
            (interval(0, 60), .bioMechanic),
        ])
        XCTAssertEqual(kept, [0, 1])
    }

    func testOrderPreservedWithMixedList() {
        let kept = WorkoutDedupe.kept([
            (interval(200, 30), .bioMechanic), // newest, alone
            (interval(100, 60), .bioMechanic), // shadows flow below
            (interval(100, 60), .flow),
            (interval(0, 30), .other),
        ])
        XCTAssertEqual(kept, [0, 2, 3])
    }

    func testEmpty() {
        XCTAssertEqual(WorkoutDedupe.kept([]), [])
    }
}
