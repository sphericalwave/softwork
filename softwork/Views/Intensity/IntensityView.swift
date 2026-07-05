//
//  IntensityView.swift
//  softwork
//
//  Workout heart rate as a percentage of HR max: an aggregate zone bar plus
//  a per-workout breakdown.
//

import SwiftUI
import HealthKit

struct IntensityView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Binding var window: DashboardViewModel.TimeWindow
    let refresh: () async -> Void

    private var aggregate: [HRZone: TimeInterval] {
        var totals: [HRZone: TimeInterval] = [:]
        for intensity in viewModel.intensities {
            for (zone, seconds) in intensity.zoneSeconds {
                totals[zone, default: 0] += seconds
            }
        }
        return totals
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    WindowPicker(window: $window, refresh: refresh)

                    if viewModel.intensities.isEmpty {
                        ContentUnavailableView("No workouts",
                                               systemImage: "figure.run",
                                               description: Text("Workouts with heart-rate data in this window will appear here."))
                            .padding(.top, 40)
                    } else {
                        aggregateCard
                        ForEach(viewModel.intensities) { workout in
                            WorkoutIntensityRow(intensity: workout)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Intensity")
            .refreshable { await refresh() }
        }
    }

    private var aggregateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Time in zone")
                .font(.headline)
            ZoneBar(zoneSeconds: aggregate)
            ZoneLegend(zoneSeconds: aggregate)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct WorkoutIntensityRow: View {
    let intensity: WorkoutIntensity

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(intensity.activityType.name)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(intensity.start, format: .dateTime.month().day())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ZoneBar(zoneSeconds: intensity.zoneSeconds)
            HStack {
                Text("\(Int(intensity.duration / 60)) min")
                Spacer()
                if let pct = intensity.avgPercentOfMax {
                    Text("avg \(Int(pct.rounded()))% HRmax")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

extension HKWorkoutActivityType {
    /// A short, human-readable name for the common activity types.
    var name: String {
        switch self {
        case .running: return "Running"
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .hiking: return "Hiking"
        case .swimming: return "Swimming"
        case .rowing: return "Rowing"
        case .elliptical: return "Elliptical"
        case .functionalStrengthTraining: return "Strength"
        case .traditionalStrengthTraining: return "Weights"
        case .highIntensityIntervalTraining: return "HIIT"
        case .yoga: return "Yoga"
        case .coreTraining: return "Core"
        case .stairClimbing: return "Stairs"
        case .mixedCardio: return "Cardio"
        default: return "Workout"
        }
    }
}
