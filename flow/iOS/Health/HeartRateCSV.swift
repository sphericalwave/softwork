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

    var filename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "flow-hr-\(formatter.string(from: start)).csv"
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
