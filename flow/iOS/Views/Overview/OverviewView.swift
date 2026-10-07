//
//  OverviewView.swift
//  flow
//
//  The landing "big picture": metric tiles + HRV / active-energy trends.
//

import SwiftUI
import AthleteFeatures

struct OverviewView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Binding var window: DashboardViewModel.TimeWindow
    let refresh: () async -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    tiles

                    TrendChart(title: "HRV",
                               unit: "ms avg / \(bucketName)",
                               series: viewModel.hrvTrend,
                               bucket: window.bucket,
                               tint: .green,
                               style: .line)

                    TrendChart(title: "Active Energy",
                               unit: "kcal / \(bucketName)",
                               series: viewModel.activeEnergyTrend,
                               bucket: window.bucket,
                               tint: .orange,
                               style: .bar)
                }
                .padding()
            }
            .navigationTitle("Overview")
            .brandedToolbars()
            .toolbar {
                ToolbarItem(placement: .principal) {
                    WindowPicker(window: $window)
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

    private var bucketName: String { window.bucket == .hour ? "hour" : "day" }

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

/// Day/Week/Month selector for the nav bar's principal slot. RootView
/// reloads when it changes.
struct WindowPicker: View {
    @Binding var window: DashboardViewModel.TimeWindow

    var body: some View {
        Picker("Timeframe", selection: $window) {
            ForEach(DashboardViewModel.TimeWindow.allCases) { w in
                Text(w.label).tag(w)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 180)
    }
}
