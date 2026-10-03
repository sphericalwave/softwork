//
//  CalorieEstimator.swift
//  SessionEngine
//
//  Heart-rate calorie estimate (Keytel et al. 2005, J Sports Sci 23:289),
//  which gives gross expenditure. Active energy — what HealthKit's
//  activeEnergyBurned means — subtracts resting expenditure, approximated as
//  1 MET (1 kcal per kg per hour) so no height is needed. Clamped at zero:
//  the formula is not meaningful near resting heart rate.
//

import Foundation

public struct CalorieProfile: Sendable, Equatable {
    public enum Sex: String, Sendable, Codable, CaseIterable, Identifiable {
        case male
        case female
        public var id: String { rawValue }
    }

    public let sex: Sex
    public let weightKg: Double
    public let age: Int

    public init(sex: Sex, weightKg: Double, age: Int) {
        self.sex = sex
        self.weightKg = weightKg
        self.age = age
    }
}

/// Active energy over a span of the session (seconds after it began).
public struct EnergyInterval: Sendable, Equatable {
    public let start: TimeInterval
    public let end: TimeInterval
    public let kcal: Double

    public init(start: TimeInterval, end: TimeInterval, kcal: Double) {
        self.start = start
        self.end = end
        self.kcal = kcal
    }
}

public enum CalorieEstimator {

    /// Keytel gross expenditure, kcal per minute.
    public static func grossKcalPerMinute(bpm: Int, profile p: CalorieProfile) -> Double {
        let hr = Double(bpm), w = p.weightKg, a = Double(p.age)
        let kJ: Double
        switch p.sex {
        case .male: kJ = -55.0969 + 0.6309 * hr + 0.1988 * w + 0.2017 * a
        case .female: kJ = -20.4022 + 0.4472 * hr - 0.1263 * w + 0.074 * a
        }
        return kJ / 4.184
    }

    /// Gross minus 1 MET, never negative.
    public static func activeKcalPerMinute(bpm: Int, profile: CalorieProfile) -> Double {
        max(grossKcalPerMinute(bpm: bpm, profile: profile) - profile.weightKg / 60, 0)
    }

    /// Active energy grouped into `bucket`-second intervals. Time between
    /// readings is credited at the earlier reading's rate and capped at
    /// `maxGap`, so a dropout adds nothing it didn't measure.
    public static func activeEnergy(
        points: [HRPoint],
        profile: CalorieProfile,
        maxGap: TimeInterval = HRPoint.maxGap,
        bucket: TimeInterval = 60
    ) -> [EnergyInterval] {
        guard points.count > 1, bucket > 0 else { return [] }
        var result: [EnergyInterval] = []
        var current: (index: Int, start: TimeInterval, end: TimeInterval, kcal: Double)?
        for i in 0..<(points.count - 1) {
            let p = points[i]
            let dt = min(max(points[i + 1].t - p.t, 0), maxGap)
            guard dt > 0 else { continue }
            let kcal = activeKcalPerMinute(bpm: p.bpm, profile: profile) * dt / 60
            let index = Int((p.t / bucket).rounded(.down))
            if let c = current, c.index == index {
                current = (index, c.start, p.t + dt, c.kcal + kcal)
            } else {
                if let c = current { result.append(EnergyInterval(start: c.start, end: c.end, kcal: c.kcal)) }
                current = (index, p.t, p.t + dt, kcal)
            }
        }
        if let c = current { result.append(EnergyInterval(start: c.start, end: c.end, kcal: c.kcal)) }
        return result
    }
}
