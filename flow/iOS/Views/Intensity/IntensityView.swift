//
//  IntensityView.swift
//  flow
//
//  Workout heart rate as a percentage of HR max: an aggregate zone bar plus
//  a per-workout breakdown.
//

import SwiftUI
import SwiftData
import SwDesignSystem
import Persistence
import AthleteFeatures
import HealthKit
import SessionEngine
import ZoneUI

struct IntensityView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Binding var window: DashboardViewModel.TimeWindow
    let refresh: () async -> Void

    @Query(filter: #Predicate<TrainingSessionRecord> { $0.healthKitWorkoutID != nil })
    private var savedSessions: [TrainingSessionRecord]

    /// flow's own training sessions, keyed by the Health workout they saved as.
    private var sessionsByWorkoutID: [UUID: TrainingSessionRecord] {
        Dictionary(savedSessions.compactMap { session in
            session.healthKitWorkoutID.map { ($0, session) }
        }, uniquingKeysWith: { first, _ in first })
    }

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
                            if let session = sessionsByWorkoutID[workout.id] {
                                NavigationLink {
                                    TrainingSessionDetailView(record: session)
                                } label: {
                                    WorkoutIntensityRow(intensity: workout, title: session.kindLabel,
                                                        showsDisclosure: true)
                                }
                                .buttonStyle(.plain)
                            } else {
                                WorkoutIntensityRow(intensity: workout, title: workout.activityType.name)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Intensity")
            .toolbarBackground(SwTheme.primaryColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
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
    let title: String
    var showsDisclosure = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(intensity.start, format: .dateTime.month().day())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if showsDisclosure {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
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
        .contentShape(RoundedRectangle(cornerRadius: 16))
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
        case .wrestling: return "Wrestling"
        case .kickboxing: return "Kickboxing"
        case .martialArts: return "Martial Arts"
        case .boxing: return "Boxing"
        default: return "Workout"
        }
    }
}
