//
//  HeartRateCopyService.swift
//  flow
//
//  Copies a similar past workout's heart rate onto a workout whose strap
//  failed, and undoes it. Everything lives in Health — no app schema change:
//  copied readings are flow-owned samples marked estimated in their metadata
//  (plus Health's own "user entered" flag), and each copy gets a batch id so
//  it can be removed exactly. flow readings a copy replaces are backed up to
//  a small JSON file first and written back on undo. Other apps' readings
//  (e.g. a Watch) can't be deleted by flow, so they're always kept.
//

import Foundation
import HealthKit
import SessionEngine

/// A past workout that could lend its heart rate.
nonisolated struct HeartRateCopySource: Identifiable, Sendable {
    let id: UUID
    let start: Date
    let duration: TimeInterval
    let activityTypeRaw: UInt

    var activityType: HKWorkoutActivityType { HKWorkoutActivityType(rawValue: activityTypeRaw) ?? .other }
}

/// What the target workout already has in Health.
nonisolated struct TargetHeartRate: Sendable {
    /// Real readings flow recorded (deletable by flow), seconds from the target's start.
    var own: [HRPoint] = []
    /// Real readings from other apps; never deleted.
    var foreign: [HRPoint] = []
    /// Readings an earlier copy wrote.
    var estimatedCount = 0

    var real: [HRPoint] { (own + foreign).sorted { $0.t < $1.t } }
}

@MainActor
final class HeartRateCopyService {

    /// Metadata on copied samples. Bool: the reading is an estimate.
    nonisolated static let estimatedKey = "FlowEstimatedHeartRate"
    /// Metadata on copied samples: the source workout's UUID string.
    nonisolated static let sourceKey = "FlowCopiedFromWorkout"
    /// Metadata on copied samples: the copy's batch UUID string, for undo.
    nonisolated static let batchKey = "FlowCopyBatch"

    /// How far back to look for sources.
    static let lookbackDays = 365

    enum CopyError: LocalizedError {
        case notAllowed
        case nothingToCopy

        var errorDescription: String? {
            switch self {
            case .notAllowed:
                return "flow isn't allowed to save heart rate to Health. Turn it on in Settings › Health › Data Access & Devices › flow."
            case .nothingToCopy:
                return "That workout has no heart rate to copy."
            }
        }
    }

    /// The result of a copy, enough to undo it.
    struct Applied: Sendable {
        let batch: UUID
        let written: Int
        let replaced: Int
    }

    private let store: HKHealthStore
    private let heartRate = HKQuantityType(.heartRate)
    private let bpmUnit = HKUnit.count().unitDivided(by: .minute())

    init(store: HKHealthStore) {
        self.store = store
    }

    // MARK: - Reads

    /// Workouts from the last year other than `excluding`, newest first.
    func sources(excluding targetID: UUID) async throws -> [HeartRateCopySource] {
        let since = Calendar.current.date(byAdding: .day, value: -Self.lookbackDays, to: Date()) ?? .distantPast
        let predicate = HKQuery.predicateForSamples(withStart: since, end: Date())
        let descriptor = HKSampleQueryDescriptor(predicates: [.workout(predicate)],
                                                 sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)])
        return try await descriptor.result(for: store)
            .filter { $0.uuid != targetID && $0.duration > 0 }
            .map { HeartRateCopySource(id: $0.uuid, start: $0.startDate, duration: $0.duration,
                                       activityTypeRaw: $0.workoutActivityType.rawValue) }
    }

    /// Average bpm over a workout, or nil if it has no heart rate.
    func averageBPM(start: Date, duration: TimeInterval) async -> Int? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: start.addingTimeInterval(duration),
                                                    options: .strictStartDate)
        let descriptor = HKStatisticsQueryDescriptor(predicate: .quantitySample(type: heartRate, predicate: predicate),
                                                     options: .discreteAverage)
        guard let average = try? await descriptor.result(for: store)?.averageQuantity() else { return nil }
        return Int(average.doubleValue(for: bpmUnit).rounded())
    }

    /// Every reading in the workout's window, seconds from its start.
    func readings(start: Date, duration: TimeInterval) async throws -> [HRPoint] {
        try await samples(start: start, duration: duration).map(point(relativeTo: start))
    }

    func targetHeartRate(start: Date, duration: TimeInterval) async throws -> TargetHeartRate {
        var target = TargetHeartRate()
        let ownBundle = HKSource.default().bundleIdentifier
        for sample in try await samples(start: start, duration: duration) {
            if sample.metadata?[Self.estimatedKey] != nil {
                target.estimatedCount += 1
            } else if sample.sourceRevision.source.bundleIdentifier == ownBundle {
                target.own.append(point(relativeTo: start)(sample))
            } else {
                target.foreign.append(point(relativeTo: start)(sample))
            }
        }
        return target
    }

    // MARK: - Copy

    /// Writes `points` (seconds from `targetStart`) as estimated readings.
    /// With `replacingOwn`, flow's own real readings in the window are
    /// backed up, then deleted once the copy is safely saved.
    func copy(_ points: [HRPoint], targetID: UUID, targetStart: Date, targetDuration: TimeInterval,
              sourceID: UUID, replacingOwn: Bool) async throws -> Applied {
        guard !points.isEmpty else { throw CopyError.nothingToCopy }
        guard store.authorizationStatus(for: heartRate) == .sharingAuthorized else { throw CopyError.notAllowed }

        let batch = UUID()
        let toReplace = replacingOwn
            ? try await ownRealSamples(start: targetStart, duration: targetDuration)
            : []
        // Backup first: if anything below fails, undo can still put them back.
        let backup = HeartRateCopyBackup(batch: batch, targetWorkoutID: targetID, sourceWorkoutID: sourceID,
                                         replaced: toReplace.map {
                                             .init(date: $0.startDate, endDate: $0.endDate,
                                                   bpm: $0.quantity.doubleValue(for: bpmUnit))
                                         })
        try backup.write()

        let metadata: [String: Any] = [
            Self.estimatedKey: true,
            Self.sourceKey: sourceID.uuidString,
            Self.batchKey: batch.uuidString,
            HKMetadataKeyWasUserEntered: true,
        ]
        let samples = points.map { point in
            let date = targetStart.addingTimeInterval(point.t)
            return HKQuantitySample(type: heartRate,
                                    quantity: HKQuantity(unit: bpmUnit, doubleValue: Double(point.bpm)),
                                    start: date, end: date, metadata: metadata)
        }
        do {
            try await store.save(samples)
        } catch {
            backup.remove()
            throw error
        }
        if !toReplace.isEmpty {
            do {
                try await store.delete(toReplace)
            } catch {
                // Leave Health as it was rather than half replaced.
                try? await undo(batch: batch)
                throw error
            }
        }
        return Applied(batch: batch, written: samples.count, replaced: toReplace.count)
    }

    // MARK: - Undo

    /// Removes the copy and writes back the readings it replaced.
    func undo(batch: UUID) async throws {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForObjects(withMetadataKey: Self.batchKey, allowedValues: [batch.uuidString]),
            HKQuery.predicateForObjects(from: HKSource.default()),
        ])
        try await deleteHeartRate(matching: predicate)
        guard let backup = HeartRateCopyBackup.read(batch: batch) else { return }
        // Only readings no longer in Health: a replace that failed part way may have left some.
        var restored: [HKQuantitySample] = []
        if let first = backup.replaced.map(\.date).min(), let last = backup.replaced.map(\.endDate).max() {
            let stillThere = Set(try await ownRealSamples(start: first, end: last.addingTimeInterval(1))
                .map(\.startDate))
            restored = backup.replaced
                .filter { !stillThere.contains($0.date) }
                .map { HKQuantitySample(type: heartRate, quantity: HKQuantity(unit: bpmUnit, doubleValue: $0.bpm),
                                        start: $0.date, end: $0.endDate) }
        }
        if !restored.isEmpty {
            try await store.save(restored)
        }
        backup.remove()
    }

    /// Undoes every copy that wrote into the workout's window.
    func removeCopies(start: Date, duration: TimeInterval) async throws {
        let batches = Set(try await samples(start: start, duration: duration).compactMap {
            ($0.metadata?[Self.batchKey] as? String).flatMap(UUID.init(uuidString:))
        })
        for batch in batches {
            try await undo(batch: batch)
        }
    }

    // MARK: - Internals

    private func samples(start: Date, duration: TimeInterval) async throws -> [HKQuantitySample] {
        try await samples(predicate: HKQuery.predicateForSamples(withStart: start, end: start.addingTimeInterval(duration),
                                                                 options: .strictStartDate))
    }

    private func samples(predicate: NSPredicate) async throws -> [HKQuantitySample] {
        let descriptor = HKSampleQueryDescriptor(predicates: [.quantitySample(type: heartRate, predicate: predicate)],
                                                 sortDescriptors: [SortDescriptor(\.startDate)])
        return try await descriptor.result(for: store)
    }

    private func ownRealSamples(start: Date, duration: TimeInterval) async throws -> [HKQuantitySample] {
        try await ownRealSamples(start: start, end: start.addingTimeInterval(duration))
    }

    private func ownRealSamples(start: Date, end: Date) async throws -> [HKQuantitySample] {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate]),
            HKQuery.predicateForObjects(from: HKSource.default()),
        ])
        return try await samples(predicate: predicate).filter { $0.metadata?[Self.estimatedKey] == nil }
    }

    private func deleteHeartRate(matching predicate: NSPredicate) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            store.deleteObjects(of: heartRate, predicate: predicate) { _, _, error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }
    }

    private func point(relativeTo start: Date) -> (HKQuantitySample) -> HRPoint {
        { [bpmUnit] in
            HRPoint(t: $0.startDate.timeIntervalSince(start),
                    bpm: Int($0.quantity.doubleValue(for: bpmUnit).rounded()))
        }
    }
}

/// flow readings a copy replaced, kept on this phone until the copy is undone
/// (Application Support/HeartRateCopies/<batch>.json).
struct HeartRateCopyBackup: Codable {
    struct Reading: Codable {
        let date: Date
        let endDate: Date
        let bpm: Double
    }

    let batch: UUID
    let targetWorkoutID: UUID
    let sourceWorkoutID: UUID
    let replaced: [Reading]

    private static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "HeartRateCopies", directoryHint: .isDirectory)
    }

    private static func url(_ batch: UUID) -> URL {
        directory.appending(path: "\(batch.uuidString).json")
    }

    static func read(batch: UUID) -> HeartRateCopyBackup? {
        guard let data = try? Data(contentsOf: url(batch)) else { return nil }
        return try? JSONDecoder().decode(HeartRateCopyBackup.self, from: data)
    }

    func write() throws {
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: Self.url(batch), options: .atomic)
    }

    func remove() {
        try? FileManager.default.removeItem(at: Self.url(batch))
    }
}
