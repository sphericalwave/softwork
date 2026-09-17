//
//  TimeoutController.swift
//  SessionEngine
//
//  The timeout rule (spec §5.4) for any number of athletes: a timeout starts
//  when any athlete is above their ceiling for `triggerSeconds` consecutive
//  good-signal seconds, and ends only once every athlete has held at or below
//  their reset bpm for `resetHoldSeconds` and `minTimeoutSeconds` has elapsed.
//  Time is session-relative seconds supplied by the caller, so tests drive it
//  with a virtual clock.
//

import Foundation

public struct TimeoutController: Sendable {

    public enum Phase: Sendable, Equatable {
        case sparring
        case timeout(startT: TimeInterval, triggeredBy: Int)
        case resetReady(atT: TimeInterval)
    }

    public enum Signal: Sendable, Equatable {
        case timeoutStarted(triggeredBy: Int, t: TimeInterval)
        case resetReady(t: TimeInterval)
    }

    struct Tracker: Sendable {
        let zone: ResolvedZone
        var overSince: TimeInterval?
        var atResetSince: TimeInterval?
    }

    public private(set) var phase: Phase = .sparring
    private var trackers: [Tracker]
    private let prescription: SparringPrescription

    /// One resolved zone per athlete, indexed by athlete position.
    public init(prescription: SparringPrescription, zones: [ResolvedZone]) {
        precondition(!zones.isEmpty, "TimeoutController needs at least one athlete")
        self.prescription = prescription
        self.trackers = zones.map { Tracker(zone: $0) }
    }

    /// Feed one reading. A reading without good signal breaks both streaks:
    /// neither a trigger nor a reset may be confirmed on bad data.
    public mutating func ingest(athlete: Int, bpm: Int, signalGood: Bool, t: TimeInterval) -> [Signal] {
        var tracker = trackers[athlete]
        if signalGood {
            if bpm > tracker.zone.ceilingBPM {
                tracker.overSince = tracker.overSince ?? t
            } else {
                tracker.overSince = nil
            }
            if bpm <= tracker.zone.resetBPM {
                tracker.atResetSince = tracker.atResetSince ?? t
            } else {
                tracker.atResetSince = nil
            }
        } else {
            tracker.overSince = nil
            tracker.atResetSince = nil
        }
        trackers[athlete] = tracker
        return evaluate(t: t)
    }

    /// Re-evaluate without a new reading, so the minimum timeout can elapse
    /// between samples.
    public mutating func tick(t: TimeInterval) -> [Signal] {
        evaluate(t: t)
    }

    /// Leave `resetReady` after the resume countdown. Streaks restart so a
    /// reading from before the timeout can't count toward the next trigger.
    public mutating func resume() {
        guard case .resetReady = phase else { return }
        for i in trackers.indices {
            trackers[i].overSince = nil
            trackers[i].atResetSince = nil
        }
        phase = .sparring
    }

    private mutating func evaluate(t: TimeInterval) -> [Signal] {
        switch phase {
        case .sparring:
            let trigger = TimeInterval(prescription.triggerSeconds)
            if let athlete = trackers.firstIndex(where: { tracker in
                tracker.overSince.map { t - $0 >= trigger } ?? false
            }) {
                phase = .timeout(startT: t, triggeredBy: athlete)
                return [.timeoutStarted(triggeredBy: athlete, t: t)]
            }
            return []
        case .timeout(let startT, _):
            let hold = TimeInterval(prescription.resetHoldSeconds)
            let allReset = trackers.allSatisfy { tracker in
                tracker.atResetSince.map { t - $0 >= hold } ?? false
            }
            if allReset && t - startT >= TimeInterval(prescription.minTimeoutSeconds) {
                phase = .resetReady(atT: t)
                return [.resetReady(t: t)]
            }
            return []
        case .resetReady:
            return []
        }
    }
}
