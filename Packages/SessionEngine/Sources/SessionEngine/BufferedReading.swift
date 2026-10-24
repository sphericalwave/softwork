//
//  BufferedReading.swift
//  SessionEngine
//
//  One line of a session's crash-safety buffer file. Readings taken while
//  the strap had no skin contact are kept, flagged, so a slipped strap
//  doesn't shorten the session; they never count as heart rate.
//
//  Line format: `<seconds since 1970>,<bpm>` for a good reading, with a
//  third `nc` field for a no-contact one. Builds that predate the flag skip
//  the three-field lines rather than misread them.
//

import Foundation

public struct BufferedReading: Sendable, Equatable {
    public let date: Date
    public let bpm: Int
    /// False when the strap reported no skin contact: the bpm isn't real.
    public let hasContact: Bool

    public init(date: Date, bpm: Int, hasContact: Bool = true) {
        self.date = date
        self.bpm = bpm
        self.hasContact = hasContact
    }

    private static let noContactField = "nc"

    /// The line, with its trailing newline.
    public var line: String {
        let base = "\(date.timeIntervalSince1970),\(bpm)"
        return (hasContact ? base : base + "," + Self.noContactField) + "\n"
    }

    /// nil for a malformed or unrecognized line.
    public init?(line: Substring) {
        let parts = line.split(separator: ",")
        guard parts.count == 2 || (parts.count == 3 && parts[2] == Self.noContactField),
              let seconds = Double(parts[0]), let bpm = Int(parts[1]) else { return nil }
        self.init(date: Date(timeIntervalSince1970: seconds), bpm: bpm, hasContact: parts.count == 2)
    }

    public static func parse(_ text: String) -> [BufferedReading] {
        text.split(separator: "\n").compactMap { BufferedReading(line: $0) }
    }

    /// Heart rate for stats, charts and Health: no-contact readings left out.
    public static func points(_ readings: [BufferedReading], since start: Date) -> [HRPoint] {
        readings.filter(\.hasContact).map { HRPoint(t: $0.date.timeIntervalSince(start), bpm: $0.bpm) }
    }

    /// When the strap was last heard from, contact or not.
    public static func lastDate(_ readings: [BufferedReading]) -> Date? {
        readings.map(\.date).max()
    }
}
