//
//  softworkApp.swift
//  softwork
//
//  Created by Aaron McGrath on 2026-07-04.
//

import SwiftUI
import SwiftData
import SwDesignSystem

@main
struct softworkApp: App {
    @StateObject private var health = HealthKitService()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([MetricSnapshot.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        SwTheme.configure()
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
