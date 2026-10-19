import XCTest
@testable import SessionEngine

final class HeartRateStatsTests: XCTestCase {

    private func points(_ pairs: [(TimeInterval, Int)]) -> [HRPoint] {
        pairs.map { HRPoint(t: $0.0, bpm: $0.1) }
    }

    private let round = SparringRound(start: 0, end: 10, ceilingBPM: 160, resetBPM: 140, timeoutCount: 0)

    func testStatsMatchEndOfSessionSummary() throws {
        let readings = points([(0, 150), (1, 170), (2, 165), (3, 140)])
        let stats = try XCTUnwrap(HeartRateStats(points: readings, rounds: [round]))
        let summary = TrainingSummary(startedAt: Date(), duration: 60, kind: .wrestling, hrMax: 200,
                                      points: readings, rounds: [round], profile: nil)
        XCTAssertEqual(stats.averageBPM, summary.averageBPM)
        XCTAssertEqual(stats.maxBPM, summary.maxBPM)
        XCTAssertEqual(stats.secondsOverCeiling, summary.secondsOverCeiling)
        XCTAssertEqual(stats, HeartRateStats(averageBPM: 156, maxBPM: 170, secondsOverCeiling: 2))
    }

    func testCopiedReadingsChangeTheNumbers() throws {
        // Strap dropped after 1 s; the copy fills the rest, hotter.
        let recorded = points([(0, 120), (1, 124)])
        let copied = points([(5, 170), (6, 180), (7, 150)])
        let before = try XCTUnwrap(HeartRateStats(points: recorded, rounds: [round]))
        let after = try XCTUnwrap(HeartRateStats(points: recorded + copied, rounds: [round]))
        XCTAssertEqual(before, HeartRateStats(averageBPM: 122, maxBPM: 124, secondsOverCeiling: 0))
        XCTAssertEqual(after, HeartRateStats(averageBPM: 149, maxBPM: 180, secondsOverCeiling: 2))
    }

    func testUnsortedReadingsAreSortedFirst() {
        let sorted = HeartRateStats(points: points([(0, 170), (1, 170), (2, 150)]), rounds: [round])
        let shuffled = HeartRateStats(points: points([(2, 150), (0, 170), (1, 170)]), rounds: [round])
        XCTAssertEqual(sorted, shuffled)
    }

    func testNoReadingsLeavesStoredNumbersAlone() {
        XCTAssertNil(HeartRateStats(points: [], rounds: [round]))
    }

    func testUndoRestoresOriginalWhenNoCopyRemains() {
        let original = HeartRateStats(averageBPM: 131, maxBPM: 177, secondsOverCeiling: 42)
        let out = HeartRateCopy.statsAfterUndo(remaining: points([(0, 100)]), rounds: [],
                                               original: original, copiesRemain: false)
        XCTAssertEqual(out, original)
    }

    func testUndoRecomputesWhileAnotherCopyRemains() {
        let original = HeartRateStats(averageBPM: 131, maxBPM: 177, secondsOverCeiling: 42)
        let out = HeartRateCopy.statsAfterUndo(remaining: points([(0, 100), (1, 110)]), rounds: [],
                                               original: original, copiesRemain: true)
        XCTAssertEqual(out, HeartRateStats(averageBPM: 105, maxBPM: 110, secondsOverCeiling: 0))
    }

    func testUndoWithoutBackupRecomputesFromRemaining() {
        let out = HeartRateCopy.statsAfterUndo(remaining: points([(0, 100), (1, 110)]), rounds: [],
                                               original: nil, copiesRemain: false)
        XCTAssertEqual(out, HeartRateStats(averageBPM: 105, maxBPM: 110, secondsOverCeiling: 0))
    }

    func testUndoWithNothingLeftAndNoBackupKeepsStored() {
        XCTAssertNil(HeartRateCopy.statsAfterUndo(remaining: [], rounds: [], original: nil, copiesRemain: false))
    }

    func testStatsRoundTripThroughJSON() throws {
        let stats = HeartRateStats(averageBPM: nil, maxBPM: 150, secondsOverCeiling: 3.5)
        let data = try JSONEncoder().encode(stats)
        XCTAssertEqual(try JSONDecoder().decode(HeartRateStats.self, from: data), stats)
    }
}
