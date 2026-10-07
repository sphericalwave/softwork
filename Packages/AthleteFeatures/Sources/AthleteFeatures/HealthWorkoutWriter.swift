//
//  HealthWorkoutWriter.swift
//  AthleteFeatures
//
//  HealthKit is the long-term home of a training session: the workout,
//  every heart-rate reading, and the estimated active energy. Also reads the
//  calorie profile (sex, weight, age), with Settings values taking priority.
//

#if os(iOS)
import Foundation
import HealthKit
import SessionEngine

/// UserDefaults keys shared with the app's Settings screen.
public enum CalorieSettingsKeys {
    /// Body weight in kg; 0 means "use Health".
    public static let weightKg = "calorieWeightKg"
    /// `CalorieProfile.Sex.rawValue`; empty means "use Health".
    public static let sex = "calorieSex"
}

/// Everything training sessions write to and read from Health. The app asks
/// for these together with its dashboard types in one request, so the user
/// sees a single Health sheet instead of a second one at Start Training.
public enum TrainingHealthTypes {
    public static var share: Set<HKSampleType> {
        [HKObjectType.workoutType(), HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
    }

    public static var read: Set<HKObjectType> {
        [
            HKObjectType.workoutType(),
            HKQuantityType(.bodyMass),
            HKCharacteristicType(.biologicalSex),
            HKCharacteristicType(.dateOfBirth),
        ]
    }
}

@MainActor
final class HealthWorkoutWriter {
    private let store = HKHealthStore()
    private let heartRate = HKQuantityType(.heartRate)
    private let activeEnergy = HKQuantityType(.activeEnergyBurned)
    private let bpmUnit = HKUnit.count().unitDivided(by: .minute())

    enum WriteError: LocalizedError {
        case unavailable
        case noWorkout
        case workoutsNotAllowed

        var errorDescription: String? {
            switch self {
            case .unavailable: return "Health isn't available on this device."
            case .noWorkout: return "Health didn't return the saved workout."
            case .workoutsNotAllowed: return "flow isn't allowed to save workouts to Health."
            }
        }
    }

    /// A no-op once the app's launch request (which includes these types) is answered.
    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        do {
            try await store.requestAuthorization(toShare: TrainingHealthTypes.share, read: TrainingHealthTypes.read)
        } catch {
            print("HealthWorkoutWriter: authorization request failed: \(error)")
        }
    }

    /// Settings values first, then Health; nil if sex, weight or age is unknown.
    func calorieProfile() async -> CalorieProfile? {
        let defaults = UserDefaults.standard
        let sex = CalorieProfile.Sex(rawValue: defaults.string(forKey: CalorieSettingsKeys.sex) ?? "")
            ?? healthSex()
        let storedWeight = defaults.double(forKey: CalorieSettingsKeys.weightKg)
        let weight = storedWeight > 0 ? storedWeight : await latestWeightKg()
        guard let sex, let weight, let age = healthAge() else { return nil }
        return CalorieProfile(sex: sex, weightKg: weight, age: age)
    }

    /// The workout flow already saved for this session, found by its sync
    /// identifier — covers an app kill between the save and recording it.
    func savedWorkoutID(sessionID: UUID) async -> UUID? {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier,
                                        allowedValues: [sessionID.uuidString]),
            HKQuery.predicateForObjects(from: HKSource.default()),
        ])
        let descriptor = HKSampleQueryDescriptor(predicates: [.workout(predicate)], sortDescriptors: [], limit: 1)
        return try? await descriptor.result(for: store).first?.uuid
    }

    /// Heart rate flow itself saved between `start` and `end`: a past
    /// session's readings, once its buffer file is gone.
    func heartRatePoints(from start: Date, to end: Date) async -> [HRPoint] {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate),
            HKQuery.predicateForObjects(from: HKSource.default()),
        ])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: heartRate, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples = (try? await descriptor.result(for: store)) ?? []
        return samples.map {
            HRPoint(t: $0.startDate.timeIntervalSince(start),
                    bpm: Int($0.quantity.doubleValue(for: bpmUnit).rounded()))
        }
    }

    /// Saves the session as a workout. The session id is the sync identifier,
    /// so a retry after a crash replaces rather than duplicates the workout.
    /// Heart rate or energy the user hasn't allowed is left out, rather than
    /// failing the whole workout on every retry.
    func save(_ summary: TrainingSummary, sessionID: UUID) async throws -> UUID {
        guard HKHealthStore.isHealthDataAvailable() else { throw WriteError.unavailable }
        guard store.authorizationStatus(for: .workoutType()) != .sharingDenied else {
            throw WriteError.workoutsNotAllowed
        }
        let config = HKWorkoutConfiguration()
        config.activityType = summary.kind.activityType
        config.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())

        let start = summary.startedAt
        let end = start.addingTimeInterval(summary.duration)
        func date(_ t: TimeInterval) -> Date { start.addingTimeInterval(t) }

        _ = try await builder.beginCollection(at: start)
        var samples: [HKSample] = summary.points.map { point in
            HKQuantitySample(type: heartRate,
                             quantity: HKQuantity(unit: bpmUnit, doubleValue: Double(point.bpm)),
                             start: date(point.t), end: date(point.t))
        }
        samples += summary.energy.map { interval in
            HKQuantitySample(type: activeEnergy,
                             quantity: HKQuantity(unit: .kilocalorie(), doubleValue: interval.kcal),
                             start: date(interval.start), end: date(interval.end))
        }
        samples.removeAll { store.authorizationStatus(for: $0.sampleType) != .sharingAuthorized }
        if !samples.isEmpty {
            _ = try await builder.addSamples(samples)
        }
        let segments = summary.rounds.map { round in
            HKWorkoutEvent(type: .segment,
                           dateInterval: DateInterval(start: date(round.start), end: date(round.end)),
                           metadata: nil)
        }
        if !segments.isEmpty {
            _ = try await builder.addWorkoutEvents(segments)
        }
        _ = try await builder.addMetadata([
            HKMetadataKeyIndoorWorkout: true,
            HKMetadataKeySyncIdentifier: sessionID.uuidString,
            HKMetadataKeySyncVersion: 1,
        ])
        _ = try await builder.endCollection(at: end)
        guard let workout = try await builder.finishWorkout() else { throw WriteError.noWorkout }
        return workout.uuid
    }

    // MARK: - Profile reads

    private func healthSex() -> CalorieProfile.Sex? {
        switch (try? store.biologicalSex())?.biologicalSex {
        case .some(.male): return .male
        case .some(.female): return .female
        default: return nil
        }
    }

    private func healthAge() -> Int? {
        guard let components = try? store.dateOfBirthComponents(),
              let birthDate = Calendar.current.date(from: components) else { return nil }
        return Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year
    }

    private func latestWeightKg() async -> Double? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.bodyMass))],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        let sample = try? await descriptor.result(for: store).first
        return sample?.quantity.doubleValue(for: .gramUnit(with: .kilo))
    }
}

extension WorkoutKind {
    var activityType: HKWorkoutActivityType {
        switch self {
        case .wrestling: return .wrestling
        case .kickboxing: return .kickboxing
        }
    }
}
#endif
