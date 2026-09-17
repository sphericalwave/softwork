//
//  HRZone.swift
//  flow
//
//  The five classic heart-rate training zones, expressed as % of HR max.
//  Pure and testable — no HealthKit here.
//

import SwiftUI

enum HRZone: Int, CaseIterable, Identifiable {
    case z1 = 1   // Recovery   50–60%
    case z2       // Endurance  60–70%
    case z3       // Tempo      70–80%
    case z4       // Threshold  80–90%
    case z5       // Max        90–100%+

    var id: Int { rawValue }

    /// Inclusive lower bound as a percentage of HR max.
    var lowerPercent: Double {
        switch self {
        case .z1: return 50
        case .z2: return 60
        case .z3: return 70
        case .z4: return 80
        case .z5: return 90
        }
    }

    var label: String {
        switch self {
        case .z1: return "Z1"
        case .z2: return "Z2"
        case .z3: return "Z3"
        case .z4: return "Z4"
        case .z5: return "Z5"
        }
    }

    var name: String {
        switch self {
        case .z1: return "Recovery"
        case .z2: return "Endurance"
        case .z3: return "Tempo"
        case .z4: return "Threshold"
        case .z5: return "Max"
        }
    }

    var color: Color {
        switch self {
        case .z1: return .blue
        case .z2: return .green
        case .z3: return .yellow
        case .z4: return .orange
        case .z5: return .red
        }
    }

    /// Maps a heart rate expressed as a percentage of HR max onto a zone.
    /// Anything below the Z2 threshold (incl. sub-50% rest) reads as Z1.
    static func zone(forPercent percent: Double) -> HRZone {
        switch percent {
        case ..<60:  return .z1
        case ..<70:  return .z2
        case ..<80:  return .z3
        case ..<90:  return .z4
        default:     return .z5
        }
    }
}

/// Pure time-in-zone accumulation, decoupled from HealthKit so it is unit-testable.
enum ZoneBucketer {

    /// Attributes elapsed time between consecutive HR samples to the zone of the
    /// earlier sample. Gaps longer than `maxGap` (e.g. sensor dropouts) are capped
    /// so a paused workout doesn't dump minutes into one zone.
    /// - Parameters:
    ///   - samples: `(date, bpm)` readings, any order.
    ///   - hrMax: resolved max heart rate (bpm). Non-positive → empty result.
    ///   - maxGap: cap applied to each inter-sample interval, in seconds.
    static func distribution(
        samples: [(date: Date, bpm: Int)],
        hrMax: Int,
        maxGap: TimeInterval = 30
    ) -> [HRZone: TimeInterval] {
        guard hrMax > 0, samples.count > 1 else { return [:] }
        let sorted = samples.sorted { $0.date < $1.date }
        var result: [HRZone: TimeInterval] = [:]
        for i in 0..<(sorted.count - 1) {
            let a = sorted[i]
            let delta = min(sorted[i + 1].date.timeIntervalSince(a.date), maxGap)
            guard delta > 0 else { continue }
            let percent = Double(a.bpm) / Double(hrMax) * 100
            result[HRZone.zone(forPercent: percent), default: 0] += delta
        }
        return result
    }
}
