import XCTest
@testable import SessionEngine

final class NumberInputTests: XCTestCase {

    func testEmptyKeepsTheStoredValue() {
        XCTAssertNil(NumberInput.wholeNumber(""))
        XCTAssertNil(NumberInput.decimal("  "))
    }

    func testWholeNumber() {
        XCTAssertEqual(NumberInput.wholeNumber("191"), 191)
        XCTAssertEqual(NumberInput.wholeNumber(" 191 "), 191)
        XCTAssertEqual(NumberInput.wholeNumber("190.6"), 191)
    }

    func testEitherDecimalSeparator() {
        XCTAssertEqual(NumberInput.decimal("72.5"), 72.5)
        XCTAssertEqual(NumberInput.decimal("72,5"), 72.5)
    }

    func testZeroAndGarbageAreRejected() {
        XCTAssertNil(NumberInput.wholeNumber("0"))
        XCTAssertNil(NumberInput.decimal("-3"))
        XCTAssertNil(NumberInput.decimal("abc"))
        XCTAssertNil(NumberInput.decimal("1.2.3"))
        XCTAssertNil(NumberInput.decimal("inf"))
    }
}
