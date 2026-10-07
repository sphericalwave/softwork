//
//  TrendChart.swift
//  flow
//
//  A titled trend of a daily metric over the selected window (native Swift Charts).
//

import SwiftUI
import Charts

struct TrendChart: View {
    let title: String
    let unit: String
    let series: [Date: Double]
    /// `.hour` for the Day window, `.day` otherwise.
    let bucket: Calendar.Component
    let tint: Color
    /// `.line` for continuous signals (HRV), `.bar` for daily totals (energy).
    let style: Style

    enum Style { case line, bar }

    private var points: [Point] {
        series.map { Point(date: $0.key, value: $0.value) }
              .sorted { $0.date < $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text(unit).font(.caption2).foregroundStyle(.secondary)
            }

            if points.isEmpty {
                Text("No data")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart(points) { point in
                    switch style {
                    case .line:
                        LineMark(x: .value("Time", point.date, unit: bucket),
                                 y: .value(title, point.value))
                            .foregroundStyle(tint)
                            .interpolationMethod(.catmullRom)
                    case .bar:
                        BarMark(x: .value("Time", point.date, unit: bucket),
                                y: .value(title, point.value))
                            .foregroundStyle(tint)
                    }
                }
                .frame(height: 140)
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
    }
}
