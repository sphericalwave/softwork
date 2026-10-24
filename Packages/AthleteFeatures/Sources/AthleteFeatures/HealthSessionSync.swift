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
    /// Session id → why its last type change didn't go through.
    public private(set) var kindChangeErrors: [UUID: String] = [:]
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

    /// Rebuilds a past session's end-of-session summary: readings from its
    /// buffer file while it still has one, otherwise from Health.
    func summary(of record: TrainingSessionRecord, store: SessionStore) async -> TrainingSummary {
        let end = record.endedAt ?? Date()
        var points = Self.points(HRBufferFile(sessionID: record.id).read(), since: record.startedAt)
        if points.isEmpty {
            points = await health.heartRatePoints(from: record.startedAt, to: end)
        }
        return TrainingSummary(record: record, endingAt: end, points: points,
                               rounds: store.rounds(for: record.id), profile: await health.calorieProfile())
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

    // MARK: - Editing

    /// True while the session is being saved or re-saved to Health.
    public func isBusy(_ record: TrainingSessionRecord) -> Bool {
        inFlight.contains(record.id)
    }

    /// Changes a session's workout type. A session already in Health is
    /// saved there again as the new type: its readings go back into the
    /// buffer file first, so a failure midway leaves it pending, not lost.
    public func changeKind(of record: TrainingSessionRecord, to kind: WorkoutKind, context: ModelContext) {
        guard record.kindRaw != kind.rawValue, record.endedAt != nil, !inFlight.contains(record.id) else { return }
        let store = SessionStore(context: context)
        kindChangeErrors[record.id] = nil
        guard record.healthKitWorkoutID != nil else {
            // Not in Health yet: the next save picks up the new type.
            store.setKind(kind, of: record)
            return
        }
        inFlight.insert(record.id)
        Task { await resave(record, as: kind, store: store) }
    }

    /// Caller must have marked `record` in flight.
    private func resave(_ record: TrainingSessionRecord, as kind: WorkoutKind, store: SessionStore) async {
        let id = record.id
        let start = record.startedAt
        let end = record.endedAt ?? start
        let buffer = HRBufferFile(sessionID: id)
        await health.requestAuthorization()
        do {
            if !buffer.read().contains(where: \.hasContact) {
                let points = await health.heartRatePoints(from: start, to: end)
                // Heart rate was recorded but can't be read back: keep the
                // workout as it is rather than replace it without its readings.
                if points.isEmpty, record.averageBPM != nil { throw EditError.readingsUnavailable }
                try buffer.write(points.map { BufferedReading(date: start.addingTimeInterval($0.t), bpm: $0.bpm) })
            }
        } catch {
            inFlight.remove(id)
            kindChangeErrors[id] = Self.message(for: error)
            return
        }

        let oldKind = WorkoutKind(rawValue: record.kindRaw)
        store.setKind(kind, of: record)
        store.markUnsaved(record)
        do {
            try await health.deleteSession(sessionID: id, from: start, to: end)
        } catch {
            print("HealthSessionSync: type change failed for \(id): \(error)")
            kindChangeErrors[id] = Self.message(for: error)
            // The old workout is still there: put the session back as it was.
            if let oldKind, let existing = await health.savedWorkoutID(sessionID: id) {
                store.setKind(oldKind, of: record)
                if store.markSaved(record, workoutID: existing) { buffer.delete() }
                inFlight.remove(id)
                return
            }
        }
        await saveFromBuffer(record, store: store, profile: await health.calorieProfile())
    }

    // MARK: - Copied heart rate

    /// The session's stored heart-rate numbers, backed up before a copy changes them.
    public func heartRateStats(of record: TrainingSessionRecord, context: ModelContext) -> HeartRateStats {
        SessionStore(context: context).heartRateStats(of: record)
    }

    /// Brings the session's stored heart-rate numbers in line with Health
    /// after heart rate was copied in or removed. `original` is what they
    /// were before an undone copy; it comes back when no copy is left.
    /// Without readings to go on, the numbers stay as they are.
    public func refreshHeartRateStats(of record: TrainingSessionRecord, context: ModelContext,
                                      restoring original: HeartRateStats? = nil) async {
        await refreshHeartRateStats(of: record, store: SessionStore(context: context), restoring: original)
    }

    /// For a session copied into by a build whose copy didn't update its
    /// numbers: fixes them the next time it's opened.
    func refreshHeartRateStatsIfCopied(of record: TrainingSessionRecord, store: SessionStore) async {
        guard record.healthKitWorkoutID != nil, let end = record.endedAt,
              await health.hasCopiedHeartRate(from: record.startedAt, to: end) else { return }
        await refreshHeartRateStats(of: record, store: store, restoring: nil)
    }

    private func refreshHeartRateStats(of record: TrainingSessionRecord, store: SessionStore,
                                       restoring original: HeartRateStats?) async {
        // Not in Health, or being re-saved: Health isn't where its readings are.
        guard record.healthKitWorkoutID != nil, let end = record.endedAt, !inFlight.contains(record.id) else { return }
        let start = record.startedAt
        let remaining = await health.heartRatePoints(from: start, to: end)
        let copiesRemain = await health.hasCopiedHeartRate(from: start, to: end)
        guard let stats = HeartRateCopy.statsAfterUndo(remaining: remaining, rounds: store.rounds(for: record.id),
                                                       original: original, copiesRemain: copiesRemain),
              !record.isDeleted else { return }
        store.setHeartRateStats(stats, of: record)
    }

    private enum EditError: LocalizedError {
        case readingsUnavailable

        var errorDescription: String? {
            "flow couldn't read this session's heart rate back from Health, so its type wasn't changed."
        }
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
        if readings.contains(where: \.hasContact) { store.end(record, at: end, summary: summary) }
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
                workoutID = try await health.save(summary, kind: WorkoutKind(rawValue: record.kindRaw) ?? summary.kind,
                                                  sessionID: id)
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

    /// Counts no-contact readings: the session ran while the strap slipped.
    private static func lastActivity(of open: TrainingSessionRecord, readings: [BufferedReading],
                                     rounds: [SparringRound]) -> Date {
        [BufferedReading.lastDate(readings), rounds.last.map { open.startedAt.addingTimeInterval($0.end) }, open.startedAt]
            .compactMap { $0 }.max() ?? open.startedAt
    }

    static func points(_ readings: [BufferedReading], since start: Date) -> [HRPoint] {
        BufferedReading.points(readings, since: start)
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
