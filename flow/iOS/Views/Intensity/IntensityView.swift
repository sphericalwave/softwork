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

    @Query(filter: #Predicate<TrainingSessionRecord> { $0.endedAt != nil })
    private var endedSessions: [TrainingSessionRecord]
    @Environment(\.modelContext) private var modelContext
    @State private var tags = WorkoutTags()
    /// The workout whose heart rate is being filled in from another.
    @State private var copyTarget: WorkoutIntensity?
    /// The workout being duplicated onto a day it wasn't recorded.
    @State private var duplicateSource: WorkoutIntensity?
    /// A duplicate waiting for delete confirmation.
    @State private var duplicateToDelete: WorkoutIntensity?
    @State private var deleteError: String?
    @Environment(\.modelContext) private var modelContext

    /// flow's own training sessions, keyed by the Health workout they saved as.
    private var sessionsByWorkoutID: [UUID: TrainingSessionRecord] {
        Dictionary(endedSessions.compactMap { session in
            session.healthKitWorkoutID.map { ($0, session) }
        }, uniquingKeysWith: { first, _ in first })
    }

    /// The flow session a workout row belongs to. A session whose workout
    /// isn't in the loaded list — being re-saved after a type change, or
    /// re-saved since the last refresh — matches by start time, so its row
    /// (and an open detail) stays put.
    private func session(for workout: WorkoutIntensity) -> TrainingSessionRecord? {
        if let session = sessionsByWorkoutID[workout.id] { return session }
        let listed = Set(viewModel.intensities.map(\.id))
        return endedSessions.first { session in
            !(session.healthKitWorkoutID.map(listed.contains) ?? false)
                && abs(session.startedAt.timeIntervalSince(workout.start)) < 1
        }
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
                            if let session = session(for: workout) {
                                NavigationLink {
                                    TrainingSessionDetailView(record: session)
                                        .toolbar {
                                            ToolbarItem(placement: .topBarTrailing) { exportButton(workout, name: session.kindLabel) }
                                            ToolbarItem(placement: .topBarTrailing) { copyButton(workout) }
                                            ToolbarItem(placement: .topBarTrailing) { duplicateButton(workout) }
                                        }
                                } label: {
                                    WorkoutIntensityRow(intensity: workout, title: session.kindLabel,
                                                        accessory: "chevron.right")
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    exportButton(workout, name: session.kindLabel)
                                    copyButton(workout)
                                    duplicateButtons(workout)
                                }
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
            .sheet(item: $copyTarget) { workout in
                CopyHeartRateView(viewModel: viewModel.copyHeartRate(for: workout,
                                                                     title: title(for: workout.id, type: workout.activityType),
                                                                     session: session(for: workout).map {
                                                                         CopyHeartRateViewModel.LinkedSession(record: $0, context: modelContext)
                                                                     },
                                                                     titleFor: title(for:type:)),
                                  onClose: { changed in
                                      if changed { Task { await refresh() } }
                                  })
            }
            .sheet(item: $duplicateSource) { workout in
                DuplicateWorkoutView(viewModel: viewModel.duplicate(workout, session: session(for: workout),
                                                                    tag: tags.tag(for: workout.id),
                                                                    title: title(for: workout.id, type: workout.activityType),
                                                                    titleFor: title(for:type:)),
                                     onClose: { changed in
                                         if changed { Task { await refresh() } }
                                     })
            }
            .confirmationDialog("Delete duplicated workout?",
                                isPresented: Binding(get: { duplicateToDelete != nil },
                                                     set: { if !$0 { duplicateToDelete = nil } }),
                                titleVisibility: .visible, presenting: duplicateToDelete) { workout in
                Button("Delete Workout", role: .destructive) { Task { await deleteDuplicate(workout) } }
            } message: { workout in
                Text("Removes the \(workout.start.formatted(date: .abbreviated, time: .shortened)) workout from Health, with its copied heart rate and energy, and its flow session.")
            }
            .alert("Couldn't delete the workout", isPresented: Binding(get: { deleteError != nil },
                                                                      set: { if !$0 { deleteError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteError ?? "")
            }
        }
    }

    /// The name a workout's card shows: flow's session kind, the user's tag, or Health's activity type.
    private func title(for workoutID: UUID, type: HKWorkoutActivityType) -> String {
        sessionsByWorkoutID[workoutID]?.kindLabel ?? tags.tag(for: workoutID)?.label ?? type.name
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
            exportButton(workout, name: tag?.label ?? workout.activityType.name)
            copyButton(workout)
            duplicateButtons(workout)
        } label: {
            WorkoutIntensityRow(intensity: workout, title: tag?.label ?? workout.activityType.name,
                                accessory: tag == nil ? "tag" : "tag.fill")
        }
        .buttonStyle(.plain)
    }

    /// Shares the workout's heart rate as CSV for youtube-uploader's hr-overlay.swift.
    @ViewBuilder
    private func exportButton(_ workout: WorkoutIntensity, name: String) -> some View {
        if let csv = viewModel.heartRateCSV(for: workout, name: name) {
            ShareLink(item: csv, preview: SharePreview(csv.filename)) {
                Label("Export Heart Rate", systemImage: "square.and.arrow.up")
            }
        }
    }

    /// For a workout whose strap failed: borrow a similar workout's heart rate.
    private func copyButton(_ workout: WorkoutIntensity) -> some View {
        Button {
            copyTarget = workout
        } label: {
            Label(workout.hasEstimatedHR == true ? "Copied Heart Rate…" : "Copy Heart Rate From…",
                  systemImage: "waveform.path.ecg")
        }
    }

    /// For a session trained but never recorded: copy this workout onto that day.
    private func duplicateButton(_ workout: WorkoutIntensity) -> some View {
        Button {
            duplicateSource = workout
        } label: {
            Label("Duplicate To…", systemImage: "plus.square.on.square")
        }
    }

    /// Duplicate To…, plus Delete for a workout that is itself a duplicate.
    @ViewBuilder
    private func duplicateButtons(_ workout: WorkoutIntensity) -> some View {
        duplicateButton(workout)
        if workout.duplicatedFrom != nil {
            Button(role: .destructive) {
                duplicateToDelete = workout
            } label: {
                Label("Delete Duplicated Workout", systemImage: "trash")
            }
        }
    }

    private func deleteDuplicate(_ workout: WorkoutIntensity) async {
        do {
            try await viewModel.deleteDuplicate(workout, context: modelContext)
        } catch {
            deleteError = error.localizedDescription
        }
        await refresh()
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
                if intensity.hasEstimatedHR == true || intensity.duplicatedFrom != nil {
                    Label("Estimated", systemImage: "waveform.path.ecg")
                        .accessibilityLabel("Heart rate partly estimated")
                }
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
