//
//  IntensityView.swift
//  flow
//
//  Workout heart rate as a percentage of HR max: an aggregate zone bar plus
//  a per-workout breakdown.
//

import SwiftUI
import SwiftData
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
    @State private var tags = WorkoutTags()

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
                    if viewModel.intensities.isEmpty {
                        if viewModel.isLoading {
                            ProgressView("Loading workouts from Health…")
                                .padding(.top, 80)
                        } else {
                            ContentUnavailableView("No workouts",
                                                   systemImage: "figure.run",
                                                   description: Text("Workouts with heart-rate data in this window will appear here."))
                                .padding(.top, 40)
                        }
                    } else {
                        aggregateCard
                        ForEach(viewModel.intensities) { workout in
                            if let session = sessionsByWorkoutID[workout.id] {
                                NavigationLink {
                                    TrainingSessionDetailView(record: session)
                                } label: {
                                    WorkoutIntensityRow(intensity: workout, title: session.kindLabel,
                                                        accessory: "chevron.right")
                                }
                                .buttonStyle(.plain)
                                .contextMenu { exportButton(workout) }
                            } else {
                                taggableRow(workout)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Intensity")
            .brandedToolbars()
            .toolbar {
                ToolbarItem(placement: .principal) {
                    WindowPicker(window: $window)
                }
            }
            .refreshable { await refresh() }
        }
    }

    /// A workout flow didn't record: tap to tag what it really was.
    private func taggableRow(_ workout: WorkoutIntensity) -> some View {
        let tag = tags.tag(for: workout.id)
        return Menu {
            Picker("Tag as", selection: Binding(
                get: { tag },
                set: { tags.setTag($0, for: workout.id) }
            )) {
                ForEach(WorkoutTag.allCases) { Text($0.label).tag(Optional($0)) }
            }
            if tag != nil {
                Button("Remove Tag", role: .destructive) { tags.setTag(nil, for: workout.id) }
            }
            exportButton(workout)
        } label: {
            WorkoutIntensityRow(intensity: workout, title: tag?.label ?? workout.activityType.name,
                                accessory: tag == nil ? "tag" : "tag.fill")
        }
        .buttonStyle(.plain)
    }

    /// Shares the workout's heart rate as CSV for youtube-uploader's hr-overlay.swift.
    @ViewBuilder
    private func exportButton(_ workout: WorkoutIntensity) -> some View {
        if let csv = viewModel.heartRateCSV(for: workout) {
            ShareLink(item: csv, preview: SharePreview(csv.filename)) {
                Label("Export Heart Rate", systemImage: "square.and.arrow.up")
            }
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
    /// SF Symbol hinting what a tap does: open (chevron) or tag.
    var accessory: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(intensity.start, format: .dateTime.month().day())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let accessory {
                    Image(systemName: accessory)
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

/// Day/Week/Month trailing-window selector for Intensity's principal slot.
/// RootView reloads when it changes.
struct WindowPicker: View {
    @Binding var window: DashboardViewModel.TimeWindow

    var body: some View {
        Picker("Timeframe", selection: $window) {
            ForEach(DashboardViewModel.TimeWindow.allCases) { w in
                Text(w.label).tag(w)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 180)
    }
}
