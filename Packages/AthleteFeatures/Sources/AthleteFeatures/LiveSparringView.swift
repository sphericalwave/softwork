//
//  LiveSparringView.swift
//  AthleteFeatures
//
//  Readable at a glance from the mat: huge bpm, a live trace against the
//  ceiling, and every state carried by text + icon, never color alone
//  (REQ-ALERT-5/6).
//

#if os(iOS)
import SwiftUI
import SessionEngine
import AlertKit

struct LiveSparringView: View {
    let model: SoloSparringModel
    @AppStorage("sparNoFlashing") private var noFlashing = false
    @State private var confirmingStop = false

    private var band: LiveBand? {
        guard let bpm = model.bpm, let zone = model.zone else { return nil }
        return zone.band(for: bpm)
    }

    /// The live chart follows the last few minutes so recent spikes stay legible.
    private static let window: TimeInterval = 5 * 60

    private var timeDomain: ClosedRange<TimeInterval> {
        let upper = max(model.elapsed, 60)
        return max(upper - Self.window, 0)...upper
    }

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            VStack(spacing: 24) {
                header
                Spacer()
                heartRate
                HeartRateChart(points: model.points, hrMax: model.sessionHRMax,
                               rounds: model.chartRounds, timeDomain: timeDomain)
                    .frame(height: 240)
                Spacer()
                if model.signal != .good {
                    SignalLabel(signal: model.signal)
                        .font(.title3.weight(.semibold))
                        .padding()
                        .background(.thinMaterial, in: Capsule())
                }
            }
            .padding()

            overlay
        }
        .confirmationDialog("Stop sparring?", isPresented: $confirmingStop, titleVisibility: .visible) {
            Button("Stop Sparring", role: .destructive) { model.stopSparring() }
        } message: {
            Text("Training keeps recording.")
        }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack {
            Label("\(model.timeoutCount)", systemImage: "hand.raised.fill")
                .font(.title3.monospacedDigit())
                .accessibilityLabel("\(model.timeoutCount) timeouts")
            Spacer()
            Button("Stop") { confirmingStop = true }
                .font(.headline)
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
    }

    private var heartRate: some View {
        VStack(spacing: 8) {
            Text(model.bpm.map(String.init) ?? "--")
                .font(.system(size: 120, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .contentTransition(.numericText())
                .accessibilityLabel(model.bpm.map { "\($0) beats per minute" } ?? "No heart rate")
            if let band {
                BandLabel(band: band)
                    .font(.title2.weight(.semibold))
            }
        }
    }

    private var background: Color {
        switch band {
        case .nearCeiling: return .orange.opacity(0.25)
        case .overCeiling: return .red.opacity(0.3)
        default: return Color(.systemBackground)
        }
    }

    @ViewBuilder
    private var overlay: some View {
        switch model.stage {
        case .countdown(let n):
            FullScreenMessage(title: "\(n)", subtitle: "Get ready", systemImage: "figure.martial.arts", tint: .blue)
        case .timeout:
            ZStack {
                TimeoutFlash(flashingAllowed: !noFlashing).ignoresSafeArea()
                VStack(spacing: 16) {
                    Label("TIMEOUT", systemImage: "hand.raised.fill")
                        .font(.system(size: 56, weight: .heavy))
                    if let bpm = model.bpm, let zone = model.zone {
                        Text("\(bpm) bpm")
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("Breathe down to \(zone.resetBPM) bpm")
                            .font(.title2.weight(.semibold))
                    }
                    if model.minTimeoutRemaining > 0 {
                        Text("Minimum rest: \(model.minTimeoutRemaining) s")
                            .font(.title3.monospacedDigit())
                    }
                }
                .foregroundStyle(.white)
                .padding()
            }
            .accessibilityElement(children: .combine)
        case .resuming(let n):
            FullScreenMessage(title: "\(n)", subtitle: "Reset. Resuming…", systemImage: "checkmark.circle.fill", tint: .green)
        case .lobby, .training, .sparring:
            EmptyView()
        }
    }
}

private struct BandLabel: View {
    let band: LiveBand

    var body: some View {
        switch band {
        case .belowTarget: Label("Below target", systemImage: "arrow.down.circle").foregroundStyle(.secondary)
        case .inTarget: Label("In target", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .nearCeiling: Label("Near ceiling", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .overCeiling: Label("Over ceiling", systemImage: "flame.fill").foregroundStyle(.red)
        }
    }
}

private struct FullScreenMessage: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        ZStack {
            tint.ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: systemImage).font(.system(size: 48))
                Text(title)
                    .font(.system(size: 120, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                Text(subtitle).font(.title.weight(.semibold))
            }
            .foregroundStyle(.white)
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
