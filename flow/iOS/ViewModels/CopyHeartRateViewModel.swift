//
//  CopyHeartRateViewModel.swift
//  flow
//
//  Picks a past workout to lend its heart rate to one whose strap failed:
//  similar workouts (same kind, comparable length) are suggested first, the
//  rest are searchable, and each is previewed stretched onto the target
//  before anything is written to Health.
//

import Foundation
import HealthKit
import Observation
import SessionEngine

@MainActor
@Observable
final class CopyHeartRateViewModel {

    struct Target {
        let id: UUID
        let start: Date
        let duration: TimeInterval
        let title: String
    }

    struct Candidate: Identifiable {
        let source: HeartRateCopySource
        let title: String
        let isSimilar: Bool
        let score: Double

        var id: UUID { source.id }
    }

    /// What happens to readings the target did record.
    enum Mode: Hashable {
        /// Keep every recorded reading; copy only into the gaps.
        case fillGaps
        /// Swap flow's own recorded readings for the copy. Other apps' readings stay.
        case replace
    }

    struct Preview {
        /// Estimated readings that would be written, seconds from the target's start.
        let copied: [HRPoint]
        /// Real readings that stay.
        let recorded: [HRPoint]
        /// Target length ÷ source length: >1 means the source is stretched.
        let stretch: Double
        /// flow readings that would be deleted (backed up for undo).
        let replacedCount: Int
    }

    /// How many similar workouts to suggest.
    private static let suggestionCount = 5

    let target: Target
    private let service: HeartRateCopyService
    private let titleFor: @MainActor (UUID, HKWorkoutActivityType) -> String

    private(set) var candidates: [Candidate] = []
    private(set) var targetHR: TargetHeartRate?
    private(set) var isLoading = true
    private(set) var errorMessage: String?
    /// Average bpm per candidate once loaded; nil value means it has no heart rate.
    private(set) var averages: [UUID: Int?] = [:]
    /// Something was written to or removed from Health; the caller should reload.
    private(set) var didChange = false
    var searchText = ""

    private var sourceReadings: [UUID: [HRPoint]] = [:]

    init(target: Target, service: HeartRateCopyService,
         titleFor: @escaping @MainActor (UUID, HKWorkoutActivityType) -> String) {
        self.target = target
        self.service = service
        self.titleFor = titleFor
    }

    // MARK: - Lists

    /// Similar workouts known to have heart rate, best first.
    var suggested: [Candidate] {
        guard searchText.isEmpty else { return [] }
        return Array(candidates.filter { $0.isSimilar && hasHeartRate($0) != false }.prefix(Self.suggestionCount))
    }

    /// Everything not suggested, best match first; filtered by the search text.
    var others: [Candidate] {
        let suggestedIDs = Set(suggested.map(\.id))
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return candidates.filter { candidate in
            !suggestedIDs.contains(candidate.id) && (query.isEmpty || Self.matches(candidate, query))
        }
    }

    /// nil until its average has loaded.
    func hasHeartRate(_ candidate: Candidate) -> Bool? {
        averages[candidate.id].map { $0 != nil }
    }

    private static func matches(_ candidate: Candidate, _ query: String) -> Bool {
        let start = candidate.source.start
        let haystack = [candidate.title,
                        start.formatted(date: .abbreviated, time: .omitted),
                        start.formatted(.dateTime.weekday(.wide)),
                        start.formatted(.dateTime.month(.wide))]
        return haystack.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    // MARK: - Loading

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            targetHR = try await service.targetHeartRate(start: target.start, duration: target.duration)
            let sources = try await service.sources(excluding: target.id)
            candidates = sources.map { source in
                let title = titleFor(source.id, source.activityType)
                let sameKind = title == target.title
                let days = source.start.timeIntervalSince(target.start) / 86_400
                return Candidate(source: source, title: title,
                                 isSimilar: HeartRateCopy.isSimilar(sameKind: sameKind, sourceDuration: source.duration,
                                                                    targetDuration: target.duration),
                                 score: HeartRateCopy.score(sameKind: sameKind, sourceDuration: source.duration,
                                                            targetDuration: target.duration, daysApart: days))
            }
            .sorted { $0.score < $1.score }
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        // Check the likely suggestions up front so ones without heart rate drop out.
        for candidate in candidates.filter(\.isSimilar).prefix(Self.suggestionCount * 3) {
            await loadAverage(candidate)
        }
    }

    func loadAverage(_ candidate: Candidate) async {
        guard averages[candidate.id] == nil else { return }
        averages[candidate.id] = .some(await service.averageBPM(start: candidate.source.start,
                                                                duration: candidate.source.duration))
    }

    // MARK: - Preview and copy

    func preview(_ candidate: Candidate, mode: Mode) async throws -> Preview {
        let readings: [HRPoint]
        if let cached = sourceReadings[candidate.id] {
            readings = cached
        } else {
            readings = try await service.readings(start: candidate.source.start, duration: candidate.source.duration)
            sourceReadings[candidate.id] = readings
        }
        let targetHR = targetHR ?? TargetHeartRate()
        let recorded = mode == .replace ? targetHR.foreign : targetHR.real
        let scaled = HeartRateCopy.scaled(readings, from: candidate.source.duration, to: target.duration)
        return Preview(copied: HeartRateCopy.fillingGaps(scaled, around: recorded.map(\.t)),
                       recorded: recorded.sorted { $0.t < $1.t },
                       stretch: target.duration / candidate.source.duration,
                       replacedCount: mode == .replace ? targetHR.own.count : 0)
    }

    func copy(_ preview: Preview, from candidate: Candidate) async throws -> HeartRateCopyService.Applied {
        let applied = try await service.copy(preview.copied, targetID: target.id, targetStart: target.start,
                                             targetDuration: target.duration, sourceID: candidate.id,
                                             replacingOwn: preview.replacedCount > 0)
        didChange = true
        return applied
    }

    func undo(_ applied: HeartRateCopyService.Applied) async throws {
        try await service.undo(batch: applied.batch)
        didChange = true
    }

    /// Removes an earlier copy so the workout can take a new one.
    func removeEarlierCopies() async {
        var failure: String?
        do {
            try await service.removeCopies(start: target.start, duration: target.duration)
            didChange = true
        } catch {
            failure = error.localizedDescription
        }
        await load()
        errorMessage = failure ?? errorMessage
    }
}
