//
//  KeepAwake.swift
//  AlertKit
//
//  Screen stays on from lobby until the summary is dismissed (REQ-AWAKE-1).
//  isIdleTimerDisabled is per-process, so a relaunch after a crash
//  mid-session starts with the idle timer back on.
//

#if os(iOS)
import UIKit

@MainActor
public enum KeepAwake {
    public static func set(_ on: Bool) {
        UIApplication.shared.isIdleTimerDisabled = on
    }
}
#endif
