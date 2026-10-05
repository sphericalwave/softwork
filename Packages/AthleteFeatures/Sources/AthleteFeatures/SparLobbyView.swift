//
//  SparLobbyView.swift
//  AthleteFeatures
//
//  Pre-session checks in the order they matter: strap, workout type,
//  sparring ceiling, alarm, start.
//

#if os(iOS)
import SwiftUI
import SessionEngine
import HeartRateKit

struct SparLobbyView: View {
    let model: SoloSparringModel

    @AppStorage("sparCeilingPct") private var ceilingPct = SparringPrescription().ceilingPct
    @AppStorage("sparNoFlashing") private var noFlashing = false
    @AppStorage("trainingKind") private var kind: WorkoutKind = .wrestling
    @State private var showingPairing = false

    private var prescription: SparringPrescription {
        SparringPrescription(ceilingPct: ceilingPct)
    }

    private var zone: ResolvedZone? { model.preview(prescription) }

    private var sensorReady: Bool { model.signal == .good }

    var body: some View {
        NavigationStack {
            Form {
                Section("Heart Rate Strap") {
                    Button {
                        if model.ble != nil { showingPairing = true }
                    } label: {
                        HStack {
                            SignalLabel(signal: model.signal)
                            Spacer()
                            if let bpm = model.bpm {
                                Text("\(bpm) bpm").monospacedDigit().foregroundStyle(.secondary)
                            }
                            if model.ble != nil {
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Section {
                    Picker("Workout", selection: $kind) {
                        ForEach(WorkoutKind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Workout")
                } footer: {
                    Text("Saved to Health as this workout type when you end the session.")
                }

                Section {
                    Stepper(value: $ceilingPct, in: 0.72...0.95, step: 0.01) {
                        HStack {
                            Text("Ceiling")
                            Spacer()
                            Text("\(Int((ceilingPct * 100).rounded()))%")
                                .monospacedDigit()
                        }
                    }
                    if let zone {
                        LabeledContent("Timeout above", value: "\(zone.ceilingBPM) bpm")
                        LabeledContent("Resume at or below", value: "\(zone.resetBPM) bpm")
                    }
                } header: {
                    Text("Sparring Prescription")
                } footer: {
                    Text("Applies to each sparring round; you can change it between rounds. Over the ceiling for \(prescription.triggerSeconds) s calls a timeout. Breathe down below the reset for \(prescription.resetHoldSeconds) s to resume. Max HR \(model.hrMax) bpm.")
                }

                Section {
                    Button {
                        model.testAlarm()
                    } label: {
                        Label("Test alarm", systemImage: "speaker.wave.3")
                    }
                    Toggle("No flashing", isOn: $noFlashing)
                } header: {
                    Text("Alarm")
                } footer: {
                    Text("The alarm plays even with the silent switch on. Check your volume.")
                }

                Section {
                    Button {
                        model.startTraining(kind: kind)
                    } label: {
                        Text("Start Training")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!sensorReady)
                    .listRowBackground(Color.clear)
                } footer: {
                    if !sensorReady {
                        Text(model.signal == .noContact
                             ? "Your strap isn't reading skin contact. Wet the electrodes and tighten it."
                             : "Connect your strap to start.")
                    } else {
                        Text("Records your heart rate until you end the session. Start sparring rounds from the session screen.")
                    }
                }
            }
            .navigationTitle("Spar")
            .sheet(isPresented: $showingPairing) {
                if let ble = model.ble {
                    SensorPairingView(ble: ble, liveBPM: model.bpm)
                }
            }
        }
    }
}

struct SignalLabel: View {
    let signal: HRSignalState

    var body: some View {
        switch signal {
        case .good:
            Label("Strap connected", systemImage: "heart.fill").foregroundStyle(.green)
        case .noContact:
            Label("No skin contact", systemImage: "hand.raised").foregroundStyle(.orange)
        case .stale:
            Label("Signal lost", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        case .disconnected:
            Label("Connect strap", systemImage: "antenna.radiowaves.left.and.right").foregroundStyle(.secondary)
        }
    }
}
#endif
