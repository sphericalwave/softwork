//
//  SoloSparringModel.swift
//  AthleteFeatures
//
//  Single-device training (M1): one athlete, one strap. A training session
//  records heart rate from Start Training to End; sparring rounds inside it
//  run the ceiling/timeout game. The two-athlete peer session (M3/M4)
//  replaces the sparring part.
//
//  Durability: session metadata and each finished round are saved to
//  SwiftData immediately, and every reading is appended to an HRBufferFile,
//  so an app kill loses nothing. At End the workout goes to HealthKit; the
//  buffer is deleted only once that succeeds.
//

#if os(iOS)
import Foundation
import Observation
import SessionEngine
import HeartRateKit
import AlertKit
import Persistence

@MainActor
@Observable
public final class SoloSparringModel {

    public enum Stage: Equatable {
        case lobby
        /// Recording, no game running.
        case training
        case countdown(Int)
        case sparring
        case timeout
        case resuming(Int)
    }

    public enum SaveState: Equatable {
        case idle
        case saving
        case saved
        case failed(String)
    }

    /// An open session older than this at launch is ended at its last
    /// reading instead of resumed.
    private static let staleAfter: TimeInterval = 30 * 60

    /// Takes effect at the next Start Training; a running session keeps its own.
    public var hrMax: Int
    public let ble: BLEHeartRateSource?
    public private(set) var stage: Stage = .lobby
    public private(set) var bpm: Int?
    public private(set) var signal: HRSignalState = .disconnected
    public private(set) var kind: WorkoutKind = .wrestling
    /// The max HR the session's bands and rounds are resolved against.
    public private(set) var sessionHRMax = 0
    /// Good-signal readings since the session began.
    public private(set) var points: [HRPoint] = []
    /// Finished sparring rounds.
    public private(set) var rounds: [SparringRound] = []
    /// Seconds since the session began.
    public private(set) var elapsed: TimeInterval = 0

    // Current sparring round
    public private(set) var zone: ResolvedZone?
    public private(set) var prescription = SparringPrescription()
    public private(set) var timeoutCount = 0
    /// Seconds left in the minimum timeout, while in `.timeout`.
    public private(set) var minTimeoutRemaining = 0
    private var roundStart: TimeInterval?

    /// The session that just ended, shown until dismissed.
    public private(set) var summary: TrainingSummary?
    public private(set) var saveState: SaveState = .idle

    private let source: HeartRateSource
    private let alerts: AlertOutput
    private let store: SessionStore
    private let health = HealthWorkoutWriter()
    private var controller: TimeoutController?
    private var evaluator = HRSignalEvaluator()
    private var sessionStart = Date()
    private var timeoutStart: Date?
    private var readingStarted = false
    private var record: TrainingSessionRecord?
    private var buffer: HRBufferFile?
    private var calorieProfile: CalorieProfile?

    init(hrMax: Int, source: HeartRateSource, ble: BLEHeartRateSource?, alerts: AlertOutput, store: SessionStore) {
        self.hrMax = hrMax
        self.source = source
        self.ble = ble
        self.alerts = alerts
        self.store = store
    }

    // MARK: - Lifecycle

    /// Screen visible: keep the display on and make sure the sensor is being read.
    /// Reading starts once and never stops — cancelling an `AsyncStream`
    /// consumer finishes the stream, so a restart would receive nothing.
    /// The first call also recovers any session interrupted by an app kill.
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
        Task { await self.recover() }
    }

    /// Leaving the tab doesn't stop a session; it keeps recording.
    public func deactivate() {
        KeepAwake.set(false)
    }

    // MARK: - Training session

    public var isSessionActive: Bool { stage != .lobby }

    public func startTraining(kind: WorkoutKind) {
        guard stage == .lobby, summary == nil else { return }
        let id = UUID()
        let now = Date()
        self.kind = kind
        sessionHRMax = hrMax
        sessionStart = now
        points = []
        rounds = []
        elapsed = 0
        record = store.begin(id: id, startedAt: now, kind: kind, hrMax: hrMax)
        buffer = HRBufferFile(sessionID: id)
        stage = .training
        Task {
            await health.requestAuthorization()
            calorieProfile = await health.calorieProfile()
        }
    }

    public func endSession() {
        guard let record, stage != .lobby else { return }
        stopSparring()
        let now = Date()
        finish(record, at: now, points: points, rounds: rounds, profile: calorieProfile)
        stage = .lobby
    }

    public func retrySave() {
        guard let record, let summary else { return }
        Task { await save(summary, record: record, buffer: buffer) }
    }

    public func dismissSummary() {
        summary = nil
        saveState = .idle
        record = nil
        buffer = nil
    }

    // MARK: - Sparring rounds

    /// Validates the prescription for this athlete; nil when it can't start.
    public func preview(_ prescription: SparringPrescription) -> ResolvedZone? {
        prescription.resolve(hrMax: isSessionActive ? sessionHRMax : hrMax)
    }

    public func startSparring(with prescription: SparringPrescription) {
        guard stage == .training, let zone = prescription.resolve(hrMax: sessionHRMax) else { return }
        self.prescription = prescription
        self.zone = zone
        controller = TimeoutController(prescription: prescription, zones: [zone])
        timeoutCount = 0
        stage = .countdown(3)
    }

    /// Back to plain recording. A round only counts once its countdown finished.
    public func stopSparring() {
        alerts.stopAlarm()
        if let roundStart, let zone, let record {
            let round = SparringRound(start: roundStart, end: Date().timeIntervalSince(sessionStart),
                                      ceilingBPM: zone.ceilingBPM, resetBPM: zone.resetBPM,
                                      timeoutCount: timeoutCount)
            rounds.append(round)
            store.add(round, to: record.id)
        }
        roundStart = nil
        controller = nil
        timeoutStart = nil
        if stage != .lobby { stage = .training }
    }

    /// Finished rounds plus the one in progress, for the chart.
    public var chartRounds: [SparringRound] {
        guard let roundStart, let zone else { return rounds }
        return rounds + [SparringRound(start: roundStart, end: elapsed, ceilingBPM: zone.ceilingBPM,
                                       resetBPM: zone.resetBPM, timeoutCount: timeoutCount)]
    }

    public func testAlarm() {
        alerts.testAlarm()
    }

    // MARK: - Finish & save

    private func finish(_ record: TrainingSessionRecord, at end: Date, points: [HRPoint],
                        rounds: [SparringRound], profile: CalorieProfile?) {
        let summary = Self.summary(of: record, endingAt: end, points: points, rounds: rounds, profile: profile)
        store.end(record, at: end, summary: summary)
        self.summary = summary
        let buffer = buffer
        Task { await save(summary, record: record, buffer: buffer) }
    }

    private static func summary(of record: TrainingSessionRecord, endingAt end: Date, points: [HRPoint],
                                rounds: [SparringRound], profile: CalorieProfile?) -> TrainingSummary {
        TrainingSummary(startedAt: record.startedAt,
                        duration: max(end.timeIntervalSince(record.startedAt), 0),
                        kind: WorkoutKind(rawValue: record.kindRaw) ?? .wrestling,
                        hrMax: record.hrMax, points: points, rounds: rounds, profile: profile)
    }

    private func save(_ summary: TrainingSummary, record: TrainingSessionRecord, buffer: HRBufferFile?) async {
        let isCurrent = record === self.record
        if isCurrent { saveState = .saving }
        do {
            let workoutID = try await health.save(summary, sessionID: record.id)
            store.markSaved(record, workoutID: workoutID)
            buffer?.delete()
            if isCurrent { saveState = .saved }
        } catch {
            if isCurrent { saveState = .failed(error.localizedDescription) }
        }
    }

    /// Runs once per launch. First, synchronously, resume a session the app
    /// was killed during — or, if it's stale, end it at its last reading.
    /// Then retry every ended session whose HealthKit save didn't finish.
    private func recover() async {
        if let open = store.openSession(), stage == .lobby {
            let file = HRBufferFile(sessionID: open.id)
            let readings = file.read()
            let restored = Self.points(readings, since: open.startedAt)
            let savedRounds = store.rounds(for: open.id)
            let lastActivity = [readings.last?.date,
                                savedRounds.last.map { open.startedAt.addingTimeInterval($0.end) },
                                open.startedAt].compactMap { $0 }.max() ?? open.startedAt

            if Date().timeIntervalSince(lastActivity) > Self.staleAfter {
                // Saved to HealthKit by the retry loop below.
                store.end(open, at: lastActivity, summary: Self.summary(of: open, endingAt: lastActivity,
                                                                        points: restored, rounds: savedRounds,
                                                                        profile: nil))
            } else {
                record = open
                buffer = file
                kind = WorkoutKind(rawValue: open.kindRaw) ?? .wrestling
                sessionHRMax = open.hrMax
                sessionStart = open.startedAt
                points = restored
                rounds = savedRounds
                elapsed = Date().timeIntervalSince(open.startedAt)
                stage = .training
            }
        }

        await health.requestAuthorization()
        calorieProfile = await health.calorieProfile()

        for unsaved in store.unsavedSessions() where unsaved !== record {
            let file = HRBufferFile(sessionID: unsaved.id)
            let end = unsaved.endedAt ?? unsaved.startedAt
            let summary = Self.summary(of: unsaved, endingAt: end,
                                       points: Self.points(file.read(), since: unsaved.startedAt),
                                       rounds: store.rounds(for: unsaved.id), profile: calorieProfile)
            store.end(unsaved, at: end, summary: summary)
            await save(summary, record: unsaved, buffer: file)
        }
    }

    private static func points(_ readings: [(date: Date, bpm: Int)], since start: Date) -> [HRPoint] {
        readings.map { HRPoint(t: $0.date.timeIntervalSince(start), bpm: $0.bpm) }
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
        guard isSessionActive else { return }
        let t = sample.timestamp.timeIntervalSince(sessionStart)
        if signal == .good {
            points.append(HRPoint(t: t, bpm: sample.bpm))
            buffer?.append(date: sample.timestamp, bpm: sample.bpm)
        }
        guard stage == .sparring || stage == .timeout else { return }
        let signals = controller?.ingest(athlete: 0, bpm: sample.bpm, signalGood: signal == .good, t: t) ?? []
        handle(signals)
    }

    private func tick(now: Date) {
        signal = evaluator.state(now: now, connected: isConnected)
        if signal != .good && signal != .noContact { bpm = nil }
        if isSessionActive { elapsed = now.timeIntervalSince(sessionStart) }

        switch stage {
        case .countdown(let n):
            if n > 1 {
                stage = .countdown(n - 1)
            } else {
                roundStart = elapsed
                stage = .sparring
            }
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
        case .lobby, .training, .sparring:
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
