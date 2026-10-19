import XCTest
@testable import SessionEngine

final class WorkoutDuplicateTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Halifax")!
        return calendar
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func testStartKeepsSourceTimeOfDayOnNewDay() {
        let source = date(2026, 9, 26, 18, 30)
        XCTAssertEqual(WorkoutDuplicate.start(on: date(2026, 10, 17, 9, 5), atTimeOf: source, calendar: calendar),
                       date(2026, 10, 17, 18, 30))
    }

    func testDefaultStartIsTodayWhenFinished() {
        let source = date(2026, 9, 26, 7, 0)
        XCTAssertEqual(WorkoutDuplicate.defaultStart(for: source, duration: 3600, now: date(2026, 10, 19, 12, 0),
                                                     calendar: calendar),
                       date(2026, 10, 19, 7, 0))
    }

    func testDefaultStartIsYesterdayWhenTodayWouldEndInFuture() {
        let source = date(2026, 9, 26, 18, 30)
        XCTAssertEqual(WorkoutDuplicate.defaultStart(for: source, duration: 3600, now: date(2026, 10, 19, 19, 0),
                                                     calendar: calendar),
                       date(2026, 10, 18, 18, 30))
    }

    func testShiftedStretchesAndPlacesAtNewStart() {
        let start = date(2026, 10, 17, 18, 30)
        let out = WorkoutDuplicate.shifted([HRPoint(t: 0, bpm: 100), HRPoint(t: 60, bpm: 150)],
                                           sourceDuration: 60, to: start, duration: 120)
        XCTAssertEqual(out.map(\.date), [start, start.addingTimeInterval(120)])
        XCTAssertEqual(out.map(\.bpm), [100, 150])
    }

    func testShiftedSameLengthKeepsOffsets() {
        let start = date(2026, 10, 17)
        let out = WorkoutDuplicate.shifted([HRPoint(t: 30, bpm: 120), HRPoint(t: 10, bpm: 110)],
                                           sourceDuration: 60, to: start, duration: 60)
        XCTAssertEqual(out.map { $0.date.timeIntervalSince(start) }, [10, 30])
    }

    func testOverlappingFindsPartialAndContainedWorkouts() {
        let start = date(2026, 10, 17, 18, 0)
        let existing = [
            DateInterval(start: date(2026, 10, 17, 17, 30), duration: 3600), // ends inside
            DateInterval(start: date(2026, 10, 17, 18, 15), duration: 600),  // inside
            DateInterval(start: date(2026, 10, 17, 16, 0), duration: 3600),  // before
            DateInterval(start: date(2026, 10, 17, 19, 0), duration: 600),   // touches end
            DateInterval(start: date(2026, 10, 17, 17, 0), duration: 3600),  // touches start
            DateInterval(start: date(2026, 10, 17, 17, 0), duration: 3 * 3600), // contains
        ]
        XCTAssertEqual(WorkoutDuplicate.overlapping(start: start, duration: 3600, existing: existing), [0, 1, 5])
    }

    func testOverlappingEmpty() {
        XCTAssertEqual(WorkoutDuplicate.overlapping(start: date(2026, 10, 17), duration: 60, existing: []), [])
    }

    func testScaledEnergy() {
        XCTAssertEqual(WorkoutDuplicate.scaledEnergy(600, from: 3600, to: 5400), 900)
        XCTAssertNil(WorkoutDuplicate.scaledEnergy(nil, from: 3600, to: 3600))
        XCTAssertNil(WorkoutDuplicate.scaledEnergy(0, from: 3600, to: 3600))
        XCTAssertNil(WorkoutDuplicate.scaledEnergy(600, from: 0, to: 3600))
    }

    func testBPMSummary() {
        let summary = WorkoutDuplicate.bpmSummary([HRPoint(t: 0, bpm: 100), HRPoint(t: 1, bpm: 151),
                                                   HRPoint(t: 2, bpm: 120)])
        XCTAssertEqual(summary?.average, 124)
        XCTAssertEqual(summary?.max, 151)
        XCTAssertNil(WorkoutDuplicate.bpmSummary([]))
    }
}
