import XCTest
@testable import SessionEngine

final class TrainingSummaryTests: XCTestCase {

    private func summary(_ bpms: [(TimeInterval, Int)],
                         rounds: [SparringRound] = [],
                         profile: CalorieProfile? = nil) -> TrainingSummary {
        TrainingSummary(startedAt: Date(), duration: 60, kind: .jiujitsu, hrMax: 200,
                        points: bpms.map { HRPoint(t: $0.0, bpm: $0.1) },
                        rounds: rounds, profile: profile)
    }

    private func round(_ start: TimeInterval, _ end: TimeInterval, ceiling: Int = 160, timeouts: Int = 0) -> SparringRound {
        SparringRound(start: start, end: end, ceilingBPM: ceiling, resetBPM: 140, timeoutCount: timeouts)
    }

    func testAverageAndMax() {
        let s = summary([(0, 120), (1, 130), (2, 141)])
        XCTAssertEqual(s.averageBPM, 130)
        XCTAssertEqual(s.maxBPM, 141)
    }

    func testEmptySessionHasNoHeartRateStats() {
        let s = summary([])
        XCTAssertNil(s.averageBPM)
        XCTAssertNil(s.maxBPM)
        XCTAssertEqual(s.secondsOverCeiling, 0)
    }

    func testTimeOverCeilingCountsOnlyInsideRounds() {
        // 160 is at the ceiling, not over it. The 170s outside the round don't count.
        let s = summary([(0, 170), (1, 170), (2, 150), (3, 161), (4, 165), (5, 160), (6, 170), (7, 170)],
                        rounds: [round(2, 6)])
        XCTAssertEqual(s.secondsOverCeiling, 2)
    }

    func testEachRoundUsesItsOwnCeiling() {
        let s = summary([(0, 150), (1, 150), (2, 150), (3, 150)],
                        rounds: [round(0, 1, ceiling: 140), round(2, 3, ceiling: 160)])
        XCTAssertEqual(s.secondsOverCeiling, 1)
    }

    func testDropoutIsCapped() {
        let s = summary([(0, 170), (60, 170)], rounds: [round(0, 60)])
        XCTAssertEqual(s.secondsOverCeiling, HRPoint.maxGap)
    }

    func testRoundTotals() {
        let s = summary([], rounds: [round(0, 30, timeouts: 2), round(100, 160, timeouts: 1)])
        XCTAssertEqual(s.timeoutCount, 3)
        XCTAssertEqual(s.sparringSeconds, 90)
    }

    func testNoProfileMeansNoCalories() {
        let s = summary([(0, 150), (1, 150)])
        XCTAssertNil(s.activeCalories)
        XCTAssertTrue(s.energy.isEmpty)
    }

    func testCaloriesSumEnergyIntervals() throws {
        let profile = CalorieProfile(sex: .male, weightKg: 80, age: 35)
        let s = summary((0..<120).map { (TimeInterval($0), 150) }, profile: profile)
        let total = try XCTUnwrap(s.activeCalories)
        XCTAssertEqual(total, s.energy.reduce(0) { $0 + $1.kcal }, accuracy: 1e-9)
        XCTAssertGreaterThan(total, 0)
    }
}
