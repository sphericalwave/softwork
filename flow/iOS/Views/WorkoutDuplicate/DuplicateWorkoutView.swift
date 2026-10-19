//
//  DuplicateWorkoutView.swift
//  flow
//
//  Sheet for recreating a session that was trained but never recorded from
//  a similar past workout: choose the day, start time and length, check the
//  copied heart rate, then create. Ends on a confirmation with Undo.
//

import SwiftUI
import AthleteFeatures

struct DuplicateWorkoutView: View {
    @State var viewModel: DuplicateWorkoutViewModel
    /// Called on close with whether Health changed, so the caller can reload.
    let onClose: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var created: WorkoutDuplicateService.Created?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var confirmingOverlap = false

    var body: some View {
        NavigationStack {
            Group {
                if let created {
                    done(created)
                } else {
                    form
                }
            }
            .navigationTitle(created == nil ? "Duplicate Workout" : "Created")
            .navigationBarTitleDisplayMode(.inline)
            .brandedToolbars()
            .toolbar {
                if created == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
        .interactiveDismissDisabled(isWorking)
        .task { await viewModel.load() }
        .task(id: "\(viewModel.start.timeIntervalSinceReferenceDate)-\(viewModel.minutes)") {
            await viewModel.checkOverlaps()
        }
        .onDisappear { onClose(viewModel.didChange) }
    }

    // MARK: - Form

    private var form: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.source.title)
                        .font(.headline)
                    Text("\(viewModel.source.start.formatted(date: .abbreviated, time: .shortened)) · \(Int((viewModel.source.duration / 60).rounded())) min")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            } header: {
                Text("Copy of")
            } footer: {
                Text("For a session you trained but didn't record. The new workout gets this one's type, notes and heart rate, saved to Health marked as estimated.")
            }

            Section("New workout") {
                DatePicker("Starts", selection: $viewModel.start, in: ...viewModel.latestStart,
                           displayedComponents: [.date, .hourAndMinute])
                Stepper(value: $viewModel.minutes, in: DuplicateWorkoutViewModel.minuteRange,
                        step: DuplicateWorkoutViewModel.minuteStep) {
                    LabeledContent("Length", value: "\(viewModel.minutes) min")
                }
                LabeledContent("Ends", value: viewModel.end.formatted(date: .omitted, time: .shortened))
            }

            if !viewModel.overlaps.isEmpty {
                Section {
                    ForEach(viewModel.overlaps, id: \.source.id) { overlap in
                        Label("Overlaps \(overlap.title), \(overlap.source.start.formatted(date: .omitted, time: .shortened))–\(overlap.source.start.addingTimeInterval(overlap.source.duration).formatted(date: .omitted, time: .shortened))",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                } footer: {
                    Text("Health already has a workout at this time. Check the day and start time, or create anyway.")
                }
            }

            previewSection

            if let error = errorMessage ?? viewModel.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    if viewModel.preview == nil {
                        Button("Try Again") { Task { await viewModel.load() } }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                if viewModel.overlaps.isEmpty {
                    Task { await create() }
                } else {
                    confirmingOverlap = true
                }
            } label: {
                Group {
                    if isWorking { ProgressView() } else { Text("Create Workout") }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!viewModel.canCreate || isWorking)
            .padding()
            .background(.bar)
        }
        .confirmationDialog("Overlaps a workout already in Health", isPresented: $confirmingOverlap,
                            titleVisibility: .visible) {
            Button("Create Anyway") { Task { await create() } }
        } message: {
            Text("Both will count toward your totals. You can delete the duplicate later from its card.")
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        Section("Preview") {
            if let preview = viewModel.preview {
                if preview.points.isEmpty {
                    Label("The original has no heart rate, so only the workout and energy are copied.",
                          systemImage: "heart.slash")
                        .foregroundStyle(.secondary)
                } else {
                    PreviewChart(preview: .init(copied: preview.points, recorded: [],
                                                stretch: viewModel.duration / viewModel.source.duration,
                                                replacedCount: 0),
                                 duration: viewModel.duration)
                        .frame(height: 180)
                    LabeledContent("Readings", value: preview.points.count.formatted())
                }
                if let summary = preview.summary {
                    LabeledContent("Average", value: "\(summary.average) bpm")
                    LabeledContent("Max", value: "\(summary.max) bpm")
                }
                if let kcal = preview.kcal {
                    LabeledContent("Active energy", value: "\(Int(kcal.rounded())) kcal")
                }
            } else if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
    }

    private func create() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            created = try await viewModel.create(context: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Done

    private func done(_ created: WorkoutDuplicateService.Created) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("Workout created")
                .font(.title2.bold())
            VStack(spacing: 8) {
                Text("\(viewModel.source.title) on \(viewModel.start.formatted(date: .complete, time: .shortened)), \(viewModel.minutes) min, copied from \(viewModel.source.start.formatted(date: .abbreviated, time: .omitted)).")
                if created.readings > 0 {
                    Text("\(created.readings.formatted()) heart-rate readings marked as estimated.")
                }
                Text("It shows in Intensity labelled Estimated. To remove it later, long-press its card › Delete Workout.")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.footnote)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("Done").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isWorking)

            Button {
                Task { await undo(created) }
            } label: {
                Group {
                    if isWorking { ProgressView() } else { Text("Undo") }
                }
                .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .disabled(isWorking)
        }
        .padding()
    }

    private func undo(_ created: WorkoutDuplicateService.Created) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await viewModel.undo(created, context: modelContext)
            self.created = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
