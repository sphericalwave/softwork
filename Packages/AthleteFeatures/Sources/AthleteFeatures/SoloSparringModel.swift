//
//  SoloSparringModel.swift
//  AthleteFeatures
//
//  Single-device sparring (M1): one athlete, one strap, the timeout rule
//  enforced locally. The two-athlete peer session (M3/M4) replaces this.
//

#if os(iOS)
import Foundation
import Observation
import SessionEngine
import HeartRateKit
import AlertKit

@MainActor
@Observable
public final class SoloSparringModel {

    public enum Stage: Equatable {
        case lobby
        case countdown(Int)
        case sparring
        case timeout
        case resuming(Int)
    }

    /// Takes effect at the next `start`; a running session keeps its resolved zone.
    public var hrMax: Int
    public let ble: BLEHeartRateSource?
    public private(set) var stage: Stage = .lobby
    public private(set) var bpm: Int?
    public private(set) var signal: HRSignalState = .disconnected
    public private(set) var timeoutCount = 0
    public private(set) var zone: ResolvedZone?
    public private(set) var prescription = SparringPrescription()
    /// Seconds left in the minimum timeout, while in `.timeout`.
    public private(set) var minTimeoutRemaining = 0

    private let source: HeartRateSource
    private let alerts: AlertOutput
    private var controller: TimeoutController?
    private var evaluator = HRSignalEvaluator()
    private var sessionStart = Date()
    private var timeoutStart: Date?
    private var readingStarted = false

    public init(hrMax: Int, source: HeartRateSource, ble: BLEHeartRateSource?, alerts: AlertOutput) {
        self.hrMax = hrMax
        self.source = source
        self.ble = ble
        self.alerts = alerts
    }

    // MARK: - Lifecycle

    /// Screen visible: keep the display on and make sure the sensor is being read.
    /// Reading starts once and never stops — cancelling an `AsyncStream`
    /// consumer finishes the stream, so a restart would receive nothing.
    public func activate() {
        KeepAwake.set(true)
        guard !readingStarted else { return }
        readingStarted = true
        // BLE: reconnect only a remembered strap; new straps are chosen in the pairing sheet.
        if ble?.hasRememberedDevice ?? true {
            Task { [source] in try? await source.start() }
        }
        Task { await self.readSamples() }
        Task { await self.runClock() }
    }

    public func deactivate() {
        endSession()
        KeepAwake.set(false)
    }

    // MARK: - Session

    /// Validates the prescription for this athlete; nil when it can't start.
    public func preview(_ prescription: SparringPrescription) -> ResolvedZone? {
        prescription.resolve(hrMax: hrMax)
    }

    public func start(with prescription: SparringPrescription) {
        guard stage == .lobby, let zone = prescription.resolve(hrMax: hrMax) else { return }
        self.prescription = prescription
        self.zone = zone
        controller = TimeoutController(prescription: prescription, zones: [zone])
        timeoutCount = 0
        sessionStart = Date()
        stage = .countdown(3)
    }

    public func endSession() {
        alerts.stopAlarm()
        controller = nil
        stage = .lobby
    }

    public func testAlarm() {
        alerts.testAlarm()
    }

    // MARK: - Loops

    private func readSamples() async {
        if let detailed = source as? DetailedHeartRateSource {
            for await sample in detailed.detailedSamples {
                ingest(sample)
            }
        } else {
            for await value in source.samples {
                ingest(HeartRateSample(bpm: value, contact: .unsupported, rrIntervals: [],
                                       energyExpended: nil, timestamp: Date(),
                                       uptime: Date().timeIntervalSince(sessionStart)))
            }
        }
    }

    private func runClock() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            tick(now: Date())
        }
    }

    private func ingest(_ sample: HeartRateSample) {
        evaluator.ingest(sample)
        bpm = sample.bpm
        signal = evaluator.state(now: sample.timestamp, connected: isConnected)
        guard stage == .sparring || stage == .timeout else { return }
        let t = sample.timestamp.timeIntervalSince(sessionStart)
        let signals = controller?.ingest(athlete: 0, bpm: sample.bpm, signalGood: signal == .good, t: t) ?? []
        handle(signals)
    }

    private func tick(now: Date) {
        signal = evaluator.state(now: now, connected: isConnected)
        if signal != .good && signal != .noContact { bpm = nil }

        switch stage {
        case .countdown(let n):
            stage = n > 1 ? .countdown(n - 1) : .sparring
        case .resuming(let n):
            if n > 1 {
                stage = .resuming(n - 1)
            } else {
                controller?.resume()
                stage = .sparring
            }
        case .timeout:
            if let timeoutStart {
                let elapsed = Int(now.timeIntervalSince(timeoutStart))
                minTimeoutRemaining = max(prescription.minTimeoutSeconds - elapsed, 0)
            }
            handle(controller?.tick(t: now.timeIntervalSince(sessionStart)) ?? [])
        case .lobby, .sparring:
            break
        }
    }

    private func handle(_ signals: [TimeoutController.Signal]) {
        for signal in signals {
            switch signal {
            case .timeoutStarted:
                timeoutCount += 1
                timeoutStart = Date()
                minTimeoutRemaining = prescription.minTimeoutSeconds
                stage = .timeout
                alerts.startAlarm()
            case .resetReady:
                alerts.stopAlarm()
                alerts.playResetChime()
                timeoutStart = nil
                stage = .resuming(3)
            }
        }
    }

    private var isConnected: Bool {
        guard let ble else { return true }
        return ble.connected != nil
    }
}
#endif
