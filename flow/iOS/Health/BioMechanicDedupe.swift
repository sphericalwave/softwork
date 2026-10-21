//
//  BioMechanicDedupe.swift
//  flow
//
//  Applies WorkoutDedupe to workouts read from Health: bioMechanic watch
//  workouts that overlap a flow one are dropped wherever flow lists or
//  totals workouts. flow can't delete them; it just doesn't count them.
//

import HealthKit
import SessionEngine

extension Array where Element == HKWorkout {
    /// These workouts, in order, without bioMechanic ones that shadow a flow workout.
    func withoutBioMechanicShadows() -> [HKWorkout] {
        let flowBundle = HKSource.default().bundleIdentifier
        let entries = map { workout in
            (interval: DateInterval(start: workout.startDate, end: max(workout.startDate, workout.endDate)),
             origin: WorkoutDedupe.origin(bundleID: workout.sourceRevision.source.bundleIdentifier,
                                          sourceApp: workout.metadata?[WorkoutDedupe.sourceAppKey] as? String,
                                          flowBundleID: flowBundle))
        }
        return WorkoutDedupe.kept(entries).map { self[$0] }
    }
}
