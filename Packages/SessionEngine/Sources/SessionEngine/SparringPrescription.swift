//
//  SparringPrescription.swift
//  SessionEngine
//
//  Prescriptions are % of HRmax so a coach can prescribe without knowing an
//  athlete's max; each device resolves bpm locally (spec §5.3).
//

import Foundation

public struct SparringPrescription: Codable, Sendable, Hashable {
    public var ceilingPct: Double
    public var targetFloorPct: Double
    public var resetPct: Double
    public var resetHoldSeconds: Int
    public var minTimeoutSeconds: Int
    public var triggerSeconds: Int
    public var nearCeilingMarginPct: Double

    public init(
        ceilingPct: Double = 0.80,
        targetFloorPct: Double = 0.65,
        resetPct: Double = 0.70,
        resetHoldSeconds: Int = 10,
        minTimeoutSeconds: Int = 20,
        triggerSeconds: Int = 3,
        nearCeilingMarginPct: Double = 0.03
    ) {
        self.ceilingPct = ceilingPct
        self.targetFloorPct = targetFloorPct
        self.resetPct = resetPct
        self.resetHoldSeconds = resetHoldSeconds
        self.minTimeoutSeconds = minTimeoutSeconds
        self.triggerSeconds = triggerSeconds
        self.nearCeilingMarginPct = nearCeilingMarginPct
    }

    public enum ValidationError: Error, Equatable, Sendable {
        case resetNotBelowCeiling
        case floorNotBelowCeiling
        case bpmOutOfRange
        case nonPositiveDuration
    }

    public static let bpmRange = 40...220

    /// REQ-ZONE-2. Empty when the prescription resolves safely for `hrMax`.
    public func validate(hrMax: Int) -> [ValidationError] {
        var errors: [ValidationError] = []
        if resetPct >= ceilingPct { errors.append(.resetNotBelowCeiling) }
        if targetFloorPct >= ceilingPct { errors.append(.floorNotBelowCeiling) }
        let zone = ResolvedZone(prescription: self, hrMax: hrMax)
        if ![zone.ceilingBPM, zone.floorBPM, zone.resetBPM].allSatisfy(Self.bpmRange.contains) {
            errors.append(.bpmOutOfRange)
        }
        if resetHoldSeconds <= 0 || minTimeoutSeconds <= 0 || triggerSeconds <= 0 {
            errors.append(.nonPositiveDuration)
        }
        return errors
    }

    /// Resolved bpm thresholds, or nil when the prescription is invalid for `hrMax`.
    public func resolve(hrMax: Int) -> ResolvedZone? {
        validate(hrMax: hrMax).isEmpty ? ResolvedZone(prescription: self, hrMax: hrMax) : nil
    }
}

/// Where a live reading sits relative to the athlete's resolved zone.
public enum LiveBand: Sendable, Equatable {
    case belowTarget
    case inTarget
    case nearCeiling
    case overCeiling
}

public struct ResolvedZone: Sendable, Equatable {
    public let ceilingBPM: Int
    public let floorBPM: Int
    public let resetBPM: Int
    public let nearCeilingBPM: Int

    init(prescription p: SparringPrescription, hrMax: Int) {
        func bpm(_ pct: Double) -> Int { Int((pct * Double(hrMax)).rounded()) }
        ceilingBPM = bpm(p.ceilingPct)
        floorBPM = bpm(p.targetFloorPct)
        resetBPM = bpm(p.resetPct)
        nearCeilingBPM = bpm(p.ceilingPct - p.nearCeilingMarginPct)
    }

    public func band(for bpm: Int) -> LiveBand {
        if bpm > ceilingBPM { return .overCeiling }
        if bpm >= nearCeilingBPM { return .nearCeiling }
        if bpm >= floorBPM { return .inTarget }
        return .belowTarget
    }
}
