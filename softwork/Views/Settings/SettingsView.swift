//
//  SettingsView.swift
//  softwork
//
//  HR max configuration and HealthKit access.
//

import SwiftUI

struct SettingsView: View {
    let health: HealthKitService
    let resolvedAge: Int?
    let onChange: () async -> Void

    @AppStorage("hrMaxOverride") private var hrMaxOverride = 0

    private var autoHRMax: Int {
        HealthKitService.effectiveHRMax(override: 0, age: resolvedAge)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Override")
                        Spacer()
                        TextField(autoPlaceholder, value: $hrMaxOverride, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                    }
                    if hrMaxOverride > 0 {
                        Button("Use age-based (\(autoHRMax))") { hrMaxOverride = 0 }
                            .font(.caption)
                    }
                } header: {
                    Text("Max Heart Rate")
                } footer: {
                    Text(resolvedAge == nil
                         ? "Set an override, or add your birth date in Health for an age-based estimate (220 − age)."
                         : "Auto estimate is 220 − age (\(autoHRMax) bpm). Enter a value to override.")
                }
                .onChange(of: hrMaxOverride) { _, _ in
                    Task { await onChange() }
                }

                Section("Health Access") {
                    Button("Re-request Health permissions") {
                        Task {
                            try? await health.requestAuthorization()
                            await onChange()
                        }
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var autoPlaceholder: String {
        resolvedAge == nil ? "e.g. 190" : "\(autoHRMax)"
    }
}
