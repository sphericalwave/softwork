//
//  SparView.swift
//  AthleteFeatures
//
//  Entry point for single-device training: lobby, the recording session
//  (with sparring rounds inside it), then the session summary.
//

#if os(iOS)
import SwiftUI

public struct SparView: View {
    private let hrMax: Int
    private let model: SoloSparringModel

    /// - Parameters:
    ///   - hrMax: resolved max heart rate for this athlete.
    ///   - model: the app's one model, made at launch by `SoloSparringModel.make`.
    public init(hrMax: Int, model: SoloSparringModel) {
        self.hrMax = hrMax
        self.model = model
    }

    public var body: some View {
        Group {
            switch model.stage {
            case .lobby:
                if let summary = model.summary {
                    SparSummaryView(summary: summary, model: model)
                } else {
                    SparLobbyView(model: model)
                }
            case .training:
                TrainingSessionView(model: model)
            case .countdown, .sparring, .timeout, .resuming:
                LiveSparringView(model: model)
            }
        }
        .onAppear {
            model.hrMax = hrMax
            model.activate()
        }
        .onDisappear { model.deactivate() }
        .onChange(of: hrMax) { _, newValue in model.hrMax = newValue }
    }
}
#endif
