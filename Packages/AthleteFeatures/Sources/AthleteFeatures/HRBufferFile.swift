//
//  HRBufferFile.swift
//  AthleteFeatures
//
//  Crash safety for the session in progress: every good-signal reading is
//  appended to a per-session file the moment it arrives, so an app kill loses
//  nothing. The file is deleted only after the workout is safely in
//  HealthKit. Left in Application Support (backed up) on purpose.
//

#if os(iOS)
import Foundation

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

    /// One line per reading: seconds since 1970, bpm.
    func append(date: Date, bpm: Int) {
        if handle == nil {
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            handle = try? FileHandle(forWritingTo: url)
            _ = try? handle?.seekToEnd()
        }
        let line = "\(date.timeIntervalSince1970),\(bpm)\n"
        do {
            try handle?.write(contentsOf: Data(line.utf8))
        } catch {
            print("HRBufferFile: append failed: \(error)")
        }
    }

    /// Current size on disk; 0 once deleted.
    var byteCount: Int {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int) ?? 0
    }

    func read() -> [(date: Date, bpm: Int)] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: ",")
            guard parts.count == 2, let seconds = Double(parts[0]), let bpm = Int(parts[1]) else { return nil }
            return (Date(timeIntervalSince1970: seconds), bpm)
        }
    }

    func delete() {
        try? handle?.close()
        handle = nil
        try? FileManager.default.removeItem(at: url)
    }
}
#endif
