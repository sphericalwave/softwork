//
//  WorkoutIntensityService.swift
//  flow
//
//  Reads recent workouts and their heart-rate samples, then buckets time into
//  HR zones as a percentage of HR max. This is the app's distinctive capability.
//

import Foundation
import HealthKit
import SessionEngine

/// A workout plus its time-in-zone breakdown and average intensity.
/// Codable so the last result can be cached and shown at launch.
struct WorkoutIntensity: Identifiable, Codable {
    let id: UUID
    let start: Date
    let activityTypeRaw: UInt
    let duration: TimeInterval
    let zoneSeconds: [HRZone: TimeInterval]
    let avgPercentOfMax: Double?

    var activityType: HKWorkoutActivityType { HKWorkoutActivityType(rawValue: activityTypeRaw) ?? .other }
    var totalZonedSeconds: TimeInterval { zoneSeconds.values.reduce(0, +) }
}

@MainActor
final class WorkoutIntensityService {

    private let store: HKHealthStore

    init(store: HKHealthStore) {
        self.store = store
    }

    /// Workouts started within `window`, newest first, each with its
    /// zone distribution computed against `hrMax`.
    func recentIntensities(in window: DashboardViewModel.TimeWindow, hrMax: Int) async throws -> [WorkoutIntensity] {
        let (start, end) = window.dates
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let workouts = try await workouts(predicate: predicate)

        var out: [WorkoutIntensity] = []
        for workout in workouts {
            let samples = try await Self.heartRateSamples(store: store, from: workout.startDate, to: workout.endDate)
            let readings = samples.map { (date: $0.startDate, bpm: Self.bpm($0)) }
            let zones = ZoneBucketer.distribution(samples: readings, hrMax: hrMax)
            var avgPct: Double? = nil
            if !readings.isEmpty {
                let sumBpm = readings.map(\.bpm).reduce(0, +)
                let meanBpm = Double(sumBpm) / Double(readings.count)
                avgPct = meanBpm / Double(hrMax) * 100
            }
            out.append(WorkoutIntensity(
                id: workout.uuid,
                start: workout.startDate,
                activityTypeRaw: workout.workoutActivityType.rawValue,
                duration: workout.duration,
                zoneSeconds: zones,
                avgPercentOfMax: avgPct
            ))
        }
        return out.sorted { $0.start > $1.start }
    }

    // MARK: - Queries

    private func workouts(predicate: NSPredicate) async throws -> [HKWorkout] {
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[HKWorkout], Error>) in
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(query)
        }
    }

    nonisolated private static func heartRateSamples(store: HKHealthStore, from start: Date,
                                                     to end: Date) async throws -> [HKQuantitySample] {
        let hrType = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[HKQuantitySample], Error>) in
            let query = HKSampleQuery(sampleType: hrType, predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            store.execute(query)
        }
    }

    nonisolated private static func bpm(_ sample: HKQuantitySample) -> Int {
        let unit = HKUnit.count().unitDivided(by: .minute())
        return Int(sample.quantity.doubleValue(for: unit).rounded())
    }

    // MARK: - Export

    /// The workout's heart-rate samples as CSV (`timestamp,bpm,hrmax`), for the
    /// Tools/hr-overlay video script. Timestamps are UTC ISO 8601 with millis.
    nonisolated static func heartRateCSV(store: HKHealthStore, from start: Date, to end: Date,
                                         hrMax: Int) async throws -> Data {
        let samples = try await heartRateSamples(store: store, from: start, to: end)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var csv = "timestamp,bpm,hrmax\n"
        for sample in samples {
            csv += "\(formatter.string(from: sample.startDate)),\(bpm(sample)),\(hrMax)\n"
        }
        return Data(csv.utf8)
    }
}
