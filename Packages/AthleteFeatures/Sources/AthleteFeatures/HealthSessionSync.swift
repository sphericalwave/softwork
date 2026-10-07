//
//  HealthSessionSync.swift
//  AthleteFeatures
//
//  The one path an ended session takes into HealthKit, and its retry queue.
//  A session stays on this phone (metadata + HRBufferFile) until its workout
//  is in Health. The queue runs at every launch and every return to the
//  foreground, from whichever tab is showing — not only when Spar opens.
//
//  The last failure per session is kept in UserDefaults, not SwiftData, so
//  showing it needs no schema change.
//

#if os(iOS)
import Foundation
import Observation
import SwiftData
import HealthKit
import Persistence
import SessionEngine

public enum HealthSyncStatus: Equatable {
    /// Still recording; saved to Health when it ends.
    case recording
    /// Ended, waiting for its next save attempt.
    case pending
    case saving
    case synced
    /// The last attempt failed; retried automatically.
    case failed(String)
}

@MainActor
@Observable
public final class HealthSessionSync {
    public static let shared = HealthSessionSync()

    /// An open session quiet for longer than this is ended at its last
    /// reading instead of resumed.
    static let staleAfter: TimeInterval = 30 * 60
    private static let failuresKey = "healthSyncFailures"

    /// True while the retry queue is running.
    public private(set) var isSyncing = false
    /// The session the Spar screen is recording; never ended as stale.
    var activeSessionID: UUID?
    private var inFlight: Set<UUID> = []
    /// Session id → last failure message.
    private var failures: [String: String]
    private let health = HealthWorkoutWriter()

    private init() {
        failures = UserDefaults.standard.dictionary(forKey: Self.failuresKey) as? [String: String] ?? [:]
    }

    public func status(of record: TrainingSessionRecord) -> HealthSyncStatus {
        if record.healthKitWorkoutID != nil { return .synced }
        if record.endedAt == nil { return .recording }
        if inFlight.contains(record.id) { return .saving }
        if let message = failures[record.id.uuidString] { return .failed(message) }
        return .pending
    }

    // MARK: - Retry queue

    /// Ends an abandoned open session, then saves every ended session that
    /// isn't in Health yet. Safe to call often; overlapping calls are dropped.
    public func syncPending(context: ModelContext) async {
        await syncPending(store: SessionStore(context: context))
    }

    func syncPending(store: SessionStore) async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        if let open = store.openSession(), open.id != activeSessionID, Self.isStale(open, store: store) {
            let readings = HRBufferFile(sessionID: open.id).read()
            let rounds = store.rounds(for: open.id)
            let end = Self.lastActivity(of: open, readings: readings, rounds: rounds)
            store.end(open, at: end, summary: TrainingSummary(record: open, endingAt: end,
                                                              points: Self.points(readings, since: open.startedAt),
                                                              rounds: rounds, profile: nil))
        }

        let unsaved = store.unsavedSessions()
        guard !unsaved.isEmpty else { return }
        // Only prompt for Health access when there is something to save.
        await health.requestAuthorization()
        let profile = await health.calorieProfile()
        for record in unsaved where claim(record) {
            await saveFromBuffer(record, store: store, profile: profile)
        }
    }

    /// Retries one session now, e.g. from its history row.
    public func retry(_ record: TrainingSessionRecord, context: ModelContext) {
        guard claim(record) else { return }
        let store = SessionStore(context: context)
        Task {
            await health.requestAuthorization()
            await saveFromBuffer(record, store: store, profile: await health.calorieProfile())
        }
    }

    /// Saves a session that just ended, from the summary already in memory.
    /// Its status reads `.saving` from this call on.
    func save(_ summary: TrainingSummary, record: TrainingSessionRecord, buffer: HRBufferFile, store: SessionStore) {
        guard claim(record) else { return }
        Task { await perform(summary, record: record, buffer: buffer, store: store) }
    }

    // MARK: - Saving

    /// Marks the session in flight; false if it needs no save or one is running.
    private func claim(_ record: TrainingSessionRecord) -> Bool {
        guard record.endedAt != nil, record.healthKitWorkoutID == nil, !inFlight.contains(record.id) else { return false }
        inFlight.insert(record.id)
        return true
    }

    /// Rebuilds the summary from the session's buffer file. Stored numbers
    /// are refreshed (calories may be known now) but never wiped when the
    /// buffer is gone.
    private func saveFromBuffer(_ record: TrainingSessionRecord, store: SessionStore, profile: CalorieProfile?) async {
        let buffer = HRBufferFile(sessionID: record.id)
        let readings = buffer.read()
        let end = record.endedAt ?? record.startedAt
        let summary = TrainingSummary(record: record, endingAt: end,
                                      points: Self.points(readings, since: record.startedAt),
                                      rounds: store.rounds(for: record.id), profile: profile)
        if !readings.isEmpty { store.end(record, at: end, summary: summary) }
        await perform(summary, record: record, buffer: buffer, store: store)
    }

    /// Caller must have claimed `record`.
    private func perform(_ summary: TrainingSummary, record: TrainingSessionRecord,
                         buffer: HRBufferFile, store: SessionStore) async {
        let id = record.id
        defer { inFlight.remove(id) }
        do {
            await health.requestAuthorization()
            let workoutID: UUID
            if let existing = await health.savedWorkoutID(sessionID: id) {
                workoutID = existing
            } else {
                workoutID = try await health.save(summary, sessionID: id)
            }
            guard store.markSaved(record, workoutID: workoutID) else { throw SyncError.notRecorded }
            setFailure(nil, for: id)
            buffer.delete()
        } catch {
            print("HealthSessionSync: save failed for \(id): \(error)")
            setFailure(Self.message(for: error), for: id)
        }
    }

    private func setFailure(_ message: String?, for id: UUID) {
        failures[id.uuidString] = message
        UserDefaults.standard.set(failures, forKey: Self.failuresKey)
    }

    private enum SyncError: LocalizedError {
        case notRecorded

        var errorDescription: String? {
            "The workout is in Health, but flow couldn't note that on this phone."
        }
    }

    private static func message(for error: Error) -> String {
        if let error = error as? HKError {
            switch error.code {
            case .errorDatabaseInaccessible:
                return "Health can't be written while your phone is locked."
            case .errorAuthorizationDenied, .errorAuthorizationNotDetermined:
                return HealthWorkoutWriter.WriteError.workoutsNotAllowed.localizedDescription
            default:
                break
            }
        }
        return error.localizedDescription
    }

    // MARK: - Helpers

    static func isStale(_ open: TrainingSessionRecord, store: SessionStore) -> Bool {
        let last = lastActivity(of: open, readings: HRBufferFile(sessionID: open.id).read(),
                                rounds: store.rounds(for: open.id))
        return Date().timeIntervalSince(last) > staleAfter
    }

    private static func lastActivity(of open: TrainingSessionRecord, readings: [(date: Date, bpm: Int)],
                                     rounds: [SparringRound]) -> Date {
        [readings.last?.date, rounds.last.map { open.startedAt.addingTimeInterval($0.end) }, open.startedAt]
            .compactMap { $0 }.max() ?? open.startedAt
    }

    static func points(_ readings: [(date: Date, bpm: Int)], since start: Date) -> [HRPoint] {
        readings.map { HRPoint(t: $0.date.timeIntervalSince(start), bpm: $0.bpm) }
    }
}

extension TrainingSummary {
    init(record: TrainingSessionRecord, endingAt end: Date, points: [HRPoint],
         rounds: [SparringRound], profile: CalorieProfile?) {
        self.init(startedAt: record.startedAt,
                  duration: max(end.timeIntervalSince(record.startedAt), 0),
                  kind: WorkoutKind(rawValue: record.kindRaw) ?? .wrestling,
                  hrMax: record.hrMax, points: points, rounds: rounds, profile: profile)
    }
}
#endif
