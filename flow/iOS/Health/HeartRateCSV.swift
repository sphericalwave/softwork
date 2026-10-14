//
//  HeartRateCSV.swift
//  flow
//
//  A workout's heart rate as a shareable CSV file, fetched from Health only
//  when the share sheet asks for it. Feeds youtube-uploader's hr-overlay.swift.
//

import Foundation
import HealthKit
import CoreTransferable
import UniformTypeIdentifiers

nonisolated struct HeartRateCSV: Transferable {
    let store: HKHealthStore
    let start: Date
    let end: Date
    let hrMax: Int
    /// The title shown on the workout's card, e.g. "Wrestling".
    let workoutName: String

    /// e.g. "2026.10.13_Wrestling_FlowHr.csv"; spaces and slashes in the name become "-".
    var filename: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy.MM.dd"
        let name = workoutName
            .components(separatedBy: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "/\\")))
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return "\(formatter.string(from: start))_\(name.isEmpty ? "Workout" : name)_FlowHr.csv"
    }

    static var transferRepresentation: some TransferRepresentation {
        // A real named file: AirDrop ignores suggestedFileName on data exports.
        FileRepresentation(exportedContentType: .commaSeparatedText) { item in
            let data = try await WorkoutIntensityService.heartRateCSV(store: item.store, from: item.start,
                                                                      to: item.end, hrMax: item.hrMax)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(item.filename)
            try data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}
