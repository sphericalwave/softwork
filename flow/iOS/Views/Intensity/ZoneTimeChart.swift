//
//  ZoneTimeChart.swift
//  flow
//
//  Minutes in each HR zone per D/W/M period: one Catmull-Rom line per zone,
//  in the zone-bar colors. Bucketed by SwCharts' PeriodBucketer (`.sum`);
//  the unfinished period is a faded dashed segment, as in PeriodChartView.
//  Not selectable — it lives in a swipeable pager.
//

import SwiftUI
import Charts
import SwCharts
import SessionEngine
import ZoneUI

struct ZoneTimeChart: View {
    /// Minutes in each zone per workout, dated by the workout's start.
    let samples: [HRZone: [DatedSample]]
    let period: ChartPeriod
    var now: Date = .now

    private let bucketer = PeriodBucketer()

    private struct Series {
        let zone: HRZone
        let buckets: [PeriodBucket]
    }

    var body: some View {
        let series = HRZone.allCases.map { zone in
            Series(zone: zone, buckets: bucketer.buckets(for: samples[zone] ?? [], period: period,
                                                         aggregation: .sum, now: now))
        }
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Time in zone")
                    .font(.headline)
                Text("\(period.adjective) minutes · \(period.windowDescription)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            legend
            if series.allSatisfy({ $0.buckets.allSatisfy { $0.value == nil } }) {
                Text("No data in the \(period.windowDescription).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                chart(series)
            }
        }
        .padding(.vertical, 4)
    }

    private var legend: some View {
        HStack(spacing: 10) {
            ForEach(HRZone.allCases) { zone in
                HStack(spacing: 3) {
                    Circle().fill(zone.color).frame(width: 7, height: 7)
                    Text(zone.label)
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    private func chart(_ series: [Series]) -> some View {
        let buckets = series.first?.buckets ?? []
        let peak = series.flatMap { $0.buckets.compactMap(\.value) }.max() ?? 0
        return Chart {
            ForEach(series, id: \.zone) { line in
                let plotted = line.buckets.filter { $0.value != nil }
                ForEach(plotted.filter { !$0.isPartial }) { bucket in
                    LineMark(x: .value("Date", Self.midpoint(of: bucket)),
                             y: .value("Minutes", bucket.value ?? 0),
                             series: .value("Zone", line.zone.label))
                        .foregroundStyle(line.zone.color)
                        .interpolationMethod(.catmullRom)
                }
                // "So far": the last full period joined to the partial one, faded and dashed.
                if plotted.last?.isPartial == true {
                    ForEach(plotted.suffix(2)) { bucket in
                        LineMark(x: .value("Date", Self.midpoint(of: bucket)),
                                 y: .value("Minutes", bucket.value ?? 0),
                                 series: .value("Zone", "\(line.zone.label) so far"))
                            .foregroundStyle(line.zone.color.opacity(0.45))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    }
                }
            }
        }
        .chartYScale(domain: 0...Swift.max(peak * 1.1, 1))
        .chartXScale(domain: (buckets.first?.start ?? now)...(buckets.last?.end ?? now))
        .chartXAxis {
            AxisMarks(values: Self.axisBuckets(buckets, period: period).map(Self.midpoint(of:))) { value in
                AxisGridLine()
                AxisValueLabel(anchor: .topTrailing) {
                    if let date = value.as(Date.self) {
                        let start = buckets.last { $0.start <= date }?.start ?? date
                        Text(Self.axisLabel(for: start, period: period))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let minutes = value.as(Double.self) {
                        Text("\(Int(minutes)) min")
                    }
                }
            }
        }
        // Catmull-Rom can overshoot below zero between points; keep it in the plot.
        .chartPlotStyle { $0.clipped() }
        .frame(maxHeight: .infinity)
    }

    nonisolated private static func midpoint(of bucket: PeriodBucket) -> Date {
        bucket.start.addingTimeInterval(bucket.end.timeIntervalSince(bucket.start) / 2)
    }

    /// Every 7th day / 3rd week / 3rd month, counted back from the newest,
    /// matching PeriodChartView's ticks.
    private static func axisBuckets(_ buckets: [PeriodBucket], period: ChartPeriod) -> [PeriodBucket] {
        let stride = period == .day ? 7 : 3
        return buckets.reversed().enumerated()
            .filter { $0.offset % stride == 0 }
            .map(\.element)
            .reversed()
    }

    private static func axisLabel(for date: Date, period: ChartPeriod) -> String {
        switch period {
        case .day, .week: return date.formatted(.dateTime.month(.abbreviated).day())
        case .month:      return date.formatted(.dateTime.month(.abbreviated))
        }
    }
}
