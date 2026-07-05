//
//  RootView.swift
//  softwork
//
//  Root tab container. Selection persists across launches (@AppStorage).
//

import SwiftUI
import SwiftData

struct RootView: View {
    @EnvironmentObject private var health: HealthKitService
    @Environment(\.modelContext) private var modelContext
    @Query private var snapshots: [MetricSnapshot]

    @AppStorage("softworkSelectedTab") private var selectedTab = 0
    @AppStorage("hrMaxOverride") private var hrMaxOverride = 0
    @AppStorage("dashboardWindow") private var windowRaw = DashboardViewModel.TimeWindow.month.rawValue

    @StateObject private var viewModel: DashboardViewModel

    init(health: HealthKitService) {
        _viewModel = StateObject(wrappedValue: DashboardViewModel(health: health))
    }

    private var windowBinding: Binding<DashboardViewModel.TimeWindow> {
        Binding(
            get: { DashboardViewModel.TimeWindow(rawValue: windowRaw) ?? .month },
            set: { windowRaw = $0.rawValue }
        )
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            OverviewView(viewModel: viewModel, window: windowBinding, refresh: refresh)
                .tabItem { Label("Overview", systemImage: "heart.text.square") }
                .tag(0)

            IntensityView(viewModel: viewModel, window: windowBinding, refresh: refresh)
                .tabItem { Label("Intensity", systemImage: "flame") }
                .tag(1)

            SettingsView(health: health, resolvedAge: health.ageInYears(), onChange: refresh)
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(2)
        }
        .task {
            viewModel.primeFromCache(snapshots.first)
            try? await health.requestAuthorization()
            await refresh()
        }
    }

    private func refresh() async {
        let window = DashboardViewModel.TimeWindow(rawValue: windowRaw) ?? .month
        await viewModel.refresh(window: window, hrMaxOverride: hrMaxOverride, context: modelContext)
    }
}
