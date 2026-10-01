import XCTest
@testable import SessionEngine

final class SparringSummaryTests: XCTestCase {

    private func summary(_ bpms: [(TimeInterval, Int)], timeouts: Int = 0) throws -> SparringSummary {
        let zone = try XCTUnwrap(SparringPrescription().resolve(hrMax: 200))   // ceiling 160
        return SparringSummary(startedAt: Date(), duration: 60,
                               points: bpms.map { HRPoint(t: $0.0, bpm: $0.1) },
                               zone: zone, hrMax: 200, timeoutCount: timeouts)
    }

    func testAverageAndMax() throws {
        let s = try summary([(0, 120), (1, 130), (2, 141)])
        XCTAssertEqual(s.averageBPM, 130)
        XCTAssertEqual(s.maxBPM, 141)
    }

    func testEmptySessionHasNoHeartRateStats() throws {
        let s = try summary([])
        XCTAssertNil(s.averageBPM)
        XCTAssertNil(s.maxBPM)
        XCTAssertEqual(s.secondsOverCeiling, 0)
    }

    func testTimeOverCeilingCountsOnlyReadingsAboveIt() throws {
        // 160 is at the ceiling, not over it.
        let s = try summary([(0, 150), (1, 161), (2, 165), (3, 160), (4, 170)])
        XCTAssertEqual(s.secondsOverCeiling, 2)
    }

    func testDropoutIsCapped() throws {
        let s = try summary([(0, 170), (60, 170)])
        XCTAssertEqual(s.secondsOverCeiling, 5)
    }

    func testCarriesTimeoutCount() throws {
        XCTAssertEqual(try summary([], timeouts: 3).timeoutCount, 3)
    }
}
