import XCTest
@testable import SessionEngine

final class BufferedReadingTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_000)

    func testGoodReadingKeepsTheOriginalTwoFieldFormat() {
        let reading = BufferedReading(date: start, bpm: 142)
        XCTAssertEqual(reading.line, "1000.0,142\n")
    }

    func testNoContactReadingIsFlagged() {
        let reading = BufferedReading(date: start, bpm: 0, hasContact: false)
        XCTAssertEqual(reading.line, "1000.0,0,nc\n")
    }

    func testRoundTrip() {
        let readings = [BufferedReading(date: start, bpm: 120),
                        BufferedReading(date: start.addingTimeInterval(1.5), bpm: 64, hasContact: false)]
        XCTAssertEqual(BufferedReading.parse(readings.map(\.line).joined()), readings)
    }

    func testReadsFilesWrittenBeforeTheFlag() {
        let readings = BufferedReading.parse("1000.0,120\n1001.0,121\n")
        XCTAssertEqual(readings.map(\.bpm), [120, 121])
        XCTAssertTrue(readings.allSatisfy(\.hasContact))
    }

    func testSkipsMalformedLines() {
        let readings = BufferedReading.parse("1000.0,120\ngarbage\n1001.0\n1002.0,abc\n1003.0,90,xx\n1004.0,91\n")
        XCTAssertEqual(readings.map(\.bpm), [120, 91])
    }

    func testPointsLeaveOutNoContactReadings() {
        let readings = [BufferedReading(date: start, bpm: 120),
                        BufferedReading(date: start.addingTimeInterval(10), bpm: 0, hasContact: false),
                        BufferedReading(date: start.addingTimeInterval(20), bpm: 130)]
        XCTAssertEqual(BufferedReading.points(readings, since: start),
                       [HRPoint(t: 0, bpm: 120), HRPoint(t: 20, bpm: 130)])
    }

    /// A strap that slipped for the last ten minutes still counts as the
    /// session running until it was last heard from.
    func testLastDateIncludesNoContactReadings() {
        let readings = [BufferedReading(date: start, bpm: 120),
                        BufferedReading(date: start.addingTimeInterval(600), bpm: 0, hasContact: false)]
        XCTAssertEqual(BufferedReading.lastDate(readings), start.addingTimeInterval(600))
        XCTAssertNil(BufferedReading.lastDate([]))
    }

    func testJiuJitsuKind() {
        XCTAssertEqual(WorkoutKind(rawValue: "jiujitsu"), .jiujitsu)
        XCTAssertEqual(WorkoutKind.jiujitsu.label, "Jiu-Jitsu")
        // Existing sessions keep decoding.
        XCTAssertEqual(WorkoutKind(rawValue: "wrestling"), .wrestling)
    }
}
