//
//  DashboardViewModel.swift
//  flow
//
//  Orchestrates HealthKit loads for the Overview and Intensity screens and
//  writes the last-known values into the MetricSnapshot cache.
//

import Foundation
import SwiftData
import HealthKit
import Combine
import SessionEngine
import DiagnosticsKit
import SwCharts
import Persistence

@MainActor
final class DashboardViewModel: ObservableObject {

    /// Raw value is the window's length in days (persisted via @AppStorage;
    /// an unknown stored value falls back to `.week`).
    enum TimeWindow: Int, CaseIterable, Identifiable {
        case day = 1, week = 7, month = 30
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .day: return "D"
            case .week: return "W"
            case .month: return "M"
            }
        }

        /// From the start of the first day in the window to the end of today.
        var dates: (start: Date, end: Date) {
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            let end = cal.date(byAdding: .day, value: 1, to: today) ?? Date()
            let start = cal.date(byAdding: .day, value: 1 - rawValue, to: today) ?? today
            return (start, end)
        }
    }

    // Tiles
    @Published var latestHRV: Double?
    @Published var restingHR: Double?
    @Published var todayActiveEnergy: Double?

    // Trends: one sample per day, a year back, bucketed by the Overview's
    // D/W/M picker.
    @Published var hrvSamples: [DatedSample] = []
    @Published var activeEnergySamples: [DatedSample] = []

    /// Covers the 12-month window (current month + 11 before).
    private static let trendDays = 366

    // Intensity: every workout, newest first. A refresh loads the year the
    // header charts cover; older ones load a page at a time as the list scrolls.
    @Published var intensities: [WorkoutIntensity] = [] {
        didSet {
            peakHRSamples = Self.peakHRSamples(intensities)
            averageHRSamples = Self.averageHRSamples(intensities)
        }
    }
    @Published private(set) var peakHRSamples: [DatedSample] = []
    @Published private(set) var averageHRSamples: [DatedSample] = []
    /// False once a page comes back empty: Health has no older workouts.
    @Published private(set) var canLoadOlder = true
    private var isLoadingOlder = false
    private static let olderPageSize = 25

    @Published var isLoading = false
    @Published var errorMessage: String?
    /// HR max used for the last Intensity load; nil until the first refresh.
    @Published private(set) var hrMax: Int?

    private let health: HealthKitService
    private let intensityService: WorkoutIntensityService

    init(health: HealthKitService) {
        self.health = health
        self.intensityService = WorkoutIntensityService(store: health.store)
    }

    /// The workout's heart rate as a CSV for the video overlay script.
    func heartRateCSV(for workout: WorkoutIntensity, name: String) -> HeartRateCSV? {
        guard let hrMax else { return nil }
        return HeartRateCSV(store: health.store, start: workout.start,
                            end: workout.start.addingTimeInterval(workout.duration), hrMax: hrMax,
                            workoutName: name)
    }

    /// The sheet model for filling in `workout`'s heart rate from a similar one.
    func copyHeartRate(for workout: WorkoutIntensity, title: String, session: CopyHeartRateViewModel.LinkedSession?,
                       titleFor: @escaping @MainActor (UUID, HKWorkoutActivityType) -> String) -> CopyHeartRateViewModel {
        CopyHeartRateViewModel(target: .init(id: workout.id, start: workout.start,
                                             duration: workout.duration, title: title),
                               session: session,
                               service: HeartRateCopyService(store: health.store), titleFor: titleFor)
    }

    /// The sheet model for duplicating `workout` onto a day it wasn't recorded.
    /// `session` is flow's session for it, if any; otherwise its tag sets the kind.
    func duplicate(_ workout: WorkoutIntensity, session: TrainingSessionRecord?, tag: WorkoutTag?, title: String,
                   titleFor: @escaping @MainActor (UUID, HKWorkoutActivityType) -> String) -> DuplicateWorkoutViewModel {
        let kindRaw = session?.kindRaw ?? tag?.rawValue
            ?? Self.kind(for: workout.activityType).rawValue
        let hrMax = session.map(\.hrMax).flatMap { $0 > 0 ? $0 : nil } ?? self.hrMax ?? 0
        return DuplicateWorkoutViewModel(source: .init(id: workout.id, start: workout.start, duration: workout.duration,
                                                       title: title, kindRaw: kindRaw, notes: session?.notes ?? "",
                                                       hrMax: hrMax),
                                         service: WorkoutDuplicateService(store: health.store),
                                         heartRate: HeartRateCopyService(store: health.store), titleFor: titleFor)
    }

    /// The training kind a Health activity type was saved from.
    private static func kind(for type: HKWorkoutActivityType) -> WorkoutKind {
        switch type {
        case .kickboxing: return .kickboxing
        case .martialArts: return .jiujitsu
        default: return .wrestling
        }
    }

    /// Deletes a flow session and its workout, heart rate and energy from Health.
    func delete(_ session: TrainingSessionRecord, context: ModelContext) async throws {
        try await WorkoutDeletionService(store: health.store).delete(session, context: context)
    }

    /// Seed tiles from the cached snapshot so the UI isn't empty on launch.
    func primeFromCache(_ snapshot: MetricSnapshot?) {
        guard let snapshot else { return }
        latestHRV = latestHRV ?? snapshot.latestHRV
        restingHR = restingHR ?? snapshot.restingHR
        todayActiveEnergy = todayActiveEnergy ?? snapshot.todayActiveEnergy
    }

    func refresh(hrMaxOverride: Int, formula: MaxHRFormula, context: ModelContext) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let hrv = health.latestHRV()
            async let resting = health.latestRestingHR()
            async let energy = health.todayActiveEnergy()
            async let hrvSeries = health.dailyAverageHRV(days: Self.trendDays)
            async let energySeries = health.dailyActiveEnergy(days: Self.trendDays)

            latestHRV = try await hrv
            restingHR = try await resting
            todayActiveEnergy = try await energy
            hrvSamples = Self.samples(try await hrvSeries)
            activeEnergySamples = Self.samples(try await energySeries)

            saveSnapshot(context: context)
        } catch {
            ErrorLog.shared.error("Dashboard", "Dashboard load failed", error: error)
            errorMessage = error.localizedDescription
        }

        // Separate from the metrics above so a failed HRV or energy query
        // can't leave Intensity empty.
        do {
            let hrMax = MaxHeartRate.effective(override: hrMaxOverride, age: health.ageInYears(), formula: formula)
            self.hrMax = hrMax
            let start = Calendar.current.date(byAdding: .day, value: -Self.trendDays,
                                              to: Calendar.current.startOfDay(for: .now)) ?? .now
            var loaded = try await intensityService.intensities(since: start, hrMax: hrMax)
            // Nothing this year: start the list with the most recent older page.
            if loaded.isEmpty {
                loaded = try await intensityService.intensities(before: start, limit: Self.olderPageSize, hrMax: hrMax)
            }
            intensities = loaded
            canLoadOlder = true
            Self.cacheIntensities(intensities)
        } catch {
            ErrorLog.shared.error("Dashboard", "Workout intensity load failed", error: error)
            errorMessage = error.localizedDescription
        }
    }

    /// Appends the next page of workouts older than the oldest listed.
    func loadOlderIntensities() async {
        guard canLoadOlder, !isLoadingOlder, !isLoading, let hrMax, let oldest = intensities.last?.start else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        do {
            let page = try await intensityService.intensities(before: oldest, limit: Self.olderPageSize, hrMax: hrMax)
            // A refresh replaced the list meanwhile; this page no longer follows it.
            guard intensities.last?.start == oldest else { return }
            intensities += page
            // Not `count < pageSize`: deduping shadows can shorten a page that isn't the last.
            canLoadOlder = !page.isEmpty
        } catch {
            ErrorLog.shared.error("Dashboard", "Older workout load failed", error: error)
            canLoadOlder = false
        }
    }

    private static func samples(_ daily: [Date: Double]) -> [DatedSample] {
        daily.map { DatedSample(date: $0.key, value: $0.value) }
    }

    /// Each workout's peak heart rate, for the header's `.max` chart.
    private static func peakHRSamples(_ intensities: [WorkoutIntensity]) -> [DatedSample] {
        intensities.compactMap { workout in
            workout.peakBPM.map { DatedSample(date: workout.start, value: Double($0)) }
        }
    }

    /// One sample per day: the workouts' average heart rate weighted by
    /// duration, so a 90-minute session counts more than a 10-minute one.
    private static func averageHRSamples(_ intensities: [WorkoutIntensity]) -> [DatedSample] {
        let calendar = Calendar.current
        var days: [Date: (weighted: Double, seconds: TimeInterval)] = [:]
        for workout in intensities {
            guard let bpm = workout.avgBPM, workout.duration > 0 else { continue }
            let day = calendar.startOfDay(for: workout.start)
            days[day, default: (0, 0)].weighted += bpm * workout.duration
            days[day, default: (0, 0)].seconds += workout.duration
        }
        return days.map { DatedSample(date: $0.key, value: $0.value.weighted / $0.value.seconds) }
    }

    /// Shows the last workouts loaded until HealthKit answers.
    func primeIntensities() {
        guard let data = try? Data(contentsOf: Self.intensityCacheURL),
              let cached = try? JSONDecoder().decode([WorkoutIntensity].self, from: data) else { return }
        intensities = cached
    }

    private static func cacheIntensities(_ intensities: [WorkoutIntensity]) {
        guard let data = try? JSONEncoder().encode(intensities) else { return }
        try? data.write(to: intensityCacheURL, options: .atomic)
    }

    private static let intensityCacheURL = URL.cachesDirectory.appending(path: "intensities.json")

    private func saveSnapshot(context: ModelContext) {
        let snapshot = MetricSnapshot(latestHRV: latestHRV,
                                      restingHR: restingHR,
                                      todayActiveEnergy: todayActiveEnergy)
        // Keep only the newest snapshot.
        if let existing = try? context.fetch(FetchDescriptor<MetricSnapshot>()) {
            existing.forEach(context.delete)
        }
        context.insert(snapshot)
    }
}
