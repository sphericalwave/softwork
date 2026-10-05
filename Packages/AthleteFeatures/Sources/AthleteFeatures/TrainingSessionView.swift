//
//  TrainingSessionView.swift
//  AthleteFeatures
//
//  The session is recording but no game is running: live bpm, the whole
//  session so far with past sparring rounds shaded, and the one big action —
//  start a sparring round at the chosen ceiling.
//

#if os(iOS)
import SwiftUI
import SessionEngine

struct TrainingSessionView: View {
    let model: SoloSparringModel

    @AppStorage("sparCeilingPct") private var ceilingPct = SparringPrescription().ceilingPct
    @State private var confirmingEnd = false

    private var prescription: SparringPrescription {
        SparringPrescription(ceilingPct: ceilingPct)
    }

    private var zone: ResolvedZone? { model.preview(prescription) }

    var body: some View {
        VStack(spacing: 20) {
            header

            Text(model.bpm.map(String.init) ?? "--")
                .font(.system(size: 96, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .contentTransition(.numericText())
                .accessibilityLabel(model.bpm.map { "\($0) beats per minute" } ?? "No heart rate")

            HeartRateChart(points: model.points, hrMax: model.sessionHRMax,
                           rounds: model.rounds, timeDomain: 0...max(model.elapsed, 60))
                .frame(maxHeight: 260)

            if model.signal != .good {
                SignalLabel(signal: model.signal)
                    .font(.headline)
            }

            Spacer(minLength: 0)

            sparringControls
        }
        .padding()
        .confirmationDialog("End this training session?", isPresented: $confirmingEnd, titleVisibility: .visible) {
            Button("End & Save to Health", role: .destructive) { model.endSession() }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.kind.label)
                    .font(.headline)
                Text(HeartRateChart.clock(model.elapsed))
                    .font(.title2.monospacedDigit())
                    .accessibilityLabel("Elapsed \(HeartRateChart.clock(model.elapsed))")
            }
            Spacer()
            if !model.rounds.isEmpty {
                Label("\(model.rounds.count)", systemImage: "figure.martial.arts")
                    .font(.title3.monospacedDigit())
                    .accessibilityLabel("\(model.rounds.count) sparring rounds")
            }
            Button("End") { confirmingEnd = true }
                .font(.headline)
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
    }

    private var sparringControls: some View {
        VStack(spacing: 12) {
            Stepper(value: $ceilingPct, in: 0.72...0.95, step: 0.01) {
                HStack {
                    Text("Ceiling \(Int((ceilingPct * 100).rounded()))%")
                    Spacer()
                    if let zone {
                        Text("\(zone.ceilingBPM) bpm")
                            .foregroundStyle(.secondary)
                    }
                }
                .monospacedDigit()
            }

            Button {
                model.startSparring(with: prescription)
            } label: {
                Text("Start Sparring")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(zone == nil || model.signal != .good)
        }
    }
}
#endif
