//
//  HealthKitService.swift
//  flow
//
//  Read-only HealthKit access for the big-picture dashboard: daily HRV,
//  active energy, resting HR aggregations plus latest values and age.
//  Daily-aggregation approach adapted from fitwrench's HealthKitWeeklyService.
//

import Foundation
import HealthKit
import Combine
import AthleteFeatures

enum HealthError: Error {
    case notAvailable
    case invalidType
}

@MainActor
final class HealthKitService: ObservableObject {

    let store = HKHealthStore()

    @Published private(set) var isAuthorized = false

    // MARK: - Authorization

    private var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        for id in [HKQuantityTypeIdentifier.heartRateVariabilitySDNN,
                   .activeEnergyBurned, .heartRate, .restingHeartRate] {
            if let t = HKQuantityType.quantityType(forIdentifier: id) { types.insert(t) }
        }
        if let dob = HKCharacteristicType.characteristicType(forIdentifier: .dateOfBirth) {
            types.insert(dob)
        }
        types.insert(HKObjectType.workoutType())
        return types
    }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthError.notAvailable }
        // Training-session types too, so the user answers one sheet covering
        // everything instead of a second one at Start Training.
        try await store.requestAuthorization(toShare: TrainingHealthTypes.share,
                                             read: readTypes.union(TrainingHealthTypes.read))
        isAuthorized = true
    }

    // MARK: - Daily aggregations

    /// Average HRV per bucket (hour for a day window, day otherwise).
    func averageHRV(in window: DashboardViewModel.TimeWindow) async throws -> [Date: Double] {
        let unit = HKUnit.secondUnit(with: .milli)
        let (start, end) = window.dates
        return try await statisticsCollection(.heartRateVariabilitySDNN, from: start, to: end,
                                               bucket: window.bucket, options: .discreteAverage) {
            $0.averageQuantity()?.doubleValue(for: unit)
        }
    }

    /// Active energy per bucket (hour for a day window, day otherwise).
    func sumActiveEnergy(in window: DashboardViewModel.TimeWindow) async throws -> [Date: Double] {
        let unit = HKUnit.largeCalorie()
        let (start, end) = window.dates
        return try await statisticsCollection(.activeEnergyBurned, from: start, to: end,
                                               bucket: window.bucket, options: .cumulativeSum) {
            $0.sumQuantity()?.doubleValue(for: unit)
        }
    }

    func dailyAverageRestingHR(days: Int) async throws -> [Date: Double] {
        let unit = HKUnit.count().unitDivided(by: .minute())
        let (start, end) = Self.windowDates(days: days)
        return try await statisticsCollection(.restingHeartRate, from: start, to: end,
                                               bucket: .day, options: .discreteAverage) {
            $0.averageQuantity()?.doubleValue(for: unit)
        }
    }

    // MARK: - Latest / today values

    func latestHRV() async throws -> Double? {
        try await mostRecent(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli))
    }

    func latestRestingHR() async throws -> Double? {
        try await mostRecent(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()))
    }

    /// Total active energy (kcal) burned since local midnight today.
    func todayActiveEnergy() async throws -> Double? {
        let (start, end) = DashboardViewModel.TimeWindow.day.dates
        let unit = HKUnit.largeCalorie()
        let today = try await statisticsCollection(.activeEnergyBurned, from: start, to: end,
                                                   bucket: .day, options: .cumulativeSum) {
            $0.sumQuantity()?.doubleValue(for: unit)
        }
        return today[start]
    }

    // MARK: - Age

    /// Age in whole years from the HealthKit date-of-birth characteristic, or nil.
    func ageInYears() -> Int? {
        guard let components = try? store.dateOfBirthComponents(),
              let birthDate = Calendar.current.date(from: components) else { return nil }
        return Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year
    }

    // MARK: - Internals

    static func windowDates(days: Int) -> (Date, Date) {
        let cal = Calendar.current
        let endOfToday = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? Date()
        let start = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: Date())) ?? Date()
        return (start, endOfToday)
    }

    private func statisticsCollection(
        _ identifier: HKQuantityTypeIdentifier,
        from start: Date,
        to end: Date,
        bucket: Calendar.Component,
        options: HKStatisticsOptions,
        extract: @escaping (HKStatistics) -> Double?
    ) async throws -> [Date: Double] {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            throw HealthError.invalidType
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let anchor = Calendar.current.startOfDay(for: start)
        var interval = DateComponents()
        interval.setValue(1, for: bucket)

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[Date: Double], Error>) in
            let query = HKStatisticsCollectionQuery(quantityType: type,
                                                    quantitySamplePredicate: predicate,
                                                    options: options,
                                                    anchorDate: anchor,
                                                    intervalComponents: interval)
            query.initialResultsHandler = { _, results, error in
                if let error { cont.resume(throwing: error); return }
                guard let results else { cont.resume(returning: [:]); return }
                var out: [Date: Double] = [:]
                results.enumerateStatistics(from: start, to: end) { stats, _ in
                    if let v = extract(stats) { out[stats.startDate] = v }
                }
                cont.resume(returning: out)
            }
            store.execute(query)
        }
    }

    private func mostRecent(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            throw HealthError.invalidType
        }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Double?, Error>) in
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1,
                                      sortDescriptors: [sort]) { _, samples, error in
                if let error { cont.resume(throwing: error); return }
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                cont.resume(returning: value)
            }
            store.execute(query)
        }
    }
}
