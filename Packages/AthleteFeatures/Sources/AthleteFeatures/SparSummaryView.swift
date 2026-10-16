//
//  SparSummaryView.swift
//  AthleteFeatures
//
//  End of session: the numbers first, then the whole-session trace with
//  sparring rounds shaded, then where the session was saved. The workout
//  type and notes stay editable afterwards. Calories are
//  an estimate from heart rate (CalorieEstimator); everything else is
//  measured.
//

#if os(iOS)
import SwiftUI
import Persistence
import SessionEngine

struct SparSummaryView: View {
    let summary: TrainingSummary
    let model: SoloSparringModel

    var body: some View {
        NavigationStack {
            SessionSummaryContent(summary: summary, record: model.record,
                                  status: model.saveStatus, bufferBytes: model.bufferBytes,
                                  retry: { model.retrySave() })
            .safeAreaInset(edge: .bottom) {
                Button {
                    model.dismissSummary()
                } label: {
                    Text("Done")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .padding()
                .background(.bar)
            }
            .navigationTitle("Training Complete")
            .brandedToolbars()
        }
    }
}

/// The end-of-session screen's content, shared with a past session's
/// detail (history and Intensity cards).
struct SessionSummaryContent: View {
    let summary: TrainingSummary
    /// The stored session, for editing its type and notes.
    let record: TrainingSessionRecord?
    let status: HealthSyncStatus
    let bufferBytes: Int
    let retry: @MainActor () -> Void

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    private var kindLabel: String { record?.kindLabel ?? summary.kind.label }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("\(kindLabel) · \(summary.startedAt.formatted(date: .complete, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: columns, spacing: 12) {
                    StatTile(value: HeartRateChart.clock(summary.duration), unit: nil,
                             label: "Duration", systemImage: "stopwatch")
                    StatTile(value: summary.activeCalories.map { "\(Int($0.rounded()))" } ?? "--", unit: "kcal",
                             label: "Active calories", systemImage: "flame.fill")
                    StatTile(value: summary.averageBPM.map(String.init) ?? "--", unit: "bpm",
                             label: "HR avg", systemImage: "heart.fill")
                    StatTile(value: summary.maxBPM.map(String.init) ?? "--", unit: "bpm",
                             label: "HR max", systemImage: "heart.fill")
                    StatTile(value: "\(summary.timeoutCount)", unit: nil,
                             label: summary.timeoutCount == 1 ? "Timeout" : "Timeouts",
                             systemImage: "hand.raised.fill")
                    StatTile(value: HeartRateChart.clock(summary.secondsOverCeiling), unit: nil,
                             label: "Over ceiling", systemImage: "exclamationmark.triangle.fill")
                }

                if summary.activeCalories == nil {
                    Text("Add your sex and weight in Settings, and your birth date in Health, to estimate calories.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let record, record.endedAt != nil {
                    WorkoutKindPicker(record: record)
                    SessionNotesEditor(record: record)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Heart Rate")
                        .font(.headline)
                    if !summary.rounds.isEmpty {
                        Text(roundsLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if summary.points.isEmpty {
                        Text("No heart rate was recorded this session.")
                            .foregroundStyle(.secondary)
                    } else {
                        HeartRateChart(points: summary.points, hrMax: summary.hrMax,
                                       rounds: summary.rounds,
                                       timeDomain: 0...max(summary.duration, 60))
                            .frame(height: 280)
                    }
                }

                HealthSyncStatusView(status: status, kindLabel: kindLabel, retry: retry)

                StorageEstimate(summary: summary, bufferBytes: bufferBytes)
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var roundsLine: String {
        let count = summary.rounds.count
        return "\(count) sparring \(count == 1 ? "round" : "rounds") · \(HeartRateChart.clock(summary.sparringSeconds)) (shaded)"
    }
}

/// The session's workout type. Changing it for a session already in Health
/// saves it there again as the new type.
private struct WorkoutKindPicker: View {
    let record: TrainingSessionRecord
    @Environment(\.modelContext) private var modelContext
    private let sync = HealthSessionSync.shared

    private var selection: Binding<WorkoutKind?> {
        Binding(get: { WorkoutKind(rawValue: record.kindRaw) },
                set: { kind in
                    guard let kind else { return }
                    sync.changeKind(of: record, to: kind, context: modelContext)
                })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Type")
                    .font(.headline)
                Spacer()
                if sync.isBusy(record) {
                    ProgressView()
                }
                Picker("Type", selection: selection) {
                    ForEach(WorkoutKind.allCases) { kind in
                        Text(kind.label).tag(Optional(kind))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .disabled(sync.isBusy(record))
            }
            if let error = sync.kindChangeErrors[record.id] {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }
}

/// Free-text notes on the session. Typing edits a local draft; it's written
/// to the store when editing ends, the screen closes or the app leaves the
/// foreground — not on every keystroke.
private struct SessionNotesEditor: View {
    let record: TrainingSessionRecord
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var draft = ""
    @State private var loaded = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.headline)
            TextEditor(text: $draft)
                .focused($focused)
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .topLeading) {
                    if draft.isEmpty {
                        Text("How did it go? Partners, techniques, how you felt…")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
        }
        .onAppear {
            guard !loaded else { return }
            draft = record.notes
            loaded = true
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { commit() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { commit() }
        }
        .onDisappear { commit() }
    }

    private func commit() {
        guard loaded, !record.isDeleted, record.modelContext != nil, draft != record.notes else { return }
        SessionStore(context: modelContext).setNotes(draft, of: record)
    }
}

/// Rough per-session footprint. Health doesn't expose its storage, so that
/// side is samples × an assumed per-sample cost; the buffer file is measured.
private struct StorageEstimate: View {
    let summary: TrainingSummary
    let bufferBytes: Int

    /// Assumed Health database cost per sample (value, dates, source,
    /// indexes). An estimate, not a measurement.
    private static let bytesPerHealthSample = 100
    /// SwiftData row for the session plus its rounds — a few hundred bytes.
    private static let metadataBytes = 1_000

    private var healthSamples: Int {
        summary.points.count + summary.energy.count + summary.rounds.count + 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Storage")
                .font(.headline)
            LabeledContent("In Health") {
                Text("≈ \(Self.format(healthSamples * Self.bytesPerHealthSample)) · \(healthSamples.formatted()) samples")
            }
            LabeledContent("On this phone") {
                Text("≈ \(Self.format(Self.metadataBytes + bufferBytes))")
            }
            Text(bufferBytes > 0
                 ? "Includes a \(Self.format(bufferBytes)) backup of your readings, deleted once the session is saved to Health."
                 : "Session details only; your readings live in Health.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .monospacedDigit()
    }

    private static func format(_ bytes: Int) -> String {
        Int64(bytes).formatted(.byteCount(style: .file))
    }
}

private struct StatTile: View {
    let value: String
    let unit: String?
    let label: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.tint)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .monospacedDigit()
                if let unit {
                    Text(unit).font(.headline)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}
#endif
