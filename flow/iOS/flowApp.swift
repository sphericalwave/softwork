//
//  flowApp.swift
//  flow
//
//  Created by Aaron McGrath on 2026-07-04.
//

import SwiftUI
import SwiftData
import SwDesignSystem

@main
struct flowApp: App {
    @StateObject private var health = HealthKitService()

    var sharedModelContainer: ModelContainer = AppModelContainer.make()

    init() {
        SwTheme.configure()
        // SwTheme paints segmented controls white with brand-blue labels, a white
        // slab in dark mode. Keep the brand-blue selected segment; let the rest adapt.
        UISegmentedControl.appearance().backgroundColor = nil
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.label], for: .normal)
    }

    var body: some Scene {
        WindowGroup {
            RootView(health: health)
                .environmentObject(health)
                .tint(SwTheme.primaryColor)
        }
        .modelContainer(sharedModelContainer)
    }
}
