//
//  SettingsView.swift
//  flow
//
//  HR max configuration and HealthKit access.
//

import SwiftUI
import SessionEngine
import DiagnosticsKit

struct SettingsView: View {
    let health: HealthKitService
    let resolvedAge: Int?
    let onChange: () async -> Void

    @AppStorage("hrMaxOverride") private var hrMaxOverride = 0
    @AppStorage("maxHRFormula") private var formula: MaxHRFormula = .tanaka

    private var autoHRMax: Int {
        MaxHeartRate.effective(override: 0, age: resolvedAge, formula: formula)
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
                    Picker("Estimate", selection: $formula) {
                        ForEach(MaxHRFormula.allCases) { Text($0.label).tag($0) }
                    }
                } header: {
                    Text("Max Heart Rate")
                } footer: {
                    Text(resolvedAge == nil
                         ? "Set an override, or add your birth date in Health for an age-based estimate (\(formula.label))."
                         : "Auto estimate is \(formula.label) = \(autoHRMax) bpm. Enter a value to override.")
                }
                .onChange(of: hrMaxOverride) { _, _ in
                    Task { await onChange() }
                }
                .onChange(of: formula) { _, _ in
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

                Section {
                    NavigationLink { DiagnosticsView() } label: {
                        Label("Error Log", systemImage: "ladybug")
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
