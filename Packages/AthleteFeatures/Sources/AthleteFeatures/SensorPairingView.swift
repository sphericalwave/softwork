//
//  SensorPairingView.swift
//  AthleteFeatures
//
//  Pick your own strap in a crowded gym (REQ-HR-2, amended): nearby straps
//  sorted by signal strength while scanning; live bpm appears once connected
//  (BLE heart rate only notifies after connection).
//

#if os(iOS)
import SwiftUI
import CoreBluetooth
import HeartRateKit

struct SensorPairingView: View {
    @ObservedObject var ble: BLEHeartRateSource
    let liveBPM: Int?
    @Environment(\.dismiss) private var dismiss

    private var sorted: [HRDiscovery] {
        ble.discoveries.sorted { $0.rssi > $1.rssi }
    }

    var body: some View {
        NavigationStack {
            List {
                if let connected = ble.connected {
                    Section("Connected") {
                        HStack {
                            Label(connected.name ?? "Heart rate strap", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Spacer()
                            Text(liveBPM.map { "\($0) bpm" } ?? "Waiting for reading…")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Button("Forget this strap", role: .destructive) {
                            ble.forgetDevice()
                            ble.scan()
                        }
                    }
                }

                Section {
                    if ble.state != .poweredOn {
                        Label("Turn on Bluetooth to find straps", systemImage: "antenna.radiowaves.left.and.right.slash")
                            .foregroundStyle(.secondary)
                    } else if sorted.isEmpty {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Looking for straps… Wet the strap and put it on.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    ForEach(sorted.filter { $0.id != ble.connected?.identifier }) { strap in
                        Button {
                            if let peripheral = ble.discovered.first(where: { $0.identifier == strap.id }) {
                                ble.select(peripheral)
                            }
                        } label: {
                            HStack {
                                Text(strap.name ?? "Unnamed strap")
                                Spacer()
                                SignalBars(rssi: strap.rssi)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Nearby")
                } footer: {
                    Text("The strongest signal is usually the strap you're wearing. Your heart rate shows after you connect.")
                }
            }
            .navigationTitle("Heart Rate Strap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { ble.scan() }
            .onDisappear { ble.stopScanning() }
        }
    }
}

private struct SignalBars: View {
    let rssi: Int

    private var bars: Int {
        switch rssi {
        case (-60)...: return 3
        case (-75)...: return 2
        default: return 1
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i <= bars ? Color.primary : Color.secondary.opacity(0.3))
                    .frame(width: 4, height: CGFloat(4 + i * 4))
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Signal \(bars) of 3")
    }
}
#endif
