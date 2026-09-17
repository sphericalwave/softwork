//
//  SparView.swift
//  AthleteFeatures
//
//  Entry point for single-device sparring: lobby, then the live screen.
//

#if os(iOS)
import SwiftUI
import SessionEngine
import HeartRateKit
import AlertKit

public struct SparView: View {
    private let hrMax: Int
    private let simulatedHR: Bool
    @State private var model: SoloSparringModel?

    /// - Parameters:
    ///   - hrMax: resolved max heart rate for this athlete.
    ///   - simulatedHR: debug aid — drives the screen from a scripted spike
    ///     instead of a strap, so the timeout flow can be seen in the Simulator.
    public init(hrMax: Int, simulatedHR: Bool = false) {
        self.hrMax = hrMax
        self.simulatedHR = simulatedHR
    }

    public var body: some View {
        Group {
            if let model {
                if model.stage == .lobby {
                    SparLobbyView(model: model)
                } else {
                    LiveSparringView(model: model)
                }
            } else {
                Color.clear
            }
        }
        .onAppear {
            if model == nil { model = makeModel() }
            model?.activate()
        }
        .onDisappear { model?.deactivate() }
        .onChange(of: hrMax) { _, newValue in model?.hrMax = newValue }
    }

    private func makeModel() -> SoloSparringModel {
        let alerts = SystemAlertOutput()
        if simulatedHR, let zone = SparringPrescription().resolve(hrMax: hrMax) {
            let mock = MockHeartRateSource(profile: .spike(baseline: zone.resetBPM - 8,
                                                           peak: zone.ceilingBPM + 12,
                                                           at: 15, duration: 12))
            return SoloSparringModel(hrMax: hrMax, source: mock, ble: nil, alerts: alerts)
        }
        let ble = BLEHeartRateSource()
        return SoloSparringModel(hrMax: hrMax, source: ble, ble: ble, alerts: alerts)
    }
}
#endif
