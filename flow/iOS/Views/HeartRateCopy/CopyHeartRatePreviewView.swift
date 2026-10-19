//
//  CopyHeartRatePreviewView.swift
//  flow
//
//  One source workout's heart rate stretched onto the target, drawn over
//  whatever the target did record, before it's written to Health. Ends on a
//  confirmation with Undo.
//

import SwiftUI
import Charts
import SessionEngine

struct CopyHeartRatePreviewView: View {
    let viewModel: CopyHeartRateViewModel
    let candidate: CopyHeartRateViewModel.Candidate
    let onDone: () -> Void

    @State private var mode: CopyHeartRateViewModel.Mode = .fillGaps
    @State private var preview: CopyHeartRateViewModel.Preview?
    @State private var applied: HeartRateCopyService.Applied?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var confirmingReplace = false

    private var ownCount: Int { viewModel.targetHR?.own.count ?? 0 }
    private var realCount: Int { viewModel.targetHR?.real.count ?? 0 }

    var body: some View {
        Group {
            if let applied {
                done(applied)
            } else {
                previewList
            }
        }
        .navigationTitle(applied == nil ? "Preview" : "Copied")
        .navigationBarBackButtonHidden(applied != nil)
        .task(id: mode) {
            do {
                preview = try await viewModel.preview(candidate, mode: mode)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Preview

    private var previewList: some View {
        List {
            Section {
                if let preview {
                    PreviewChart(preview: preview, duration: viewModel.target.duration)
                        .frame(height: 200)
                    PreviewLegend(hasRecorded: !preview.recorded.isEmpty)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 200)
                }
            }

            Section {
                LabeledContent("From", value: "\(candidate.title), \(candidate.source.start.formatted(date: .abbreviated, time: .omitted))")
                LabeledContent("Length", value: lengthText)
                if let preview {
                    LabeledContent("Readings to add", value: preview.copied.count.formatted())
                    if let average = Self.average(preview.copied + preview.recorded) {
                        LabeledContent("Average", value: "\(average) bpm")
                    }
                }
            }

            if realCount > 0 {
                Section {
                    Picker("Recorded readings", selection: $mode) {
                        Text("Keep, fill gaps").tag(CopyHeartRateViewModel.Mode.fillGaps)
                        if ownCount > 0 {
                            Text("Replace").tag(CopyHeartRateViewModel.Mode.replace)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("This workout recorded \(realCount) readings")
                } footer: {
                    Text(modeFooter)
                }
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                if (preview?.replacedCount ?? 0) > 0 {
                    confirmingReplace = true
                } else {
                    Task { await copy() }
                }
            } label: {
                Group {
                    if isWorking {
                        ProgressView()
                    } else {
                        Text("Copy Heart Rate")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled((preview?.copied.isEmpty ?? true) || isWorking)
            .padding()
            .background(.bar)
        }
        .confirmationDialog("Replace \(preview?.replacedCount ?? 0) recorded readings?",
                            isPresented: $confirmingReplace, titleVisibility: .visible) {
            Button("Replace and Copy", role: .destructive) { Task { await copy() } }
        } message: {
            Text("They're backed up on this phone and come back if you undo or remove the copy.")
        }
    }

    private var lengthText: String {
        let from = Int(candidate.source.duration / 60)
        let to = Int(viewModel.target.duration / 60)
        let percent = Int(((viewModel.target.duration / candidate.source.duration - 1) * 100).rounded())
        if percent == 0 { return "\(from) min, same length" }
        return "\(from) → \(to) min (\(percent > 0 ? "stretched" : "squeezed") \(abs(percent))%)"
    }

    private var modeFooter: String {
        let foreignNote = (viewModel.targetHR?.foreign.isEmpty ?? true)
            ? "" : " Readings from other apps, like a Watch, are always kept."
        switch mode {
        case .fillGaps:
            return "Real readings stay; copied ones only go where the strap dropped out." + foreignNote
        case .replace:
            return "flow's own readings are swapped for the copy. Undo brings them back." + foreignNote
        }
    }

    private func copy() async {
        guard let preview else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            applied = try await viewModel.copy(preview, from: candidate)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Done

    private func done(_ applied: HeartRateCopyService.Applied) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("Heart rate copied")
                .font(.title2.bold())
            VStack(spacing: 8) {
                Text("Added \(applied.written.formatted()) estimated readings to \(viewModel.target.title) from \(candidate.title) on \(candidate.source.start.formatted(date: .abbreviated, time: .omitted)).")
                if applied.replaced > 0 {
                    Text("Replaced \(applied.replaced.formatted()) recorded readings; they're backed up on this phone.")
                }
                Text("Marked as estimated in Health. To take it out later, use Remove Copied Heart Rate on the workout.")
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
            Button(action: onDone) {
                Text("Done").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isWorking)

            Button {
                Task { await undo(applied) }
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

    private func undo(_ applied: HeartRateCopyService.Applied) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await viewModel.undo(applied)
            self.applied = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func average(_ points: [HRPoint]) -> Int? {
        guard !points.isEmpty else { return nil }
        return Int((Double(points.map(\.bpm).reduce(0, +)) / Double(points.count)).rounded())
    }
}

/// Copied readings as a line, recorded ones as dots, over the target's length.
struct PreviewChart: View {
    let preview: CopyHeartRateViewModel.Preview
    let duration: TimeInterval

    /// Keeps a long workout cheap to draw.
    private static let maxDrawnPoints = 600

    private var copied: [HRPoint] { Self.thinned(preview.copied) }
    private var recorded: [HRPoint] { Self.thinned(preview.recorded) }

    var body: some View {
        Chart {
            ForEach(Array(copied.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("Minute", point.t / 60), y: .value("bpm", point.bpm),
                         series: .value("Series", "Copied"))
                    .foregroundStyle(Color.accentColor)
                    .interpolationMethod(.monotone)
            }
            ForEach(Array(recorded.enumerated()), id: \.offset) { _, point in
                PointMark(x: .value("Minute", point.t / 60), y: .value("bpm", point.bpm))
                    .foregroundStyle(.secondary)
                    .symbolSize(12)
            }
        }
        .chartXScale(domain: 0...max(duration / 60, 1))
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxisLabel("min")
        .accessibilityLabel("Preview: \(preview.copied.count) copied readings and \(preview.recorded.count) recorded readings")
    }

    private static func thinned(_ points: [HRPoint]) -> [HRPoint] {
        guard points.count > maxDrawnPoints else { return points }
        let step = Int((Double(points.count) / Double(maxDrawnPoints)).rounded(.up))
        return stride(from: 0, to: points.count, by: step).map { points[$0] }
    }
}

private struct PreviewLegend: View {
    let hasRecorded: Bool

    var body: some View {
        HStack(spacing: 16) {
            Label("Copied (estimated)", systemImage: "line.diagonal")
                .foregroundStyle(Color.accentColor)
            if hasRecorded {
                Label("Recorded", systemImage: "circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }
}
