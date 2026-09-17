//
//  MaxHeartRate.swift
//  SessionEngine
//
//  Max-HR estimation. Tanaka is the spec default (§5.1); 220 − age is kept
//  as the traditional alternative for athletes who prefer it.
//

import Foundation

public enum MaxHRFormula: String, Sendable, Codable, CaseIterable, Identifiable {
    case tanaka
    case traditional

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .tanaka: return "Tanaka (208 − 0.7 × age)"
        case .traditional: return "220 − age"
        }
    }

    public func estimate(age: Int) -> Int {
        switch self {
        case .tanaka: return Int((208 - 0.7 * Double(age)).rounded())
        case .traditional: return 220 - age
        }
    }
}

public enum MaxHeartRate {
    public static let fallback = 190

    /// Resolves the max HR to use: an explicit override wins, otherwise the
    /// chosen formula applied to age, otherwise `fallback`.
    public static func effective(override: Int, age: Int?, formula: MaxHRFormula = .tanaka) -> Int {
        if override > 0 { return override }
        if let age, age > 0, age < 120 { return formula.estimate(age: age) }
        return fallback
    }
}
