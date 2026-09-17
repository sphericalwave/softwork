//
//  flowTests.swift
//  flowTests
//
//  Pure-logic tests: HR zone boundaries, time-in-zone bucketing, HR-max resolver.
//

import XCTest
@testable import flow

final class flowTests: XCTestCase {

    // MARK: - HRZone boundaries

    func testZoneBoundaries() {
        XCTAssertEqual(HRZone.zone(forPercent: 40), .z1)   // sub-rest reads as Z1
        XCTAssertEqual(HRZone.zone(forPercent: 55), .z1)
        XCTAssertEqual(HRZone.zone(forPercent: 60), .z2)   // inclusive lower bound
        XCTAssertEqual(HRZone.zone(forPercent: 65), .z2)
        XCTAssertEqual(HRZone.zone(forPercent: 70), .z3)
        XCTAssertEqual(HRZone.zone(forPercent: 85), .z4)
        XCTAssertEqual(HRZone.zone(forPercent: 90), .z5)
        XCTAssertEqual(HRZone.zone(forPercent: 105), .z5)  // over max still Z5
    }

    // MARK: - Time-in-zone bucketing

    func testZoneDistributionAttributesTimeToEarlierSample() {
        let t0 = Date(timeIntervalSince1970: 0)
        // hrMax = 200 → 120 bpm = 60% (Z2), 180 bpm = 90% (Z5).
        let samples: [(date: Date, bpm: Int)] = [
            (t0, 120),                              // 10s in Z2
            (t0.addingTimeInterval(10), 180),       // 10s in Z5
            (t0.addingTimeInterval(20), 180),       // trailing sample, no interval after
        ]
        let dist = ZoneBucketer.distribution(samples: samples, hrMax: 200)
        XCTAssertEqual(dist[.z2] ?? 0, 10, accuracy: 0.001)
        XCTAssertEqual(dist[.z5] ?? 0, 10, accuracy: 0.001)
        XCTAssertNil(dist[.z1])
    }

    func testZoneDistributionCapsLargeGaps() {
        let t0 = Date(timeIntervalSince1970: 0)
        let samples: [(date: Date, bpm: Int)] = [
            (t0, 120),                              // gap of 300s, capped to 30
            (t0.addingTimeInterval(300), 120),
        ]
        let dist = ZoneBucketer.distribution(samples: samples, hrMax: 200, maxGap: 30)
        XCTAssertEqual(dist[.z2] ?? 0, 30, accuracy: 0.001)
    }

    func testZoneDistributionSortsUnorderedInput() {
        let t0 = Date(timeIntervalSince1970: 0)
        let samples: [(date: Date, bpm: Int)] = [
            (t0.addingTimeInterval(10), 180),
            (t0, 120),
        ]
        let dist = ZoneBucketer.distribution(samples: samples, hrMax: 200)
        XCTAssertEqual(dist[.z2] ?? 0, 10, accuracy: 0.001)
    }

    func testZoneDistributionEmptyForBadInput() {
        let t0 = Date(timeIntervalSince1970: 0)
        XCTAssertTrue(ZoneBucketer.distribution(samples: [(t0, 120)], hrMax: 200).isEmpty)
        XCTAssertTrue(ZoneBucketer.distribution(samples: [(t0, 120), (t0, 130)], hrMax: 0).isEmpty)
    }

    // MARK: - HR max resolver

    func testEffectiveHRMaxOverrideWins() {
        XCTAssertEqual(HealthKitService.effectiveHRMax(override: 185, age: 30), 185)
    }

    func testEffectiveHRMaxFromAge() {
        XCTAssertEqual(HealthKitService.effectiveHRMax(override: 0, age: 40), 180)
    }

    func testEffectiveHRMaxFallback() {
        XCTAssertEqual(HealthKitService.effectiveHRMax(override: 0, age: nil),
                       HealthKitService.fallbackHRMax)
        XCTAssertEqual(HealthKitService.effectiveHRMax(override: 0, age: 200),
                       HealthKitService.fallbackHRMax)   // implausible age → fallback
    }
}
