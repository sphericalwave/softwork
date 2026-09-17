import XCTest
@testable import SessionEngine

final class MaxHeartRateTests: XCTestCase {

    func testOverrideWins() {
        XCTAssertEqual(MaxHeartRate.effective(override: 205, age: 30, formula: .tanaka), 205)
    }

    func testTanakaFromAge() {
        // 208 - 0.7*40 = 180
        XCTAssertEqual(MaxHeartRate.effective(override: 0, age: 40, formula: .tanaka), 180)
    }

    func testTraditionalFromAge() {
        XCTAssertEqual(MaxHeartRate.effective(override: 0, age: 40, formula: .traditional), 180)
    }

    func testFallbackWhenNoAgeOrOverride() {
        XCTAssertEqual(MaxHeartRate.effective(override: 0, age: nil, formula: .tanaka), MaxHeartRate.fallback)
        XCTAssertEqual(MaxHeartRate.effective(override: 0, age: 0, formula: .tanaka), MaxHeartRate.fallback)
        XCTAssertEqual(MaxHeartRate.effective(override: 0, age: 200, formula: .tanaka), MaxHeartRate.fallback)
    }
}
