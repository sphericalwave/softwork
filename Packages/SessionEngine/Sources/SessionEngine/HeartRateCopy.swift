//
//  HeartRateCopy.swift
//  SessionEngine
//
//  Borrowing a similar past workout's heart rate for one whose sensor
//  failed: rank likely sources, stretch the source's trace onto the target's
//  length, and keep any real readings the target did record.
//

import Foundation

public enum HeartRateCopy {
    /// Copied readings this close to a real reading are dropped, so what the
    /// sensor did record always wins over the estimate.
    public static let realDataWindow: TimeInterval = 15

    /// `source` (seconds from the source's start) stretched or squeezed so
    /// the source's whole length maps onto `targetDuration`.
    public static func scaled(_ source: [HRPoint], from sourceDuration: TimeInterval,
                              to targetDuration: TimeInterval) -> [HRPoint] {
        guard sourceDuration > 0, targetDuration > 0 else { return [] }
        let factor = targetDuration / sourceDuration
        return source
            .filter { $0.t >= 0 && $0.t <= sourceDuration }
            .sorted { $0.t < $1.t }
            .map { HRPoint(t: $0.t * factor, bpm: $0.bpm) }
    }

    /// `copied` minus readings within `window` seconds of a real reading at `kept`.
    public static func fillingGaps(_ copied: [HRPoint], around kept: [TimeInterval],
                                   window: TimeInterval = realDataWindow) -> [HRPoint] {
        guard !kept.isEmpty else { return copied }
        let kept = kept.sorted()
        var i = 0
        return copied.sorted { $0.t < $1.t }.filter { point in
            // Both sorted: advance to the first kept reading not too far behind.
            while i < kept.count && kept[i] < point.t - window { i += 1 }
            return i == kept.count || kept[i] > point.t + window
        }
    }

    /// Lower is a better source. Same kind of workout matters most, then how
    /// close its length is (a 60 vs 90 min roll differs more than 60 vs 65),
    /// then recency as a tiebreak.
    public static func score(sameKind: Bool, sourceDuration: TimeInterval,
                             targetDuration: TimeInterval, daysApart: Double) -> Double {
        let lengthPenalty = (sourceDuration > 0 && targetDuration > 0)
            ? abs(log(sourceDuration / targetDuration)) : 3
        return (sameKind ? 0 : 2) + lengthPenalty + abs(daysApart) / 365
    }

    /// Worth suggesting first: same kind and within half to double the length.
    public static func isSimilar(sameKind: Bool, sourceDuration: TimeInterval,
                                 targetDuration: TimeInterval) -> Bool {
        guard sameKind, sourceDuration > 0, targetDuration > 0 else { return false }
        return (0.5...2).contains(sourceDuration / targetDuration)
    }
}
