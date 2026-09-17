import XCTest
@testable import SessionEngine

final class HRZoneTests: XCTestCase {

    func testZoneBoundaries() {
        XCTAssertEqual(HRZone.zone(forPercent: 0), .z0)
        XCTAssertEqual(HRZone.zone(forPercent: 49.9), .z0)
        XCTAssertEqual(HRZone.zone(forPercent: 50), .z1)
        XCTAssertEqual(HRZone.zone(forPercent: 59.9), .z1)
        XCTAssertEqual(HRZone.zone(forPercent: 60), .z2)
        XCTAssertEqual(HRZone.zone(forPercent: 69.9), .z2)
        XCTAssertEqual(HRZone.zone(forPercent: 70), .z3)
        XCTAssertEqual(HRZone.zone(forPercent: 79.9), .z3)
        XCTAssertEqual(HRZone.zone(forPercent: 80), .z4)
        XCTAssertEqual(HRZone.zone(forPercent: 89.9), .z4)
        XCTAssertEqual(HRZone.zone(forPercent: 90), .z5)
        XCTAssertEqual(HRZone.zone(forPercent: 150), .z5)
    }

    func testZoneDistributionAttributesTimeToEarlierSample() {
        let now = Date()
        let samples: [(date: Date, bpm: Int)] = [
            (now, 100),
            (now.addingTimeInterval(10), 150),
        ]
        let dist = ZoneBucketer.distribution(samples: samples, hrMax: 200)
        // 100/200 = 50% -> z1, for the full 10s gap
        XCTAssertEqual(dist[.z1], 10)
        XCTAssertNil(dist[.z4])
    }

    func testZoneDistributionCapsLargeGaps() {
        let now = Date()
        let samples: [(date: Date, bpm: Int)] = [
            (now, 100),
            (now.addingTimeInterval(120), 150),
        ]
        let dist = ZoneBucketer.distribution(samples: samples, hrMax: 200, maxGap: 30)
        XCTAssertEqual(dist[.z1], 30)
    }

    func testZoneDistributionSortsUnorderedInput() {
        let now = Date()
        let samples: [(date: Date, bpm: Int)] = [
            (now.addingTimeInterval(10), 150),
            (now, 100),
        ]
        let dist = ZoneBucketer.distribution(samples: samples, hrMax: 200)
        XCTAssertEqual(dist[.z1], 10)
    }

    func testZoneDistributionEmptyForBadInput() {
        XCTAssertTrue(ZoneBucketer.distribution(samples: [], hrMax: 200).isEmpty)
        XCTAssertTrue(ZoneBucketer.distribution(samples: [(Date(), 100)], hrMax: 200).isEmpty)
        XCTAssertTrue(ZoneBucketer.distribution(samples: [(Date(), 100), (Date(), 120)], hrMax: 0).isEmpty)
    }
}
