//
//  HeartRateChart.swift
//  AthleteFeatures
//
//  Polar-style heart rate trace: the bpm line over horizontal %-of-max zone
//  bands, bpm on the left axis, % of max on the right, elapsed time below.
//  The ceiling and resume lines are labelled so they read without color.
//

#if os(iOS)
import SwiftUI
import Charts
import SessionEngine

struct HeartRateChart: View {
    let points: [HRPoint]
    let hrMax: Int
    let zone: ResolvedZone
    let timeDomain: ClosedRange<TimeInterval>

    /// Readings further apart than this are drawn as separate segments, so a
    /// signal dropout shows as a gap instead of a misleading straight line.
    private static let gap: TimeInterval = 5
    /// Banded like Polar: 50–100% of max in 10% steps; below 50% is unshaded.
    private static let bandZones: [HRZone] = [.z1, .z2, .z3, .z4, .z5]
    private static let tickPercents: [Double] = [50, 60, 70, 80, 90, 100]

    private var visible: [HRPoint] {
        points.filter { timeDomain.contains($0.t) }
    }

    private var bpmDomain: ClosedRange<Double> {
        let bpms = visible.map { Double($0.bpm) }
        let lower = min(Double(hrMax) * 0.45, (bpms.min() ?? .infinity) - 5)
        let upper = max(Double(hrMax), (bpms.max() ?? 0) + 3)
        return lower...upper
    }

    private var ticks: [Double] {
        Self.tickPercents.map { Double(hrMax) * $0 / 100 }
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("bpm")
                Spacer()
                Text("%")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)

            chart
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var chart: some View {
        let domain = bpmDomain
        let segments = segments
        return Chart {
            ForEach(Self.bandZones) { band in
                RectangleMark(
                    xStart: .value("Start", timeDomain.lowerBound),
                    xEnd: .value("End", timeDomain.upperBound),
                    yStart: .value("Low", Double(hrMax) * band.lowerPercent / 100),
                    yEnd: .value("High", band == .z5
                                 ? domain.upperBound
                                 : Double(hrMax) * (band.lowerPercent + 10) / 100)
                )
                .foregroundStyle(band.bandColor.opacity(0.35))
            }

            ForEach(segments.indices, id: \.self) { s in
                ForEach(segments[s], id: \.t) { point in
                    LineMark(
                        x: .value("Time", point.t),
                        y: .value("bpm", Double(point.bpm)),
                        series: .value("Segment", s)
                    )
                    .foregroundStyle(Color.primary)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
                }
            }

            RuleMark(y: .value("Ceiling", Double(zone.ceilingBPM)))
                .foregroundStyle(.red)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .annotation(position: .top, alignment: .leading, spacing: 2) {
                    lineLabel("Ceiling \(zone.ceilingBPM)", color: .red)
                }
            RuleMark(y: .value("Resume", Double(zone.resetBPM)))
                .foregroundStyle(.green)
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .annotation(position: .bottom, alignment: .leading, spacing: 2) {
                    lineLabel("Resume \(zone.resetBPM)", color: .green)
                }
        }
        .chartXScale(domain: timeDomain)
        .chartYScale(domain: domain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel {
                    if let t = value.as(Double.self) { Text(Self.clock(t)) }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: ticks) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let bpm = value.as(Double.self) { Text("\(Int(bpm.rounded()))") }
                }
            }
            AxisMarks(position: .trailing, values: ticks) { value in
                AxisValueLabel {
                    if let bpm = value.as(Double.self) {
                        Text("\(Int((bpm / Double(hrMax) * 100).rounded()))")
                    }
                }
            }
        }
        .chartPlotStyle { $0.clipped() }
    }

    private var segments: [[HRPoint]] {
        var result: [[HRPoint]] = []
        for point in visible {
            if let last = result.last?.last, point.t - last.t <= Self.gap {
                result[result.count - 1].append(point)
            } else {
                result.append([point])
            }
        }
        return result
    }

    private func lineLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold).monospacedDigit())
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .background(.background.opacity(0.8), in: Capsule())
    }

    private var accessibilitySummary: String {
        let range = visible.isEmpty
            ? "No heart rate recorded"
            : "Heart rate from \(visible.map(\.bpm).min()!) to \(visible.map(\.bpm).max()!) bpm"
        return "\(range). Ceiling \(zone.ceilingBPM), resume \(zone.resetBPM)."
    }

    /// Elapsed time as m:ss, or h:mm:ss past an hour.
    static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}

private extension HRZone {
    /// Mirrors the zone palette used on the Intensity tab.
    var bandColor: Color {
        switch self {
        case .z0: return .gray
        case .z1: return .blue
        case .z2: return .green
        case .z3: return .yellow
        case .z4: return .orange
        case .z5: return .red
        }
    }
}
#endif
