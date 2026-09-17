//
//  SparLobbyView.swift
//  AthleteFeatures
//
//  Pre-session checks in the order they matter: strap, ceiling, alarm, start.
//

#if os(iOS)
import SwiftUI
import SessionEngine
import HeartRateKit

struct SparLobbyView: View {
    let model: SoloSparringModel

    @AppStorage("sparCeilingPct") private var ceilingPct = SparringPrescription().ceilingPct
    @AppStorage("sparNoFlashing") private var noFlashing = false
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
                    Text("Prescription")
                } footer: {
                    Text("Over the ceiling for \(prescription.triggerSeconds) s calls a timeout. Breathe down below the reset for \(prescription.resetHoldSeconds) s to resume. Max HR \(model.hrMax) bpm.")
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
                        model.start(with: prescription)
                    } label: {
                        Text("Start Sparring")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(zone == nil || !sensorReady)
                    .listRowBackground(Color.clear)
                } footer: {
                    if !sensorReady {
                        Text(model.signal == .noContact
                             ? "Your strap isn't reading skin contact. Wet the electrodes and tighten it."
                             : "Connect your strap to start.")
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
