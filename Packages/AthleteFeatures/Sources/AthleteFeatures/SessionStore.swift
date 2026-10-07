//
//  SessionStore.swift
//  AthleteFeatures
//
//  Session metadata in the app's SwiftData store. Every change is saved
//  immediately: a session must survive an app kill at any point.
//

#if os(iOS)
import Foundation
import SwiftData
import Persistence
import SessionEngine

@MainActor
final class SessionStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// The session still recording, if the app was killed during one.
    func openSession() -> TrainingSessionRecord? {
        var descriptor = FetchDescriptor<TrainingSessionRecord>(
            predicate: #Predicate { $0.endedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// Ended sessions whose workout isn't in HealthKit yet.
    func unsavedSessions() -> [TrainingSessionRecord] {
        let descriptor = FetchDescriptor<TrainingSessionRecord>(
            predicate: #Predicate { $0.endedAt != nil && $0.healthKitWorkoutID == nil },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func begin(id: UUID, startedAt: Date, kind: WorkoutKind, hrMax: Int) -> TrainingSessionRecord {
        let record = TrainingSessionRecord(id: id, startedAt: startedAt, kindRaw: kind.rawValue, hrMax: hrMax)
        context.insert(record)
        save()
        return record
    }

    func rounds(for sessionID: UUID) -> [SparringRound] {
        let id: UUID? = sessionID
        let descriptor = FetchDescriptor<SparringRoundRecord>(
            predicate: #Predicate { $0.sessionID == id },
            sortBy: [SortDescriptor(\.start)]
        )
        return ((try? context.fetch(descriptor)) ?? []).map {
            SparringRound(start: $0.start, end: $0.end, ceilingBPM: $0.ceilingBPM,
                          resetBPM: $0.resetBPM, timeoutCount: $0.timeoutCount)
        }
    }

    func add(_ round: SparringRound, to sessionID: UUID) {
        context.insert(SparringRoundRecord(sessionID: sessionID, start: round.start, end: round.end,
                                           ceilingBPM: round.ceilingBPM, resetBPM: round.resetBPM,
                                           timeoutCount: round.timeoutCount))
        save()
    }

    func end(_ record: TrainingSessionRecord, at date: Date, summary: TrainingSummary) {
        record.endedAt = date
        record.averageBPM = summary.averageBPM
        record.maxBPM = summary.maxBPM
        record.activeCalories = summary.activeCalories
        record.timeoutCount = summary.timeoutCount
        record.secondsOverCeiling = summary.secondsOverCeiling
        save()
    }

    /// False if the store couldn't be written; the caller must then keep the
    /// session's buffer file.
    func markSaved(_ record: TrainingSessionRecord, workoutID: UUID) -> Bool {
        record.healthKitWorkoutID = workoutID
        return save()
    }

    @discardableResult
    private func save() -> Bool {
        do {
            try context.save()
            return true
        } catch {
            print("SessionStore: save failed: \(error)")
            return false
        }
    }
}
#endif
