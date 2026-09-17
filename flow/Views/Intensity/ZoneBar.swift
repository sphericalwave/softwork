//
//  ZoneBar.swift
//  flow
//
//  Horizontal stacked bar of time-in-zone proportions.
//

import SwiftUI

struct ZoneBar: View {
    let zoneSeconds: [HRZone: TimeInterval]

    private var total: TimeInterval {
        max(zoneSeconds.values.reduce(0, +), 1)
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(HRZone.allCases) { zone in
                    let seconds = zoneSeconds[zone] ?? 0
                    if seconds > 0 {
                        Rectangle()
                            .fill(zone.color)
                            .frame(width: geo.size.width * CGFloat(seconds / total))
                    }
                }
            }
        }
        .frame(height: 12)
        .clipShape(Capsule())
        .background(Capsule().fill(Color.gray.opacity(0.15)))
    }
}

/// Legend + minutes for each zone, used under the aggregate bar.
struct ZoneLegend: View {
    let zoneSeconds: [HRZone: TimeInterval]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(HRZone.allCases) { zone in
                HStack(spacing: 8) {
                    Circle().fill(zone.color).frame(width: 8, height: 8)
                    Text("\(zone.label) · \(zone.name)")
                        .font(.caption)
                    Spacer()
                    Text(minutes(zoneSeconds[zone] ?? 0))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func minutes(_ seconds: TimeInterval) -> String {
        "\(Int((seconds / 60).rounded())) min"
    }
}
