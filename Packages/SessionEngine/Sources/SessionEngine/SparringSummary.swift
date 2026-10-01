//
//  SparringSummary.swift
//  SessionEngine
//
//  End-of-session numbers derived only from what the strap actually
//  reported — no modelled values (calories, fat burn) here.
//

import Foundation

/// One good-signal reading, `t` seconds after sparring began.
public struct HRPoint: Sendable, Equatable {
    public let t: TimeInterval
    public let bpm: Int

    public init(t: TimeInterval, bpm: Int) {
        self.t = t
        self.bpm = bpm
    }
}

public struct SparringSummary: Sendable, Equatable {
    public let startedAt: Date
    public let duration: TimeInterval
    public let points: [HRPoint]
    public let zone: ResolvedZone
    public let hrMax: Int
    public let timeoutCount: Int
    /// Mean of the recorded readings; nil when none were recorded.
    public let averageBPM: Int?
    public let maxBPM: Int?
    public let secondsOverCeiling: TimeInterval

    public init(
        startedAt: Date,
        duration: TimeInterval,
        points: [HRPoint],
        zone: ResolvedZone,
        hrMax: Int,
        timeoutCount: Int,
        maxGap: TimeInterval = 5
    ) {
        self.startedAt = startedAt
        self.duration = duration
        self.points = points
        self.zone = zone
        self.hrMax = hrMax
        self.timeoutCount = timeoutCount
        averageBPM = points.isEmpty
            ? nil
            : Int((Double(points.reduce(0) { $0 + $1.bpm }) / Double(points.count)).rounded())
        maxBPM = points.map(\.bpm).max()
        secondsOverCeiling = Self.seconds(in: points, above: zone.ceilingBPM, maxGap: maxGap)
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
