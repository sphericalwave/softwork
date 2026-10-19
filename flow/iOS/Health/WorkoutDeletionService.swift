//
//  WorkoutDeletionService.swift
//  flow
//
//  Deletes a workout flow recorded, from Health and from flow: the workout,
//  the heart rate and active energy flow saved during it (recorded or
//  copied), its session and sparring rounds. Health only lets an app delete
//  what it wrote, so other apps' readings in that time (e.g. a Watch) stay.
//

import Foundation
import HealthKit
import SwiftData
import Persistence

@MainActor
final class WorkoutDeletionService {
    private let store: HKHealthStore

    init(store: HKHealthStore) {
        self.store = store
    }

    /// Health first: if that fails, the session stays so the workout can still be found and retried.
    func delete(_ session: TrainingSessionRecord, context: ModelContext) async throws {
        let ours = HKQuery.predicateForObjects(from: HKSource.default())
        if let workoutID = session.healthKitWorkoutID,
           let workout = try await HKSampleQueryDescriptor(
               predicates: [.workout(NSCompoundPredicate(andPredicateWithSubpredicates: [
                   HKQuery.predicateForObject(with: workoutID), ours,
               ]))],
               sortDescriptors: [], limit: 1
           ).result(for: store).first {
            let window = NSCompoundPredicate(andPredicateWithSubpredicates: [
                HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: .strictStartDate),
                ours,
            ])
            for type in [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
            where store.authorizationStatus(for: type) == .sharingAuthorized {
                _ = try await store.deleteObjects(of: type, predicate: window)
            }
            try await store.delete(workout)
        }

        let sessionID: UUID? = session.id
        let rounds = try context.fetch(FetchDescriptor<SparringRoundRecord>(predicate: #Predicate { $0.sessionID == sessionID }))
        rounds.forEach(context.delete)
        context.delete(session)
        try context.save()
    }
}
