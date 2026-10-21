//
//  WorkoutDedupe.swift
//  SessionEngine
//
//  bioMechanic's watch app can save the same session flow records. The strap
//  wins, the watch fills in: a bioMechanic workout that overlaps a flow one
//  is left out so its time, energy and heart rate aren't counted twice.
//  Everything else, including bioMechanic workouts nothing overlaps, stays.
//

import Foundation

public enum WorkoutDedupe {

    /// Who saved a workout to Health.
    public enum Origin: Sendable, Equatable {
        case flow
        case bioMechanic
        case other
    }

    /// `SWSourceApp` metadata value bioMechanic tags its workouts with.
    public static let bioMechanicSourceApp = "bioMechanic"
    /// Metadata key holding that value.
    public static let sourceAppKey = "SWSourceApp"
    /// bioMechanic's watch app, for workouts saved without the tag.
    public static let bioMechanicWatchBundle = "com.sphericalwave.fitwrench.torque.watchkitapp"
    /// Overlap with a flow workout beyond this hides a bioMechanic one.
    public static let minimumOverlap: TimeInterval = 60

    /// Origin from the workout's source bundle and its `SWSourceApp` metadata.
    public static func origin(bundleID: String, sourceApp: String?, flowBundleID: String) -> Origin {
        if bundleID == flowBundleID { return .flow }
        if sourceApp == bioMechanicSourceApp || bundleID == bioMechanicWatchBundle { return .bioMechanic }
        return .other
    }

    /// Indexes of `workouts` to keep, in order: all but bioMechanic workouts
    /// sharing more than `minimumOverlap` with a flow workout.
    public static func kept(_ workouts: [(interval: DateInterval, origin: Origin)]) -> [Int] {
        let flow = workouts.filter { $0.origin == .flow }.map(\.interval)
        return workouts.indices.filter { i in
            guard workouts[i].origin == .bioMechanic else { return true }
            return !flow.contains { overlap($0, workouts[i].interval) > minimumOverlap }
        }
    }

    /// Seconds two intervals share; 0 when they don't meet.
    static func overlap(_ a: DateInterval, _ b: DateInterval) -> TimeInterval {
        max(0, min(a.end, b.end).timeIntervalSince(max(a.start, b.start)))
    }
}
