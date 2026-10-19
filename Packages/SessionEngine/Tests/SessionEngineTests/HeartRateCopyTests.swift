import XCTest
@testable import SessionEngine

final class HeartRateCopyTests: XCTestCase {

    private func points(_ pairs: [(TimeInterval, Int)]) -> [HRPoint] {
        pairs.map { HRPoint(t: $0.0, bpm: $0.1) }
    }

    func testScaledStretchesOntoLongerTarget() {
        let out = HeartRateCopy.scaled(points([(0, 100), (30, 150), (60, 120)]), from: 60, to: 90)
        XCTAssertEqual(out, points([(0, 100), (45, 150), (90, 120)]))
    }

    func testScaledSqueezesAndDropsReadingsOutsideSource() {
        let out = HeartRateCopy.scaled(points([(-5, 90), (40, 140), (20, 130), (80, 110)]), from: 40, to: 20)
        XCTAssertEqual(out, points([(10, 130), (20, 140)]))
    }

    func testScaledEmptyForZeroDurations() {
        XCTAssertEqual(HeartRateCopy.scaled(points([(0, 100)]), from: 0, to: 60), [])
        XCTAssertEqual(HeartRateCopy.scaled(points([(0, 100)]), from: 60, to: 0), [])
    }

    func testFillingGapsKeepsEverythingWithoutRealReadings() {
        let copied = points([(0, 100), (10, 110)])
        XCTAssertEqual(HeartRateCopy.fillingGaps(copied, around: []), copied)
    }

    func testFillingGapsDropsCopiesNearRealReadings() {
        let copied = points([(0, 100), (10, 110), (20, 120), (40, 130), (60, 140)])
        // Real readings at 18 and 21: copies at 10 and 20 are within 10 s and dropped.
        let out = HeartRateCopy.fillingGaps(copied, around: [21, 18], window: 10)
        XCTAssertEqual(out, points([(0, 100), (40, 130), (60, 140)]))
    }

    func testSameKindBeatsCloserLength() {
        let same = HeartRateCopy.score(sameKind: true, sourceDuration: 90 * 60, targetDuration: 60 * 60, daysApart: 7)
        let other = HeartRateCopy.score(sameKind: false, sourceDuration: 60 * 60, targetDuration: 60 * 60, daysApart: 7)
        XCTAssertLessThan(same, other)
    }

    func testCloserLengthWinsWithinKind() {
        let near = HeartRateCopy.score(sameKind: true, sourceDuration: 65 * 60, targetDuration: 60 * 60, daysApart: 30)
        let far = HeartRateCopy.score(sameKind: true, sourceDuration: 90 * 60, targetDuration: 60 * 60, daysApart: 7)
        XCTAssertLessThan(near, far)
    }

    func testSimilarNeedsSameKindAndComparableLength() {
        XCTAssertTrue(HeartRateCopy.isSimilar(sameKind: true, sourceDuration: 100, targetDuration: 60))
        XCTAssertFalse(HeartRateCopy.isSimilar(sameKind: true, sourceDuration: 130, targetDuration: 60))
        XCTAssertFalse(HeartRateCopy.isSimilar(sameKind: false, sourceDuration: 60, targetDuration: 60))
    }
}
