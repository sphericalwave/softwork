//
//  LiveSparringView.swift
//  AthleteFeatures
//
//  Readable at a glance from the mat: huge bpm, where it sits against the
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
    @State private var confirmingEnd = false

    private var band: LiveBand? {
        guard let bpm = model.bpm, let zone = model.zone else { return nil }
        return zone.band(for: bpm)
    }

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            VStack(spacing: 24) {
                header
                Spacer()
                heartRate
                if let zone = model.zone {
                    CeilingGauge(bpm: model.bpm, zone: zone)
                        .padding(.horizontal)
                }
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
        .confirmationDialog("End this session?", isPresented: $confirmingEnd, titleVisibility: .visible) {
            Button("End Session", role: .destructive) { model.endSession() }
        }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack {
            Label("\(model.timeoutCount)", systemImage: "hand.raised.fill")
                .font(.title3.monospacedDigit())
                .accessibilityLabel("\(model.timeoutCount) timeouts")
            Spacer()
            Button("End") { confirmingEnd = true }
                .font(.headline)
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
    }

    private var heartRate: some View {
        VStack(spacing: 8) {
            Text(model.bpm.map(String.init) ?? "--")
                .font(.system(size: 140, weight: .bold, design: .rounded))
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
        case .lobby, .sparring:
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

/// Current bpm on a track from the target floor to just past the ceiling,
/// with the reset and ceiling marked.
private struct CeilingGauge: View {
    let bpm: Int?
    let zone: ResolvedZone

    private var lower: Double { Double(zone.floorBPM - 15) }
    private var upper: Double { Double(zone.ceilingBPM + 15) }

    private func fraction(_ value: Int) -> CGFloat {
        CGFloat(min(max((Double(value) - lower) / (upper - lower), 0), 1))
    }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.2))
                    if let bpm {
                        Capsule()
                            .fill(color(for: zone.band(for: bpm)))
                            .frame(width: geo.size.width * fraction(bpm))
                    }
                    marker(at: fraction(zone.resetBPM), width: geo.size.width, color: .green)
                    marker(at: fraction(zone.ceilingBPM), width: geo.size.width, color: .red)
                }
            }
            .frame(height: 24)
            HStack {
                Text("reset \(zone.resetBPM)").foregroundStyle(.green)
                Spacer()
                Text("ceiling \(zone.ceilingBPM)").foregroundStyle(.red)
            }
            .font(.caption.weight(.semibold).monospacedDigit())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ceiling \(zone.ceilingBPM), reset \(zone.resetBPM)")
    }

    private func marker(at x: CGFloat, width: CGFloat, color: Color) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: 3, height: 32)
            .offset(x: x * width - 1.5)
    }

    private func color(for band: LiveBand) -> Color {
        switch band {
        case .belowTarget: return .blue
        case .inTarget: return .green
        case .nearCeiling: return .orange
        case .overCeiling: return .red
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
