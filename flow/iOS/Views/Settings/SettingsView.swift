//
//  SettingsView.swift
//  flow
//
//  HR max, calorie profile, and HealthKit access.
//

import SwiftUI
import SwDesignSystem
import SessionEngine
import AthleteFeatures
import DiagnosticsKit

struct SettingsView: View {
    let health: HealthKitService
    let resolvedAge: Int?
    let onChange: () async -> Void

    @AppStorage("hrMaxOverride") private var hrMaxOverride = 0
    @AppStorage("maxHRFormula") private var formula: MaxHRFormula = .tanaka
    @AppStorage(CalorieSettingsKeys.sex) private var calorieSex = ""
    @AppStorage(CalorieSettingsKeys.weightKg) private var weightKg = 0.0

    /// Number-pad drafts: empty while editing starts, with the current value
    /// as the grey placeholder. Committed on Done, focus loss, tapping
    /// another row, or leaving the screen; left empty, the value stays.
    @State private var hrMaxDraft = ""
    @State private var weightDraft = ""
    @FocusState private var focusedField: NumberField?
    @Environment(\.scenePhase) private var scenePhase

    private enum NumberField: Hashable {
        case hrMax, weight
    }

    private static let usesPounds = Locale.current.measurementSystem == .us
    private static let kgPerPound = 0.45359237

    /// Stored weight in the locale's unit, to one decimal; nil means "use Health".
    private var displayWeight: Double? {
        guard weightKg > 0 else { return nil }
        let value = Self.usesPounds ? weightKg / Self.kgPerPound : weightKg
        return (value * 10).rounded() / 10
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
                        TextField(hrMaxPlaceholder, text: $hrMaxDraft)
                            .focused($focusedField, equals: .hrMax)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { focusedField = .hrMax }
                    if hrMaxOverride > 0 {
                        Button("Use age-based (\(autoHRMax))") {
                            hrMaxDraft = ""
                            hrMaxOverride = 0
                            focusedField = nil
                        }
                        .font(.caption)
                    }
                    Picker("Estimate", selection: $formula) {
                        ForEach(MaxHRFormula.allCases) { Text($0.label).tag($0) }
                    }
                    .simultaneousGesture(TapGesture().onEnded { focusedField = nil })
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
                    .simultaneousGesture(TapGesture().onEnded { focusedField = nil })
                    HStack {
                        Text("Weight")
                        Spacer()
                        TextField(weightPlaceholder, text: $weightDraft)
                            .focused($focusedField, equals: .weight)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 110)
                        Text(Self.usesPounds ? "lb" : "kg")
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { focusedField = .weight }
                    if weightKg > 0 {
                        Button("Use weight from Health") {
                            weightDraft = ""
                            weightKg = 0
                            focusedField = nil
                        }
                        .font(.caption)
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
                    .simultaneousGesture(TapGesture().onEnded { focusedField = nil })
                }

                Section {
                    NavigationLink { VideoSyncView() } label: {
                        Label("GoPro Sync Clock", systemImage: "qrcode")
                    }
                } header: {
                    Text("Video")
                } footer: {
                    Text("Film the sync clock at the start of a GoPro recording, then long-press the workout in Intensity to export its heart rate for the video overlay.")
                }

                Section {
                    NavigationLink { DiagnosticsView().brandedToolbars() } label: {
                        Label("Error Log", systemImage: "ladybug")
                    }
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("Settings")
            .brandedToolbars()
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                        .fontWeight(.semibold)
                }
            }
            .onChange(of: focusedField) { old, _ in
                if let old { commit(old) }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { commitAll() }
            }
            .onDisappear { commitAll() }
        }
    }

    private var autoPlaceholder: String {
        resolvedAge == nil ? "e.g. 190" : "\(autoHRMax)"
    }

    /// The override in effect, else the age-based estimate.
    private var hrMaxPlaceholder: String {
        hrMaxOverride > 0 ? "\(hrMaxOverride)" : autoPlaceholder
    }

    private var weightPlaceholder: String {
        displayWeight.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? "From Health"
    }

    private func commitAll() {
        commit(.hrMax)
        commit(.weight)
    }

    /// Writes a draft back; an empty or unreadable one keeps the stored value.
    private func commit(_ field: NumberField) {
        switch field {
        case .hrMax:
            defer { hrMaxDraft = "" }
            if let value = NumberInput.wholeNumber(hrMaxDraft), value != hrMaxOverride {
                hrMaxOverride = value
            }
        case .weight:
            defer { weightDraft = "" }
            if let value = NumberInput.decimal(weightDraft) {
                let kg = Self.usesPounds ? value * Self.kgPerPound : value
                if abs(kg - weightKg) > 0.001 { weightKg = kg }
            }
        }
    }
}
