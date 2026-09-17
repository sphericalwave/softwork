//
//  TimeoutFlash.swift
//  AlertKit
//
//  Red timeout backdrop. Flashes at 2 Hz (under the 3 Hz limit, REQ-ALERT-3);
//  with Reduce Motion or the app's "No flashing" setting it becomes solid red
//  with a slow pulse.
//

import SwiftUI

public struct TimeoutFlash: View {
    private let flashingAllowed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    /// Pass the app's "No flashing" preference inverted.
    public init(flashingAllowed: Bool = true) {
        self.flashingAllowed = flashingAllowed
    }

    public var body: some View {
        if reduceMotion || !flashingAllowed {
            Color.red
                .opacity(pulse ? 1 : 0.8)
                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: pulse)
                .onAppear { pulse = true }
        } else {
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let step = Int(context.date.timeIntervalSinceReferenceDate / 0.25)
                Color.red.opacity(step.isMultiple(of: 2) ? 1 : 0.45)
            }
        }
    }
}
