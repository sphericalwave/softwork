//
//  DashboardViewModel.swift
//  softwork
//
//  Orchestrates HealthKit loads for the Overview and Intensity screens and
//  writes the last-known values into the MetricSnapshot cache.
//

import Foundation
import SwiftData
import HealthKit
import Combine

@MainActor
final class DashboardViewModel: ObservableObject {

    enum TimeWindow: Int, CaseIterable, Identifiable {
        case week = 7, month = 30, quarter = 90
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .week: return "7D"
            case .month: return "30D"
            case .quarter: return "90D"
            }
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

    func refresh(window: TimeWindow, hrMaxOverride: Int, context: ModelContext) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let hrv = health.latestHRV()
            async let resting = health.latestRestingHR()
            async let energy = health.todayActiveEnergy()
            async let hrvSeries = health.dailyAverageHRV(days: window.rawValue)
            async let energySeries = health.dailySumActiveEnergy(days: window.rawValue)

            latestHRV = try await hrv
            restingHR = try await resting
            todayActiveEnergy = try await energy
            hrvTrend = try await hrvSeries
            activeEnergyTrend = try await energySeries

            let hrMax = HealthKitService.effectiveHRMax(override: hrMaxOverride, age: health.ageInYears())
            intensities = try await intensityService.recentIntensities(days: window.rawValue, hrMax: hrMax)

            saveSnapshot(context: context)
        } catch {
            errorMessage = error.localizedDescription
        }
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
