//
//  MetricSnapshot.swift
//  softwork
//
//  Lightweight on-launch cache of the last computed dashboard values so tiles
//  render instantly/offline before HealthKit refreshes. HealthKit remains the
//  source of truth. CloudKit-safe: every attribute is optional or defaulted,
//  and there are no relationships.
//

import Foundation
import SwiftData

@Model
final class MetricSnapshot {
    var capturedAt: Date = Date()
    var latestHRV: Double?
    var restingHR: Double?
    var todayActiveEnergy: Double?

    init(capturedAt: Date = Date(),
         latestHRV: Double? = nil,
         restingHR: Double? = nil,
         todayActiveEnergy: Double? = nil) {
        self.capturedAt = capturedAt
        self.latestHRV = latestHRV
        self.restingHR = restingHR
        self.todayActiveEnergy = todayActiveEnergy
    }
}
