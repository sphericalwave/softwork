//
//  WorkoutDuplicate.swift
//  SessionEngine
//
//  Recreating a session that was trained but never recorded from a similar
//  past one: where the copy lands in time, what it would overlap, and the
//  numbers it carries over.
//

import Foundation

public enum WorkoutDuplicate {
    /// `day` at `source`'s time of day.
    public static func start(on day: Date, atTimeOf source: Date, calendar: Calendar = .current) -> Date {
        let time = calendar.dateComponents([.hour, .minute, .second], from: source)
        return calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0,
                             of: day) ?? day
    }

    /// Where a new copy starts by default: today at the source's time of day,
    /// or yesterday if that copy wouldn't have finished yet.
    public static func defaultStart(for sourceStart: Date, duration: TimeInterval, now: Date = Date(),
                                    calendar: Calendar = .current) -> Date {
        let today = start(on: now, atTimeOf: sourceStart, calendar: calendar)
        if today.addingTimeInterval(duration) <= now { return today }
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        return start(on: yesterday, atTimeOf: sourceStart, calendar: calendar)
    }

    /// `points` (seconds from the source's start) fitted to `duration` and
    /// placed at `start`, earliest first.
    public static func shifted(_ points: [HRPoint], sourceDuration: TimeInterval,
                               to start: Date, duration: TimeInterval) -> [(date: Date, bpm: Int)] {
        HeartRateCopy.scaled(points, from: sourceDuration, to: duration)
            .map { (start.addingTimeInterval($0.t), $0.bpm) }
    }

    /// Indexes of `existing` that share any time with `start..<start+duration`.
    /// Touching end to start isn't an overlap.
    public static func overlapping(start: Date, duration: TimeInterval, existing: [DateInterval]) -> [Int] {
        let end = start.addingTimeInterval(duration)
        return existing.indices.filter { existing[$0].start < end && existing[$0].end > start }
    }

    /// Energy for the copy, scaled by length; nil when the source had none.
    public static func scaledEnergy(_ kcal: Double?, from sourceDuration: TimeInterval,
                                    to duration: TimeInterval) -> Double? {
        guard let kcal, kcal > 0, sourceDuration > 0, duration > 0 else { return nil }
        return kcal * duration / sourceDuration
    }

    /// Rounded mean and max bpm, as a session summary stores them; nil when empty.
    public static func bpmSummary(_ points: [HRPoint]) -> (average: Int, max: Int)? {
        guard let max = points.map(\.bpm).max() else { return nil }
        let average = Int((Double(points.reduce(0) { $0 + $1.bpm }) / Double(points.count)).rounded())
        return (average, max)
    }
}
