//
//  HRBufferFile.swift
//  AthleteFeatures
//
//  Crash safety for the session in progress: every reading is appended to a
//  per-session file the moment it arrives, so an app kill loses nothing.
//  No-contact readings are kept too, flagged (see `BufferedReading`), so a
//  slipped strap doesn't cut the session short. The file is deleted only
//  after the workout is safely in HealthKit. Left in Application Support
//  (backed up) on purpose.
//

#if os(iOS)
import Foundation
import SessionEngine

final class HRBufferFile {
    let url: URL
    private var handle: FileHandle?

    init(sessionID: UUID) {
        let dir = URL.applicationSupportDirectory.appending(path: "TrainingBuffers", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appending(path: "\(sessionID.uuidString).csv")
    }

    deinit {
        try? handle?.close()
    }

    /// One line per reading, in `BufferedReading`'s format.
    func append(_ reading: BufferedReading) {
        if handle == nil {
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            handle = try? FileHandle(forWritingTo: url)
            _ = try? handle?.seekToEnd()
        }
        do {
            try handle?.write(contentsOf: Data(reading.line.utf8))
        } catch {
            print("HRBufferFile: append failed: \(error)")
        }
    }

    /// Current size on disk; 0 once deleted.
    var byteCount: Int {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int) ?? 0
    }

    func read() -> [BufferedReading] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return BufferedReading.parse(text)
    }

    /// Replaces the file's contents, e.g. with a saved session's readings
    /// read back from Health before it is saved again.
    func write(_ readings: [BufferedReading]) throws {
        try? handle?.close()
        handle = nil
        let text = readings.map(\.line).joined()
        try Data(text.utf8).write(to: url, options: .atomic)
    }

    func delete() {
        try? handle?.close()
        handle = nil
        try? FileManager.default.removeItem(at: url)
    }
}
#endif
