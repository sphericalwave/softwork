//
//  NumberInput.swift
//  SessionEngine
//
//  Lenient parsing for number-pad settings fields: either decimal
//  separator, stray spaces. nil for empty, zero or garbage, which the
//  caller treats as "keep the stored value".
//

import Foundation

public enum NumberInput {
    public static func wholeNumber(_ text: String) -> Int? {
        decimal(text).map { Int($0.rounded()) }.flatMap { $0 > 0 ? $0 : nil }
    }

    public static func decimal(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value > 0, value.isFinite else { return nil }
        return value
    }
}
