import XCTest
@testable import SessionEngine

final class CalorieEstimatorTests: XCTestCase {

    private let male = CalorieProfile(sex: .male, weightKg: 80, age: 35)
    private let female = CalorieProfile(sex: .female, weightKg: 60, age: 30)

    func testKeytelMale() {
        // (-55.0969 + 0.6309*150 + 0.1988*80 + 0.2017*35) / 4.184
        XCTAssertEqual(CalorieEstimator.grossKcalPerMinute(bpm: 150, profile: male), 14.938, accuracy: 0.001)
    }

    func testKeytelFemale() {
        // (-20.4022 + 0.4472*150 - 0.1263*60 + 0.074*30) / 4.184
        XCTAssertEqual(CalorieEstimator.grossKcalPerMinute(bpm: 150, profile: female), 9.876, accuracy: 0.001)
    }

    func testActiveSubtractsOneMET() {
        let gross = CalorieEstimator.grossKcalPerMinute(bpm: 150, profile: male)
        XCTAssertEqual(CalorieEstimator.activeKcalPerMinute(bpm: 150, profile: male), gross - 80.0 / 60, accuracy: 1e-9)
    }

    func testActiveNeverNegative() {
        XCTAssertEqual(CalorieEstimator.activeKcalPerMinute(bpm: 40, profile: male), 0)
    }

    func testEnergyBucketsPerMinute() {
        let points = (0..<150).map { HRPoint(t: TimeInterval($0), bpm: 150) }
        let energy = CalorieEstimator.activeEnergy(points: points, profile: male)
        XCTAssertEqual(energy.count, 3)
        XCTAssertEqual(energy[0].start, 0)
        XCTAssertEqual(energy[0].end, 60)
        XCTAssertEqual(energy[2].end, 149)
        let perMinute = CalorieEstimator.activeKcalPerMinute(bpm: 150, profile: male)
        XCTAssertEqual(energy[0].kcal, perMinute, accuracy: 1e-9)
    }

    func testDropoutAddsOnlyTheCap() {
        let points = [HRPoint(t: 0, bpm: 150), HRPoint(t: 300, bpm: 150)]
        let energy = CalorieEstimator.activeEnergy(points: points, profile: male)
        let perMinute = CalorieEstimator.activeKcalPerMinute(bpm: 150, profile: male)
        XCTAssertEqual(energy.reduce(0) { $0 + $1.kcal }, perMinute * HRPoint.maxGap / 60, accuracy: 1e-9)
    }
}
