//
//  WorkoutTags.swift
//  flow
//
//  User tags for Health workouts flow didn't record (e.g. a Watch workout
//  saved as Weights that was really Jiu-Jitsu). Health can't be edited for
//  another app's workouts, so the tag lives on this phone, keyed by the
//  workout's UUID — in UserDefaults, so there's no schema change.
//

import Foundation
import Observation

enum WorkoutTag: String, CaseIterable, Identifiable {
    case jiujitsu
    case kickboxing
    case wrestling

    var id: String { rawValue }

    var label: String {
        switch self {
        case .jiujitsu: return "Jiu-Jitsu"
        case .kickboxing: return "Kickboxing"
        case .wrestling: return "Wrestling"
        }
    }
}

@MainActor
@Observable
final class WorkoutTags {
    private static let key = "workoutTags"
    private let defaults: UserDefaults
    /// Workout UUID string → `WorkoutTag.rawValue`.
    private var tags: [String: String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        tags = defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
    }

    func tag(for workoutID: UUID) -> WorkoutTag? {
        tags[workoutID.uuidString].flatMap(WorkoutTag.init(rawValue:))
    }

    /// nil clears the tag.
    func setTag(_ tag: WorkoutTag?, for workoutID: UUID) {
        tags[workoutID.uuidString] = tag?.rawValue
        defaults.set(tags, forKey: Self.key)
    }
}
