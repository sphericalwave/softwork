//
//  DuplicateWorkoutViewModel.swift
//  flow
//
//  Duplicates a past workout onto a date it was trained but never recorded:
//  pick when and how long, preview the copied heart rate, then create the
//  Health workout plus a matching flow session (same kind and notes,
//  summary computed from the copy). Warns when the new time overlaps a
//  workout already in Health. Undo removes both.
//

import Foundation
import HealthKit
import Observation
import SwiftData
import Persistence
import SessionEngine

@MainActor
@Observable
final class DuplicateWorkoutViewModel {

    struct Source {
        let id: UUID
        let start: Date
        let duration: TimeInterval
        let title: String
        /// The session's kind, or the workout's tag; the new session's `kindRaw`.
        let kindRaw: String
        let notes: String
        let hrMax: Int
    }

    struct Preview {
        /// Copied readings, seconds from the new start.
        let points: [HRPoint]
        let kcal: Double?
        let summary: (average: Int, max: Int)?
    }

    /// Length limits for the copy, minutes.
    static let minuteRange = 5...600
    static let minuteStep = 5

    let source: Source
    private let service: WorkoutDuplicateService
    private let heartRate: HeartRateCopyService
    private let titleFor: @MainActor (UUID, HKWorkoutActivityType) -> String

    var start: Date
    var minutes: Int
    private(set) var isLoading = true
    private(set) var errorMessage: String?
    /// Workouts already in Health at the chosen time.
    private(set) var overlaps: [(source: HeartRateCopySource, title: String)] = []
    /// Something was written to or removed from Health; the caller should reload.
    private(set) var didChange = false

    private var sourceWorkout: HKWorkout?
    private var readings: [HRPoint] = []

    init(source: Source, service: WorkoutDuplicateService, heartRate: HeartRateCopyService,
         titleFor: @escaping @MainActor (UUID, HKWorkoutActivityType) -> String) {
        self.source = source
        self.service = service
        self.heartRate = heartRate
        self.titleFor = titleFor
        let minutes = min(max(Int((source.duration / 60).rounded()), Self.minuteRange.lowerBound),
                          Self.minuteRange.upperBound)
        self.minutes = minutes
        start = WorkoutDuplicate.defaultStart(for: source.start, duration: TimeInterval(minutes * 60))
    }

    var duration: TimeInterval { TimeInterval(minutes * 60) }
    var end: Date { start.addingTimeInterval(duration) }
    /// The copy must have finished by now.
    var latestStart: Date { Date().addingTimeInterval(-duration) }
    var canCreate: Bool { sourceWorkout != nil && end <= Date() }

    var preview: Preview? {
        guard let sourceWorkout else { return nil }
        let points = HeartRateCopy.scaled(readings, from: source.duration, to: duration)
        return Preview(points: points,
                       kcal: WorkoutDuplicate.scaledEnergy(service.activeKcal(of: sourceWorkout),
                                                           from: source.duration, to: duration),
                       summary: WorkoutDuplicate.bpmSummary(points))
    }

    // MARK: - Loading

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            guard let workout = try await service.workout(id: source.id) else {
                throw WorkoutDuplicateService.DuplicateError.sourceMissing
            }
            readings = try await heartRate.readings(start: source.start, duration: source.duration)
            sourceWorkout = workout
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Re-run whenever the time or length changes.
    func checkOverlaps() async {
        let found = (try? await service.workouts(overlapping: start, duration: duration)) ?? []
        overlaps = found.map { ($0, titleFor($0.id, $0.activityType)) }
    }

    // MARK: - Create and undo

    /// Writes the workout to Health, then records its flow session. If the
    /// session can't be saved the workout is removed again, so nothing is
    /// left half made.
    func create(context: ModelContext) async throws -> WorkoutDuplicateService.Created {
        guard let sourceWorkout, let preview else { throw WorkoutDuplicateService.DuplicateError.sourceMissing }
        let sessionID = UUID()
        let created = try await service.create(from: sourceWorkout, points: preview.points, start: start,
                                               duration: duration, kcal: preview.kcal, sessionID: sessionID)
        didChange = true

        let record = TrainingSessionRecord(id: sessionID, startedAt: start, kindRaw: source.kindRaw, hrMax: source.hrMax)
        record.endedAt = end
        record.healthKitWorkoutID = created.workoutID
        record.notes = source.notes
        // Only what made it into Health.
        if created.readings > 0 {
            record.averageBPM = preview.summary?.average
            record.maxBPM = preview.summary?.max
        }
        record.activeCalories = preview.kcal
        context.insert(record)
        do {
            try context.save()
        } catch {
            context.delete(record)
            try? await service.delete(workoutID: created.workoutID)
            throw error
        }
        return created
    }

    func undo(_ created: WorkoutDuplicateService.Created, context: ModelContext) async throws {
        try await Self.delete(workoutID: created.workoutID, service: service, context: context)
        didChange = true
    }

    /// Removes a duplicated workout from Health, then its flow session.
    static func delete(workoutID: UUID, service: WorkoutDuplicateService, context: ModelContext) async throws {
        try await service.delete(workoutID: workoutID)
        let id: UUID? = workoutID
        let sessions = try context.fetch(FetchDescriptor<TrainingSessionRecord>(
            predicate: #Predicate { $0.healthKitWorkoutID == id }
        ))
        sessions.forEach(context.delete)
        try context.save()
    }
}
