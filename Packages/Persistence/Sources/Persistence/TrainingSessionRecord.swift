//
//  TrainingSessionRecord.swift
//  Persistence
//
//  One training session's metadata. Migration-safe shape: every attribute is
//  optional or defaulted and there are no relationships — rounds point back
//  by `sessionID`. Never change a shipped attribute in place; add a new
//  VersionedSchema in the app's FlowMigrationPlan instead.
//

import Foundation
import SwiftData

@Model
public final class TrainingSessionRecord {
    public var id: UUID = UUID()
    public var startedAt: Date = Date()
    /// nil while the session is still recording.
    public var endedAt: Date?
    /// `WorkoutKind.rawValue`.
    public var kindRaw: String = "wrestling"
    public var hrMax: Int = 0
    /// Set once the workout is saved to HealthKit; nil means not saved yet.
    public var healthKitWorkoutID: UUID?

    // Summary, filled in at End so history needs no HealthKit read.
    public var averageBPM: Int?
    public var maxBPM: Int?
    public var activeCalories: Double?
    public var timeoutCount: Int = 0
    public var secondsOverCeiling: Double = 0

    public init(id: UUID, startedAt: Date, kindRaw: String, hrMax: Int) {
        self.id = id
        self.startedAt = startedAt
        self.kindRaw = kindRaw
        self.hrMax = hrMax
    }
}

/// A sparring round inside a session. Times are seconds after the session began.
@Model
public final class SparringRoundRecord {
    public var id: UUID = UUID()
    public var sessionID: UUID?
    public var start: Double = 0
    public var end: Double = 0
    public var ceilingBPM: Int = 0
    public var resetBPM: Int = 0
    public var timeoutCount: Int = 0

    public init(sessionID: UUID, start: Double, end: Double, ceilingBPM: Int, resetBPM: Int, timeoutCount: Int) {
        self.sessionID = sessionID
        self.start = start
        self.end = end
        self.ceilingBPM = ceilingBPM
        self.resetBPM = resetBPM
        self.timeoutCount = timeoutCount
    }
}
