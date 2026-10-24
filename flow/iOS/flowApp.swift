//
//  flowApp.swift
//  flow
//
//  Created by Aaron McGrath on 2026-07-04.
//

import SwiftUI
import SwiftData
import SwDesignSystem
import AthleteFeatures

@main
struct flowApp: App {
    @StateObject private var health = HealthKitService()

    let sharedModelContainer: ModelContainer
    /// Made here, at launch, rather than when Spar first shows: when iOS
    /// relaunches flow in the background for the strap (Bluetooth state
    /// restoration after a background kill), no screen appears, yet an open
    /// session must resume and keep recording.
    @State private var spar: SoloSparringModel

    /// The Simulator has no Bluetooth, so sparring there runs on scripted heart rate.
    private static let simulatedHR: Bool = {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }()

    init() {
        let container = AppModelContainer.make()
        sharedModelContainer = container
        let spar = SoloSparringModel.make(context: container.mainContext, simulatedHR: Self.simulatedHR)
        spar.launch()
        _spar = State(initialValue: spar)
    }

    // No SwTheme.configure(): its UINavigationBar/UISegmentedControl appearance
    // fights brandedToolbars() and the system segmented control in the nav bar.

    var body: some Scene {
        WindowGroup {
            RootView(health: health, spar: spar)
                .environmentObject(health)
                .tint(SwTheme.primaryColor)
        }
        .modelContainer(sharedModelContainer)
    }
}
