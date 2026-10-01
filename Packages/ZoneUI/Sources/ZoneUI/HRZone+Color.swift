//
//  HRZone+Color.swift
//  ZoneUI
//
//  Zone colors live on the UI side; SessionEngine stays free of SwiftUI.
//

import SwiftUI
import SessionEngine

extension HRZone {
    public var color: Color {
        switch self {
        case .z0: return .gray
        case .z1: return .blue
        case .z2: return .green
        case .z3: return .yellow
        case .z4: return .orange
        case .z5: return .red
        }
    }
}
