//
//  RootView.swift
//  flow
//
//  Root tab container. Selection persists across launches (@AppStorage).
//

import SwiftUI
import SwiftData
import SessionEngine
import AthleteFeatures
import DiagnosticsKit

struct RootView: View {
    @EnvironmentObject private var health: HealthKitService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var snapshots: [MetricSnapshot]

    @AppStorage("flowSelectedTab") private var selectedTab = 0
    @AppStorage("hrMaxOverride") private var hrMaxOverride = 0
    @AppStorage("maxHRFormula") private var maxHRFormula: MaxHRFormula = .tanaka
    @AppStorage("dashboardWindow") private var windowRaw = DashboardViewModel.TimeWindow.week.rawValue

    @StateObject private var viewModel: DashboardViewModel

    init(health: HealthKitService) {
        _viewModel = StateObject(wrappedValue: DashboardViewModel(health: health))
    }

    /// The Simulator has no Bluetooth, so sparring there runs on scripted heart rate.
    private static let simulatedHR: Bool = {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }()

    private var hrMax: Int {
        MaxHeartRate.effective(override: hrMaxOverride, age: health.ageInYears(), formula: maxHRFormula)
    }

    private var window: DashboardViewModel.TimeWindow {
        DashboardViewModel.TimeWindow(rawValue: windowRaw) ?? .week
    }

    private var windowBinding: Binding<DashboardViewModel.TimeWindow> {
        Binding(
            get: { window },
            set: { windowRaw = $0.rawValue }
        )
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            SparView(hrMax: hrMax, simulatedHR: Self.simulatedHR)
                .tabItem { Label("Spar", systemImage: "figure.martial.arts") }
                .tag(3)

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
            viewModel.primeIntensities(for: window)
            do {
                try await health.requestAuthorization()
            } catch {
                ErrorLog.shared.error("Health", "Health authorization request failed", error: error)
            }
            await refresh()
        }
        .onChange(of: windowRaw) { _, _ in
            viewModel.primeIntensities(for: window)
            Task { await refresh() }
        }
        // Training sessions not yet in Health are retried at launch and on
        // every return to the foreground, whichever tab is showing.
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            Task { await HealthSessionSync.shared.syncPending(context: modelContext) }
        }
    }

    private func refresh() async {
        await viewModel.refresh(window: window, hrMaxOverride: hrMaxOverride, formula: maxHRFormula, context: modelContext)
    }
}
