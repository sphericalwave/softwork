//
//  HeartRateCSV.swift
//  flow
//
//  A workout's heart rate as a shareable CSV file, fetched from Health only
//  when the share sheet asks for it. Feeds Tools/hr-overlay.
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

    var filename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "flow-hr-\(formatter.string(from: start)).csv"
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { item in
            try await WorkoutIntensityService.heartRateCSV(store: item.store, from: item.start,
                                                           to: item.end, hrMax: item.hrMax)
        }
        .suggestedFileName { $0.filename }
    }
}
