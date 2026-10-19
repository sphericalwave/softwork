//
//  CopyHeartRateView.swift
//  flow
//
//  Sheet for filling in a workout whose strap failed with a similar past
//  workout's heart rate. Similar workouts are suggested first; everything
//  from the last year is searchable below. Picking one opens a preview, and
//  nothing is written to Health until it's confirmed there.
//

import SwiftUI
import AthleteFeatures

struct CopyHeartRateView: View {
    @State var viewModel: CopyHeartRateViewModel
    /// Called on close with whether Health changed, so the caller can reload.
    let onClose: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Copy Heart Rate")
                .navigationBarTitleDisplayMode(.inline)
                .brandedToolbars()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
        .task { await viewModel.load() }
        .onDisappear { onClose(viewModel.didChange) }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.candidates.isEmpty && viewModel.targetHR == nil {
            ProgressView("Finding similar workouts…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                Section {
                    TargetSummary(target: viewModel.target, heartRate: viewModel.targetHR)
                } header: {
                    Text("Fill in")
                } footer: {
                    Text("Pick a similar session. Its heart rate is stretched to fit this workout and saved to Health marked as estimated.")
                }

                if let error = viewModel.errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Button("Try Again") { Task { await viewModel.load() } }
                    }
                }

                if (viewModel.targetHR?.estimatedCount ?? 0) > 0 {
                    earlierCopySection
                } else {
                    sourceSections
                }
            }
            .searchable(text: $viewModel.searchText, prompt: "Workout, day or month")
        }
    }

    /// A workout takes one copy at a time; a new one replaces the old.
    private var earlierCopySection: some View {
        Section {
            Label("This workout already has copied heart rate.", systemImage: "waveform.path.ecg")
            Button("Remove Copied Heart Rate", role: .destructive) {
                Task { await viewModel.removeEarlierCopies() }
            }
            .disabled(viewModel.isLoading)
        } footer: {
            Text("Remove it to copy from a different workout. Any readings it replaced come back.")
        }
    }

    @ViewBuilder
    private var sourceSections: some View {
        let suggested = viewModel.suggested
        let others = viewModel.others
        if !suggested.isEmpty {
            Section("Suggested") {
                ForEach(suggested) { row($0) }
            }
        }
        Section(viewModel.searchText.isEmpty ? (suggested.isEmpty ? "Workouts" : "All Workouts") : "Results") {
            if others.isEmpty {
                if !viewModel.searchText.isEmpty {
                    ContentUnavailableView.search(text: viewModel.searchText)
                } else if suggested.isEmpty && !viewModel.isLoading {
                    Text("No other workouts in the last year.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(others) { row($0) }
            }
        }
    }

    private func row(_ candidate: CopyHeartRateViewModel.Candidate) -> some View {
        let hasHR = viewModel.hasHeartRate(candidate)
        return NavigationLink {
            CopyHeartRatePreviewView(viewModel: viewModel, candidate: candidate, onDone: { dismiss() })
        } label: {
            CandidateRow(candidate: candidate, target: viewModel.target,
                         average: viewModel.averages[candidate.id] ?? nil, hasHeartRate: hasHR)
        }
        .disabled(hasHR == false)
        .task { await viewModel.loadAverage(candidate) }
    }
}

private struct TargetSummary: View {
    let target: CopyHeartRateViewModel.Target
    let heartRate: TargetHeartRate?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(target.title)
                .font(.headline)
            Text("\(target.start.formatted(date: .abbreviated, time: .shortened)) · \(Int(target.duration / 60)) min")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let heartRate {
                let count = heartRate.real.count
                Label(count == 0 ? "No heart rate recorded" : "Only \(count) readings recorded",
                      systemImage: "heart.slash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct CandidateRow: View {
    let candidate: CopyHeartRateViewModel.Candidate
    let target: CopyHeartRateViewModel.Target
    let average: Int?
    /// nil while loading.
    let hasHeartRate: Bool?

    private var lengthDifference: String {
        let minutes = Int(((candidate.source.duration - target.duration) / 60).rounded())
        if minutes == 0 { return "same length" }
        return minutes > 0 ? "+\(minutes) min" : "\(minutes) min"
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.title)
                    .font(.headline)
                Text(candidate.source.start.formatted(.dateTime.weekday(.abbreviated).month().day().year()))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(Int(candidate.source.duration / 60)) min")
                    .monospacedDigit()
                Group {
                    switch hasHeartRate {
                    case .some(false): Text("No heart rate")
                    case .some(true): Text("avg \(average ?? 0) bpm · \(lengthDifference)")
                    case .none: Text(lengthDifference)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
