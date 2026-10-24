//
//  PendingSessionsBanner.swift
//  flow
//
//  Overview and Intensity list Health workouts only, so a session still
//  recording, or ended but not yet in Health, would otherwise look lost.
//  One row per such session; tapping it opens the session — Spar for one
//  still recording, its detail (with Save Now / Try Again) otherwise.
//

import SwiftUI
import SwiftData
import Persistence
import AthleteFeatures

struct PendingSessionsBanner: View {
    let openSpar: () -> Void

    @Query(filter: #Predicate<TrainingSessionRecord> { $0.healthKitWorkoutID == nil },
           sort: \TrainingSessionRecord.startedAt, order: .reverse)
    private var sessions: [TrainingSessionRecord]
    private let sync = HealthSessionSync.shared

    var body: some View {
        if !sessions.isEmpty {
            VStack(spacing: 8) {
                ForEach(sessions) { session in
                    row(session)
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ session: TrainingSessionRecord) -> some View {
        let status = sync.status(of: session)
        if status == .recording {
            Button(action: openSpar) {
                PendingSessionRow(title: title(session), status: status)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                TrainingSessionDetailView(record: session)
            } label: {
                PendingSessionRow(title: title(session), status: status)
            }
            .buttonStyle(.plain)
        }
    }

    /// "Jiu-Jitsu 13:02", with the day when it wasn't today.
    private func title(_ session: TrainingSessionRecord) -> String {
        let start = session.startedAt
        let time = Calendar.current.isDateInToday(start)
            ? start.formatted(date: .omitted, time: .shortened)
            : start.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        return "\(session.kindLabel) \(time)"
    }
}

private struct PendingSessionRow: View {
    let title: String
    let status: HealthSyncStatus

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Open")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tint)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        switch status {
        case .recording: return "Still recording"
        case .saving: return "Saving to Health…"
        case .pending, .synced: return "Not in Health yet"
        case .failed: return "Not in Health yet · will retry"
        }
    }

    private var icon: String {
        switch status {
        case .recording: return "record.circle"
        case .saving: return "arrow.triangle.2.circlepath"
        case .pending, .synced: return "clock"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch status {
        case .recording: return .red
        case .failed: return .orange
        case .pending, .saving, .synced: return .blue
        }
    }
}
