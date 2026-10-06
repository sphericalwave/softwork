//
//  TrainingSummary.swift
//  SessionEngine
//
//  A training session is one continuous recording; sparring rounds are the
//  stretches inside it where the ceiling game ran. Everything here derives
//  from what the strap reported, plus the calorie estimate in
//  CalorieEstimator.
//

import Foundation

/// One good-signal reading, `t` seconds after the session began.
public struct HRPoint: Sendable, Equatable, Codable {
    public let t: TimeInterval
    public let bpm: Int

    public init(t: TimeInterval, bpm: Int) {
        self.t = t
        self.bpm = bpm
    }
}

/// The HealthKit-facing kind of a training session.
public enum WorkoutKind: String, Sendable, Codable, CaseIterable, Identifiable {
    case jiujitsu
    case kickboxing

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .jiujitsu: return "Jiu-Jitsu"
        case .kickboxing: return "Kickboxing"
        }
    }
}

/// A stretch of the session where the ceiling game ran. Times are seconds
/// after the session began.
public struct SparringRound: Sendable, Equatable, Codable {
    public let start: TimeInterval
    public let end: TimeInterval
    public let ceilingBPM: Int
    public let resetBPM: Int
    public let timeoutCount: Int

    public init(start: TimeInterval, end: TimeInterval, ceilingBPM: Int, resetBPM: Int, timeoutCount: Int) {
        self.start = start
        self.end = end
        self.ceilingBPM = ceilingBPM
        self.resetBPM = resetBPM
        self.timeoutCount = timeoutCount
    }

    public var duration: TimeInterval { max(end - start, 0) }
}

public struct TrainingSummary: Sendable, Equatable {
    public let startedAt: Date
    public let duration: TimeInterval
    public let kind: WorkoutKind
    public let hrMax: Int
    public let points: [HRPoint]
    public let rounds: [SparringRound]
    /// Mean of the recorded readings; nil when none were recorded.
    public let averageBPM: Int?
    public let maxBPM: Int?
    public let timeoutCount: Int
    public let sparringSeconds: TimeInterval
    /// Time above each round's ceiling, summed over rounds.
    public let secondsOverCeiling: TimeInterval
    /// Per-minute active energy; empty without a calorie profile.
    public let energy: [EnergyInterval]
    /// nil when there is no calorie profile to estimate with.
    public let activeCalories: Double?

    public init(
        startedAt: Date,
        duration: TimeInterval,
        kind: WorkoutKind,
        hrMax: Int,
        points: [HRPoint],
        rounds: [SparringRound],
        profile: CalorieProfile?,
        maxGap: TimeInterval = HRPoint.maxGap
    ) {
        self.startedAt = startedAt
        self.duration = duration
        self.kind = kind
        self.hrMax = hrMax
        self.points = points
        self.rounds = rounds
        averageBPM = points.isEmpty
            ? nil
            : Int((Double(points.reduce(0) { $0 + $1.bpm }) / Double(points.count)).rounded())
        maxBPM = points.map(\.bpm).max()
        timeoutCount = rounds.reduce(0) { $0 + $1.timeoutCount }
        sparringSeconds = rounds.reduce(0) { $0 + $1.duration }
        secondsOverCeiling = rounds.reduce(0) { total, round in
            let inRound = points.filter { $0.t >= round.start && $0.t <= round.end }
            return total + Self.seconds(in: inRound, above: round.ceilingBPM, maxGap: maxGap)
        }
        if let profile {
            energy = CalorieEstimator.activeEnergy(points: points, profile: profile, maxGap: maxGap)
            activeCalories = energy.reduce(0) { $0 + $1.kcal }
        } else {
            energy = []
            activeCalories = nil
        }
    }

    /// Time between consecutive readings is credited to the earlier one.
    /// Intervals longer than `maxGap` (signal dropouts) are capped so a lost
    /// strap can't inflate the total.
    static func seconds(in points: [HRPoint], above bpm: Int, maxGap: TimeInterval) -> TimeInterval {
        guard points.count > 1 else { return 0 }
        var total: TimeInterval = 0
        for i in 0..<(points.count - 1) where points[i].bpm > bpm {
            total += min(max(points[i + 1].t - points[i].t, 0), maxGap)
        }
        return total
    }
}

extension HRPoint {
    /// Readings further apart than this are a dropout, not continuous data.
    public static let maxGap: TimeInterval = 5
}
