//
//  SettingsView.swift
//  flow
//
//  HR max, calorie profile, and HealthKit access.
//

import SwiftUI
import SessionEngine
import AthleteFeatures

struct SettingsView: View {
    let health: HealthKitService
    let resolvedAge: Int?
    let onChange: () async -> Void

    @AppStorage("hrMaxOverride") private var hrMaxOverride = 0
    @AppStorage("maxHRFormula") private var formula: MaxHRFormula = .tanaka
    @AppStorage(CalorieSettingsKeys.sex) private var calorieSex = ""
    @AppStorage(CalorieSettingsKeys.weightKg) private var weightKg = 0.0

    private static let usesPounds = Locale.current.measurementSystem == .us
    private static let kgPerPound = 0.45359237

    /// Weight in the locale's unit; nil (empty field) means "use Health".
    private var weightBinding: Binding<Double?> {
        Binding(
            get: {
                guard weightKg > 0 else { return nil }
                let value = Self.usesPounds ? weightKg / Self.kgPerPound : weightKg
                return (value * 10).rounded() / 10
            },
            set: { newValue in
                guard let newValue, newValue > 0 else { weightKg = 0; return }
                weightKg = Self.usesPounds ? newValue * Self.kgPerPound : newValue
            }
        )
    }

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

                Section {
                    Picker("Sex", selection: $calorieSex) {
                        Text("From Health").tag("")
                        ForEach(CalorieProfile.Sex.allCases) { sex in
                            Text(sex.rawValue.capitalized).tag(sex.rawValue)
                        }
                    }
                    HStack {
                        Text("Weight")
                        Spacer()
                        TextField("From Health", value: weightBinding, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 110)
                        Text(Self.usesPounds ? "lb" : "kg")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Calories")
                } footer: {
                    Text("Training calories are estimated from heart rate using your sex, weight and age (birth date from Health). Leave these on From Health to use what Health has.")
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
