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

        /// Trend bucket: hours for a day, days otherwise.
        var bucket: Calendar.Component { self == .day ? .hour : .day }

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

    // Trends (day → value)
    @Published var hrvTrend: [Date: Double] = [:]
    @Published var activeEnergyTrend: [Date: Double] = [:]

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
            async let hrvSeries = health.averageHRV(in: window)
            async let energySeries = health.sumActiveEnergy(in: window)

            latestHRV = try await hrv
            restingHR = try await resting
            todayActiveEnergy = try await energy
            hrvTrend = try await hrvSeries
            activeEnergyTrend = try await energySeries

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
