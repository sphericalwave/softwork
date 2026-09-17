import XCTest
@testable import SessionEngine

final class TimeoutControllerTests: XCTestCase {

    // hrMax 200 → ceiling 160, reset 140. Trigger 3 s, hold 10 s, min timeout 20 s.
    private let prescription = SparringPrescription()
    private var zone: ResolvedZone { prescription.resolve(hrMax: 200)! }

    private func solo() -> TimeoutController {
        TimeoutController(prescription: prescription, zones: [zone])
    }

    /// Feeds one reading per second for athlete `athlete` over `seconds`.
    @discardableResult
    private func feed(_ c: inout TimeoutController, athlete: Int = 0, bpm: Int,
                      from start: Int, through end: Int, signalGood: Bool = true) -> [TimeoutController.Signal] {
        var signals: [TimeoutController.Signal] = []
        for t in start...end {
            signals += c.ingest(athlete: athlete, bpm: bpm, signalGood: signalGood, t: TimeInterval(t))
        }
        return signals
    }

    func testOverCeilingThreeSecondsTriggersTimeout() {
        var c = solo()
        let signals = feed(&c, bpm: 170, from: 0, through: 3)
        XCTAssertEqual(signals, [.timeoutStarted(triggeredBy: 0, t: 3)])
        XCTAssertEqual(c.phase, .timeout(startT: 3, triggeredBy: 0))
    }

    func testSpikeShorterThanTriggerDoesNotTimeout() {
        var c = solo()
        feed(&c, bpm: 170, from: 0, through: 2)
        let signals = feed(&c, bpm: 150, from: 3, through: 10)
        XCTAssertTrue(signals.isEmpty)
        XCTAssertEqual(c.phase, .sparring)
    }

    func testAtCeilingIsNotOver() {
        var c = solo()
        XCTAssertTrue(feed(&c, bpm: 160, from: 0, through: 30).isEmpty)
    }

    func testBadSignalBreaksTriggerStreak() {
        var c = solo()
        feed(&c, bpm: 170, from: 0, through: 2)
        feed(&c, bpm: 170, from: 3, through: 3, signalGood: false)
        XCTAssertTrue(feed(&c, bpm: 170, from: 4, through: 6).isEmpty)
        XCTAssertEqual(feed(&c, bpm: 170, from: 7, through: 7), [.timeoutStarted(triggeredBy: 0, t: 7)])
    }

    func testResetNeedsHoldAndMinimumTimeout() {
        var c = solo()
        feed(&c, bpm: 170, from: 0, through: 3)            // timeout at t=3
        // Recovered at t=4; hold satisfied by t=14 but min timeout not until t=23.
        XCTAssertTrue(feed(&c, bpm: 130, from: 4, through: 22).isEmpty)
        XCTAssertEqual(feed(&c, bpm: 130, from: 23, through: 23), [.resetReady(t: 23)])
    }

    func testResetHoldRestartsIfHRClimbsBack() {
        var c = solo()
        feed(&c, bpm: 170, from: 0, through: 3)
        feed(&c, bpm: 130, from: 4, through: 20)
        feed(&c, bpm: 150, from: 21, through: 21)          // above reset: hold restarts
        XCTAssertTrue(feed(&c, bpm: 130, from: 22, through: 31).isEmpty)
        XCTAssertEqual(feed(&c, bpm: 130, from: 32, through: 32), [.resetReady(t: 32)])
    }

    func testTickLetsMinimumTimeoutElapseBetweenSamples() {
        var c = solo()
        feed(&c, bpm: 170, from: 0, through: 3)
        feed(&c, bpm: 130, from: 4, through: 15)
        XCTAssertEqual(c.tick(t: 23), [.resetReady(t: 23)])
    }

    func testResumeReturnsToSparringWithFreshStreaks() {
        var c = solo()
        feed(&c, bpm: 170, from: 0, through: 3)
        feed(&c, bpm: 130, from: 4, through: 23)
        c.resume()
        XCTAssertEqual(c.phase, .sparring)
        feed(&c, bpm: 170, from: 30, through: 32)
        XCTAssertEqual(c.phase, .sparring)
    }

    func testEitherAthleteTriggersAndResetNeedsBoth() {
        var c = TimeoutController(prescription: prescription, zones: [zone, zone])
        var signals: [TimeoutController.Signal] = []
        for t in 0...3 {
            signals += c.ingest(athlete: 0, bpm: 150, signalGood: true, t: TimeInterval(t))
            signals += c.ingest(athlete: 1, bpm: 170, signalGood: true, t: TimeInterval(t))
        }
        XCTAssertEqual(signals, [.timeoutStarted(triggeredBy: 1, t: 3)])

        signals = []
        for t in 4...40 {
            signals += c.ingest(athlete: 0, bpm: 130, signalGood: true, t: TimeInterval(t))
            signals += c.ingest(athlete: 1, bpm: 150, signalGood: true, t: TimeInterval(t))
        }
        XCTAssertTrue(signals.isEmpty, "athlete 1 never reached reset")

        for t in 41...51 {
            signals += c.ingest(athlete: 0, bpm: 130, signalGood: true, t: TimeInterval(t))
            signals += c.ingest(athlete: 1, bpm: 135, signalGood: true, t: TimeInterval(t))
        }
        XCTAssertEqual(signals, [.resetReady(t: 51)])
    }
}
