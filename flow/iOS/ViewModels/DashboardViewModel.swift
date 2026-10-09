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
    // D/W/M picker. Independent of the Intensity window.
    @Published var hrvSamples: [DatedSample] = []
    @Published var activeEnergySamples: [DatedSample] = []

    /// Covers the 12-month window (current month + 11 before).
    private static let trendDays = 366

    // Intensity
    @Published var intensities: [WorkoutIntensity] = []

    @Published var isLoading = false
    @Published var errorMessage: String?

    private let health: HealthKitService
    private let intensityService: WorkoutIntensityService

    init(health: HealthKitService) {
        self.health = health
        self.intensityService = WorkoutIntensityService(store: health.store)
    }

    /// Seed tiles from the cached snapshot so the UI isn't empty on launch.
    func primeFromCache(_ snapshot: MetricSnapshot?) {
        guard let snapshot else { return }
        latestHRV = latestHRV ?? snapshot.latestHRV
        restingHR = restingHR ?? snapshot.restingHR
        todayActiveEnergy = todayActiveEnergy ?? snapshot.todayActiveEnergy
    }

    func refresh(window: TimeWindow, hrMaxOverride: Int, formula: MaxHRFormula, context: ModelContext) async {
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
            intensities = try await intensityService.recentIntensities(in: window, hrMax: hrMax)
            Self.cacheIntensities(intensities, for: window)
        } catch {
            ErrorLog.shared.error("Dashboard", "Workout intensity load failed", error: error)
            errorMessage = error.localizedDescription
        }
    }

    private static func samples(_ daily: [Date: Double]) -> [DatedSample] {
        daily.map { DatedSample(date: $0.key, value: $0.value) }
    }

    /// Shows the last workouts computed for `window` until HealthKit answers.
    func primeIntensities(for window: TimeWindow) {
        guard let data = try? Data(contentsOf: Self.intensityCacheURL(window)),
              let cached = try? JSONDecoder().decode([WorkoutIntensity].self, from: data) else {
            intensities = []
            return
        }
        intensities = cached
    }

    private static func cacheIntensities(_ intensities: [WorkoutIntensity], for window: TimeWindow) {
        guard let data = try? JSONEncoder().encode(intensities) else { return }
        try? data.write(to: intensityCacheURL(window), options: .atomic)
    }

    private static func intensityCacheURL(_ window: TimeWindow) -> URL {
        URL.cachesDirectory.appending(path: "intensities-\(window.rawValue).json")
    }

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
