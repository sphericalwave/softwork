import XCTest
@testable import SessionEngine

final class SparringPrescriptionTests: XCTestCase {

    func testDefaultsResolveAgainstHRMax() throws {
        let zone = try XCTUnwrap(SparringPrescription().resolve(hrMax: 200))
        XCTAssertEqual(zone.ceilingBPM, 160)
        XCTAssertEqual(zone.floorBPM, 130)
        XCTAssertEqual(zone.resetBPM, 140)
        XCTAssertEqual(zone.nearCeilingBPM, 154)
    }

    func testResetMustBeBelowCeiling() {
        let p = SparringPrescription(ceilingPct: 0.75, resetPct: 0.75)
        XCTAssertTrue(p.validate(hrMax: 200).contains(.resetNotBelowCeiling))
        XCTAssertNil(p.resolve(hrMax: 200))
    }

    func testFloorMustBeBelowCeiling() {
        let p = SparringPrescription(ceilingPct: 0.70, targetFloorPct: 0.72, resetPct: 0.60)
        XCTAssertTrue(p.validate(hrMax: 200).contains(.floorNotBelowCeiling))
    }

    func testResolvedBpmMustBePlausible() {
        XCTAssertTrue(SparringPrescription().validate(hrMax: 300).contains(.bpmOutOfRange))
        XCTAssertTrue(SparringPrescription().validate(hrMax: 50).contains(.bpmOutOfRange))
    }

    func testDurationsMustBePositive() {
        let p = SparringPrescription(triggerSeconds: 0)
        XCTAssertTrue(p.validate(hrMax: 200).contains(.nonPositiveDuration))
    }

    func testBands() throws {
        let zone = try XCTUnwrap(SparringPrescription().resolve(hrMax: 200))
        XCTAssertEqual(zone.band(for: 120), .belowTarget)
        XCTAssertEqual(zone.band(for: 130), .inTarget)
        XCTAssertEqual(zone.band(for: 154), .nearCeiling)
        XCTAssertEqual(zone.band(for: 160), .nearCeiling)   // at ceiling is not over
        XCTAssertEqual(zone.band(for: 161), .overCeiling)
    }
}
