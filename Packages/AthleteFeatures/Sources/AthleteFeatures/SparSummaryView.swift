//
//  SparSummaryView.swift
//  AthleteFeatures
//
//  End of session: the numbers first, then the whole-session trace.
//  Only stats measured from the strap — nothing modelled.
//

#if os(iOS)
import SwiftUI
import SessionEngine

struct SparSummaryView: View {
    let summary: SparringSummary
    let onDone: @MainActor () -> Void

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(summary.startedAt.formatted(date: .complete, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: columns, spacing: 12) {
                        StatTile(value: HeartRateChart.clock(summary.duration), unit: nil,
                                 label: "Duration", systemImage: "stopwatch")
                        StatTile(value: "\(summary.timeoutCount)", unit: nil,
                                 label: summary.timeoutCount == 1 ? "Timeout" : "Timeouts",
                                 systemImage: "hand.raised.fill")
                        StatTile(value: summary.averageBPM.map(String.init) ?? "--", unit: "bpm",
                                 label: "HR avg", systemImage: "heart.fill")
                        StatTile(value: summary.maxBPM.map(String.init) ?? "--", unit: "bpm",
                                 label: "HR max", systemImage: "heart.fill")
                        StatTile(value: HeartRateChart.clock(summary.secondsOverCeiling), unit: nil,
                                 label: "Over ceiling (\(summary.zone.ceilingBPM) bpm)",
                                 systemImage: "flame.fill")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Heart Rate")
                            .font(.headline)
                        if summary.points.isEmpty {
                            Text("No heart rate was recorded this session.")
                                .foregroundStyle(.secondary)
                        } else {
                            HeartRateChart(points: summary.points, hrMax: summary.hrMax,
                                           zone: summary.zone,
                                           timeDomain: 0...max(summary.duration, 60))
                                .frame(height: 280)
                        }
                    }
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: onDone) {
                    Text("Done")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .padding()
                .background(.bar)
            }
            .navigationTitle("Session Complete")
        }
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
