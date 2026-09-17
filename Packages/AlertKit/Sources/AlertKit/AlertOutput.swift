//
//  AlertOutput.swift
//  AlertKit
//
//  Audible + haptic side of a timeout. Tones come from WorkoutAudioKit, whose
//  `.playback` session plays with the silent switch on (REQ-ALERT-2).
//

import Foundation

@MainActor
public protocol AlertOutput: AnyObject {
    func startAlarm()
    func stopAlarm()
    func playResetChime()
    /// A short burst of the alarm so athletes can check volume before sparring.
    func testAlarm()
}

#if os(iOS)
import UIKit
import WorkoutAudioKit

@MainActor
public final class SystemAlertOutput: AlertOutput {
    private let audio: AudioCueService
    private let haptics = UINotificationFeedbackGenerator()
    private var loop: Timer?
    private var beat = 0

    public init(audio: AudioCueService = AudioCueService()) {
        self.audio = audio
    }

    public func startAlarm() {
        guard loop == nil else { return }
        beat = 0
        haptics.prepare()
        fireBeat()
        loop = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.fireBeat() }
        }
    }

    public func stopAlarm() {
        loop?.invalidate()
        loop = nil
    }

    public func playResetChime() {
        audio.play(.roundEnd)
        haptics.notificationOccurred(.success)
    }

    public func testAlarm() {
        startAlarm()
        Timer.scheduledTimer(withTimeInterval: 1.6, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopAlarm() }
        }
    }

    private func fireBeat() {
        audio.play(beat.isMultiple(of: 2) ? .terminal : .countdownBeep)
        haptics.notificationOccurred(.error)
        beat += 1
    }
}
#endif
