//
//  OverviewView.swift
//  flow
//
//  The landing "big picture": metric tiles + HRV / active-energy trends.
//

import SwiftUI
import SwDesignSystem

struct OverviewView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Binding var window: DashboardViewModel.TimeWindow
    let refresh: () async -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    tiles
                    WindowPicker(window: $window, refresh: refresh)

                    TrendChart(title: "HRV",
                               unit: "ms avg / day",
                               series: viewModel.hrvTrend,
                               tint: .green,
                               style: .line)

                    TrendChart(title: "Active Energy",
                               unit: "kcal / day",
                               series: viewModel.activeEnergyTrend,
                               tint: .orange,
                               style: .bar)
                }
                .padding()
            }
            .navigationTitle("Overview")
            .toolbarBackground(SwTheme.primaryColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
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

/// Shared 7/30/90-day selector that re-runs the load on change.
struct WindowPicker: View {
    @Binding var window: DashboardViewModel.TimeWindow
    let refresh: () async -> Void

    var body: some View {
        Picker("Window", selection: $window) {
            ForEach(DashboardViewModel.TimeWindow.allCases) { w in
                Text(w.label).tag(w)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: window) { _, _ in
            Task { await refresh() }
        }
    }
}
