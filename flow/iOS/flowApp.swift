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

    // No SwTheme.configure(): its UINavigationBar/UISegmentedControl appearance
    // fights brandedToolbars() and the system segmented control in the nav bar.

    var body: some Scene {
        WindowGroup {
            RootView(health: health)
                .environmentObject(health)
                .tint(SwTheme.primaryColor)
        }
        .modelContainer(sharedModelContainer)
    }
}
