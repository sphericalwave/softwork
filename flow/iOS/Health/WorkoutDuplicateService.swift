//
//  WorkoutDuplicateService.swift
//  flow
//
//  Recreates a session that was trained but never recorded by duplicating a
//  similar past workout onto another date, and removes such a duplicate.
//  The copy is a flow-owned Health workout with the source's activity type,
//  its heart rate stretched to the new length (marked estimated exactly like
//  a heart-rate copy, so Intensity labels it) and its active energy scaled
//  by length. One batch id on the workout and every sample lets the whole
//  duplicate be deleted exactly.
//

import Foundation
import HealthKit
import SessionEngine

@MainActor
final class WorkoutDuplicateService {

    /// Metadata on a duplicated workout and its energy: the source workout's UUID string.
    nonisolated static let duplicatedFromKey = "FlowDuplicatedFromWorkout"

    enum DuplicateError: LocalizedError {
        case workoutsNotAllowed
        case sourceMissing
        case noWorkout

        var errorDescription: String? {
            switch self {
            case .workoutsNotAllowed:
                return "flow isn't allowed to save workouts to Health. Turn it on in Settings › Health › Data Access & Devices › flow."
            case .sourceMissing:
                return "That workout is no longer in Health."
            case .noWorkout:
                return "Health didn't return the new workout."
            }
        }
    }

    /// The new workout, enough to undo it.
    struct Created: Sendable {
        let workoutID: UUID
        let batch: UUID
        let readings: Int
    }

    private let store: HKHealthStore
    private let heartRate = HKQuantityType(.heartRate)
    private let activeEnergy = HKQuantityType(.activeEnergyBurned)
    private let bpmUnit = HKUnit.count().unitDivided(by: .minute())

    init(store: HKHealthStore) {
        self.store = store
    }

    // MARK: - Reads

    func workout(id: UUID) async throws -> HKWorkout? {
        let descriptor = HKSampleQueryDescriptor(predicates: [.workout(HKQuery.predicateForObject(with: id))],
                                                 sortDescriptors: [], limit: 1)
        return try await descriptor.result(for: store).first
    }

    /// Active energy recorded during the workout, kcal; nil if none.
    func activeKcal(of workout: HKWorkout) -> Double? {
        workout.statistics(for: activeEnergy)?.sumQuantity()?.doubleValue(for: .kilocalorie())
    }

    /// Workouts sharing any time with `start..<start+duration`, earliest first.
    func workouts(overlapping start: Date, duration: TimeInterval) async throws -> [HeartRateCopySource] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: start.addingTimeInterval(duration))
        let descriptor = HKSampleQueryDescriptor(predicates: [.workout(predicate)],
                                                 sortDescriptors: [SortDescriptor(\.startDate)])
        let found = try await descriptor.result(for: store).withoutBioMechanicShadows()
        let overlapping = WorkoutDuplicate.overlapping(start: start, duration: duration,
                                                       existing: found.map { DateInterval(start: $0.startDate, end: $0.endDate) })
        return overlapping.map { found[$0] }.map {
            HeartRateCopySource(id: $0.uuid, start: $0.startDate, duration: $0.duration,
                                activityTypeRaw: $0.workoutActivityType.rawValue)
        }
    }

    // MARK: - Create

    /// Saves a copy of `source` at `start`. `points` are seconds from the
    /// new start, already fitted to `duration`. `sessionID` is the sync
    /// identifier, as for workouts flow records, so a later type change on
    /// the session finds this workout.
    func create(from source: HKWorkout, points: [HRPoint], start: Date, duration: TimeInterval,
                kcal: Double?, sessionID: UUID) async throws -> Created {
        guard store.authorizationStatus(for: .workoutType()) == .sharingAuthorized else {
            throw DuplicateError.workoutsNotAllowed
        }
        let batch = UUID()
        let end = start.addingTimeInterval(duration)
        let config = HKWorkoutConfiguration()
        config.activityType = source.workoutActivityType
        if let indoor = source.metadata?[HKMetadataKeyIndoorWorkout] as? Bool {
            config.locationType = indoor ? .indoor : .outdoor
        }
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())

        let heartRateMetadata: [String: Any] = [
            HeartRateCopyService.estimatedKey: true,
            HeartRateCopyService.sourceKey: source.uuid.uuidString,
            HeartRateCopyService.batchKey: batch.uuidString,
            HKMetadataKeyWasUserEntered: true,
        ]
        var samples: [HKSample] = points.map { point in
            let date = start.addingTimeInterval(point.t)
            return HKQuantitySample(type: heartRate, quantity: HKQuantity(unit: bpmUnit, doubleValue: Double(point.bpm)),
                                    start: date, end: date, metadata: heartRateMetadata)
        }
        if let kcal {
            samples.append(HKQuantitySample(type: activeEnergy, quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
                                            start: start, end: end,
                                            metadata: [Self.duplicatedFromKey: source.uuid.uuidString,
                                                       HeartRateCopyService.batchKey: batch.uuidString,
                                                       HKMetadataKeyWasUserEntered: true]))
        }
        samples.removeAll { store.authorizationStatus(for: $0.sampleType) != .sharingAuthorized }

        var metadata: [String: Any] = [
            HKMetadataKeyWasUserEntered: true,
            HKMetadataKeySyncIdentifier: sessionID.uuidString,
            HKMetadataKeySyncVersion: 1,
            Self.duplicatedFromKey: source.uuid.uuidString,
            HeartRateCopyService.batchKey: batch.uuidString,
        ]
        if let indoor = source.metadata?[HKMetadataKeyIndoorWorkout] {
            metadata[HKMetadataKeyIndoorWorkout] = indoor
        }
        if let brand = source.metadata?[HKMetadataKeyWorkoutBrandName] {
            metadata[HKMetadataKeyWorkoutBrandName] = brand
        }

        do {
            _ = try await builder.beginCollection(at: start)
            if !samples.isEmpty {
                _ = try await builder.addSamples(samples)
            }
            _ = try await builder.addMetadata(metadata)
            _ = try await builder.endCollection(at: end)
            guard let workout = try await builder.finishWorkout() else { throw DuplicateError.noWorkout }
            let readings = samples.filter { $0.sampleType.identifier == heartRate.identifier }.count
            return Created(workoutID: workout.uuid, batch: batch, readings: readings)
        } catch {
            // Samples the builder already saved go too, so a failure leaves Health as it was.
            builder.discardWorkout()
            try? await deleteSamples(batch: batch)
            throw error
        }
    }

    // MARK: - Delete

    /// Removes a duplicate: the workout and every sample saved with it.
    /// Only flow's own duplicates; anything else is left alone.
    func delete(workoutID: UUID) async throws {
        let ours = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForObject(with: workoutID),
            HKQuery.predicateForObjects(from: HKSource.default()),
        ])
        let descriptor = HKSampleQueryDescriptor(predicates: [.workout(ours)], sortDescriptors: [], limit: 1)
        guard let workout = try await descriptor.result(for: store).first,
              workout.metadata?[Self.duplicatedFromKey] != nil else { return }
        if let batch = (workout.metadata?[HeartRateCopyService.batchKey] as? String).flatMap(UUID.init(uuidString:)) {
            try await deleteSamples(batch: batch)
        }
        try await store.delete(workout)
    }

    private func deleteSamples(batch: UUID) async throws {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForObjects(withMetadataKey: HeartRateCopyService.batchKey, allowedValues: [batch.uuidString]),
            HKQuery.predicateForObjects(from: HKSource.default()),
        ])
        for type in [heartRate, activeEnergy] where store.authorizationStatus(for: type) == .sharingAuthorized {
            _ = try await store.deleteObjects(of: type, predicate: predicate)
        }
    }
}
