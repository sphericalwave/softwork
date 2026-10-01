//
//  flowApp.swift
//  flow
//
//  macOS entry point. The Mac is the coach workspace; live sparring,
//  Bluetooth straps and HealthKit dashboards stay on iPhone/iPad.
//  SwDesignSystem is UIKit-only, so the Mac uses the asset-catalog AccentColor.
//

import SwiftUI
import SwiftData

@main
struct flowApp: App {
    var sharedModelContainer: ModelContainer = AppModelContainer.make()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(sharedModelContainer)
    }
}
