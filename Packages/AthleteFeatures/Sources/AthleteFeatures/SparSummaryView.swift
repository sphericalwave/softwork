//
//  SparSummaryView.swift
//  AthleteFeatures
//
//  End of session: the numbers first, then the whole-session trace with
//  sparring rounds shaded, then where the session was saved. Calories are
//  an estimate from heart rate (CalorieEstimator); everything else is
//  measured.
//

#if os(iOS)
import SwiftUI
import SessionEngine

struct SparSummaryView: View {
    let summary: TrainingSummary
    let model: SoloSparringModel

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("\(summary.kind.label) · \(summary.startedAt.formatted(date: .complete, time: .shortened))")
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

                    HealthSaveStatus(state: model.saveState, kind: summary.kind, retry: { model.retrySave() })

                    StorageEstimate(summary: summary, bufferBytes: model.bufferBytes)
                }
                .padding()
            }
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
        }
    }

    private var roundsLine: String {
        let count = summary.rounds.count
        return "\(count) sparring \(count == 1 ? "round" : "rounds") · \(HeartRateChart.clock(summary.sparringSeconds)) (shaded)"
    }
}

private struct HealthSaveStatus: View {
    let state: SoloSparringModel.SaveState
    let kind: WorkoutKind
    let retry: @MainActor () -> Void

    var body: some View {
        switch state {
        case .idle, .saving:
            HStack(spacing: 8) {
                ProgressView()
                Text("Saving to Health…")
            }
            .foregroundStyle(.secondary)
        case .saved:
            Label("Saved to Health as \(kind.label)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label("Not saved to Health", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.headline)
                Text("\(message) Your session is kept on this phone and will be saved next time flow opens. Check that flow can write workouts in Settings › Health › Data Access.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Try Again", action: retry)
                    .buttonStyle(.bordered)
            }
        }
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
