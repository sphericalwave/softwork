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
    /// Some of its heart rate was copied from another workout. Optional so
    /// intensities cached before this field still decode.
    var hasEstimatedHR: Bool? = nil
    /// Made with Duplicate To… from this workout. Optional for old caches too.
    var duplicatedFrom: UUID? = nil
    /// `HKMetadataKeyWorkoutBrandName`, e.g. "Jiu-Jitsu" on a Martial Arts
    /// workout flow saved. Optional for old caches too.
    var brandName: String? = nil
    /// Active energy burned during the workout, kcal; nil when Health has none.
    /// Optional for old caches too.
    var activeKcal: Double? = nil
    /// Highest and mean bpm over the workout, for the header charts; nil
    /// without heart rate. Optional for old caches too.
    var peakBPM: Int? = nil
    var avgBPM: Double? = nil

    var activityType: HKWorkoutActivityType { HKWorkoutActivityType(rawValue: activityTypeRaw) ?? .other }
    var totalZonedSeconds: TimeInterval { zoneSeconds.values.reduce(0, +) }
}

@MainActor
final class WorkoutIntensityService {

    private let store: HKHealthStore

    init(store: HKHealthStore) {
        self.store = store
    }

    /// Workouts started since `start`, newest first, each with its
    /// zone distribution computed against `hrMax`.
    func intensities(since start: Date, hrMax: Int) async throws -> [WorkoutIntensity] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil, options: .strictStartDate)
        return try await intensities(predicate: predicate, limit: HKObjectQueryNoLimit, hrMax: hrMax)
    }

    /// Up to `limit` workouts started before `date`, newest first: the next
    /// page of the list.
    func intensities(before date: Date, limit: Int, hrMax: Int) async throws -> [WorkoutIntensity] {
        let predicate = HKQuery.predicateForSamples(withStart: nil, end: date, options: .strictStartDate)
        return try await intensities(predicate: predicate, limit: limit, hrMax: hrMax)
    }

    private func intensities(predicate: NSPredicate, limit: Int, hrMax: Int) async throws -> [WorkoutIntensity] {
        let workouts = try await workouts(predicate: predicate, limit: limit).withoutBioMechanicShadows()

        var out: [WorkoutIntensity] = []
        for workout in workouts {
            let samples = try await Self.heartRateSamples(store: store, from: workout.startDate, to: workout.endDate)
            let readings = samples.map { (date: $0.startDate, bpm: Self.bpm($0)) }
            let zones = ZoneBucketer.distribution(samples: readings, hrMax: hrMax)
            var avgPct: Double? = nil
            var meanBpm: Double? = nil
            if !readings.isEmpty {
                let sumBpm = readings.map(\.bpm).reduce(0, +)
                meanBpm = Double(sumBpm) / Double(readings.count)
                avgPct = meanBpm.map { $0 / Double(hrMax) * 100 }
            }
            out.append(WorkoutIntensity(
                id: workout.uuid,
                start: workout.startDate,
                activityTypeRaw: workout.workoutActivityType.rawValue,
                duration: workout.duration,
                zoneSeconds: zones,
                avgPercentOfMax: avgPct,
                hasEstimatedHR: samples.contains { $0.metadata?[HeartRateCopyService.estimatedKey] != nil },
                duplicatedFrom: (workout.metadata?[WorkoutDuplicateService.duplicatedFromKey] as? String)
                    .flatMap(UUID.init(uuidString:)),
                brandName: workout.metadata?[HKMetadataKeyWorkoutBrandName] as? String,
                activeKcal: try? await activeKcal(of: workout),
                peakBPM: readings.map(\.bpm).max(),
                avgBPM: meanBpm
            ))
        }
        return out.sorted { $0.start > $1.start }
    }

    // MARK: - Queries

    private func workouts(predicate: NSPredicate, limit: Int) async throws -> [HKWorkout] {
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[HKWorkout], Error>) in
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate,
                                      limit: limit, sortDescriptors: [sort]) { _, samples, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(query)
        }
    }

    /// The workout's own active energy statistic, else the sum of active energy
    /// samples over its interval (for workouts saved without associated samples).
    private func activeKcal(of workout: HKWorkout) async throws -> Double? {
        let type = HKQuantityType(.activeEnergyBurned)
        if let sum = workout.statistics(for: type)?.sumQuantity() {
            return sum.doubleValue(for: .kilocalorie())
        }
        let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate)
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Double?, Error>) in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate,
                                          options: .cumulativeSum) { _, stats, error in
                if let error = error as? HKError, error.code == .errorNoData { cont.resume(returning: nil); return }
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: .kilocalorie()))
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

    /// The workout's heart-rate samples as CSV (`timestamp,bpm,hrmax,kcal`), for the
    /// youtube-uploader's hr-overlay.swift video script. Timestamps are UTC ISO 8601 with millis.
    /// `kcal` is active energy burned since the workout start, one decimal; empty when Health
    /// has no active energy for the workout.
    nonisolated static func heartRateCSV(store: HKHealthStore, from start: Date, to end: Date,
                                         hrMax: Int) async throws -> Data {
        let samples = try await heartRateSamples(store: store, from: start, to: end)
        let energy = try await activeEnergyBuckets(store: store, from: start, to: end)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var csv = "timestamp,bpm,hrmax,kcal\n"
        for sample in samples {
            let kcal = energy.isEmpty ? "" : String(format: "%.1f", cumulativeKcal(energy, at: sample.startDate))
            csv += "\(formatter.string(from: sample.startDate)),\(bpm(sample)),\(hrMax),\(kcal)\n"
        }
        return Data(csv.utf8)
    }

    nonisolated private static let energyBucketSeconds = 5

    /// Active energy per 5 s bucket from `start`, ascending. A statistics query so overlapping
    /// Watch and iPhone samples are merged rather than double counted.
    nonisolated private static func activeEnergyBuckets(store: HKHealthStore, from start: Date,
                                                        to end: Date) async throws -> [(start: Date, kcal: Double)] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        var interval = DateComponents()
        interval.second = energyBucketSeconds
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[(start: Date, kcal: Double)], Error>) in
            let query = HKStatisticsCollectionQuery(quantityType: HKQuantityType(.activeEnergyBurned),
                                                    quantitySamplePredicate: predicate,
                                                    options: .cumulativeSum,
                                                    anchorDate: start,
                                                    intervalComponents: interval)
            query.initialResultsHandler = { _, results, error in
                if let error { cont.resume(throwing: error); return }
                var out: [(start: Date, kcal: Double)] = []
                results?.enumerateStatistics(from: start, to: end) { stats, _ in
                    if let sum = stats.sumQuantity() {
                        out.append((stats.startDate, sum.doubleValue(for: .kilocalorie())))
                    }
                }
                cont.resume(returning: out)
            }
            store.execute(query)
        }
    }

    /// Energy from buckets finished by `date`, plus the elapsed share of the bucket it falls in.
    nonisolated private static func cumulativeKcal(_ buckets: [(start: Date, kcal: Double)], at date: Date) -> Double {
        let length = Double(energyBucketSeconds)
        var total = 0.0
        for bucket in buckets {
            let elapsed = date.timeIntervalSince(bucket.start)
            if elapsed <= 0 { break }
            total += bucket.kcal * min(elapsed / length, 1)
        }
        return total
    }
}
