//
//  OverviewView.swift
//  flow
//
//  The landing "big picture": metric tiles + HRV / active-energy trends.
//

import SwiftUI
import AthleteFeatures
import SwCharts

struct OverviewView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @AppStorage("overviewChartPeriod") private var period: ChartPeriod = .week
    let refresh: () async -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    tiles

                    PeriodChartView(title: "HRV",
                                    samples: viewModel.hrvSamples,
                                    period: period,
                                    aggregation: .average,
                                    valueLabel: { "\(Int($0.rounded())) ms" },
                                    risingColor: .green,
                                    fallingColor: .red)
                        .padding(14)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))

                    PeriodChartView(title: "Active Energy",
                                    samples: viewModel.activeEnergySamples,
                                    period: period,
                                    aggregation: .sum,
                                    style: .bar,
                                    valueLabel: { $0.formatted(.number.notation(.compactName)) + " kcal" },
                                    barColor: .orange)
                        .padding(14)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
                .padding()
            }
            .navigationTitle("Overview")
            .brandedToolbars()
            .toolbar {
                ToolbarItem(placement: .principal) {
                    PeriodPicker(selection: $period)
                }
            }
            .refreshable { await refresh() }
            .overlay(alignment: .top) {
                if let message = viewModel.errorMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(6)
                }
            }
        }
    }

    private var tiles: some View {
        HStack(spacing: 12) {
            MetricTile(title: "HRV", value: viewModel.latestHRV, unit: "ms",
                       systemImage: "waveform.path.ecg", tint: .green)
            MetricTile(title: "Active", value: viewModel.todayActiveEnergy, unit: "kcal",
                       systemImage: "flame", tint: .orange)
            MetricTile(title: "Resting HR", value: viewModel.restingHR, unit: "bpm",
                       systemImage: "heart", tint: .red)
        }
    }
}
