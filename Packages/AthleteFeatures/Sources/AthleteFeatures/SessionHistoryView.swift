//
//  SessionHistoryView.swift
//  AthleteFeatures
//
//  Past training sessions, newest first, each with where it stands in
//  Health. Sessions not in Health yet are surfaced at the top with one
//  action to save them now. Numbers come from the session's stored summary,
//  so history needs no HealthKit read.
//

#if os(iOS)
import SwiftUI
import SwiftData
import Persistence
import SessionEngine

public struct SessionHistoryView: View {
    @Query(sort: \TrainingSessionRecord.startedAt, order: .reverse) private var sessions: [TrainingSessionRecord]
    @Environment(\.modelContext) private var modelContext
    private let sync = HealthSessionSync.shared

    public init() {}

    private var unsavedCount: Int {
        sessions.filter { $0.endedAt != nil && $0.healthKitWorkoutID == nil }.count
    }

    public var body: some View {
        List {
            if unsavedCount > 0 {
                Section {
                    Button {
                        Task { await sync.syncPending(context: modelContext) }
                    } label: {
                        HStack {
                            Label(unsavedCount == 1 ? "Save 1 session to Health"
                                                    : "Save \(unsavedCount) sessions to Health",
                                  systemImage: "arrow.clockwise.heart")
                            Spacer()
                            if sync.isSyncing { ProgressView() }
                        }
                        .contentShape(Rectangle())
                    }
                    .disabled(sync.isSyncing)
                } footer: {
                    Text("Sessions not in Health yet stay on this phone and are retried each time flow opens.")
                }
            }

            Section {
                ForEach(sessions) { session in
                    NavigationLink {
                        SessionDetailView(record: session)
                    } label: {
                        SessionRow(record: session, status: sync.status(of: session))
                    }
                }
            }
        }
        .overlay {
            if sessions.isEmpty {
                ContentUnavailableView("No Sessions Yet", systemImage: "figure.martial.arts",
                                       description: Text("Training sessions you record appear here."))
            }
        }
        .navigationTitle("History")
    }
}

private struct SessionRow: View {
    let record: TrainingSessionRecord
    let status: HealthSyncStatus

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.kindLabel)
                    .font(.headline)
                Text(record.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if let duration = record.duration {
                    Text(HeartRateChart.clock(duration))
                        .monospacedDigit()
                }
                SyncBadge(status: status)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

private struct SessionDetailView: View {
    let record: TrainingSessionRecord
    @Query private var rounds: [SparringRoundRecord]
    @Environment(\.modelContext) private var modelContext
    private let sync = HealthSessionSync.shared

    init(record: TrainingSessionRecord) {
        self.record = record
        let id: UUID? = record.id
        _rounds = Query(filter: #Predicate<SparringRoundRecord> { $0.sessionID == id }, sort: \.start)
    }

    var body: some View {
        Form {
            Section {
                HealthSyncStatusView(status: sync.status(of: record), kindLabel: record.kindLabel) {
                    sync.retry(record, context: modelContext)
                }
            } header: {
                Text("Apple Health")
            }

            Section {
                LabeledContent("Started", value: record.startedAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Duration", value: record.duration.map(HeartRateChart.clock) ?? "--")
                LabeledContent("Active calories", value: record.activeCalories.map { "\(Int($0.rounded())) kcal" } ?? "--")
                LabeledContent("HR avg", value: record.averageBPM.map { "\($0) bpm" } ?? "--")
                LabeledContent("HR max", value: record.maxBPM.map { "\($0) bpm" } ?? "--")
            }

            if !rounds.isEmpty {
                Section("Sparring") {
                    LabeledContent("Rounds", value: "\(rounds.count)")
                    LabeledContent("Timeouts", value: "\(record.timeoutCount)")
                    LabeledContent("Over ceiling", value: HeartRateChart.clock(record.secondsOverCeiling))
                }
            }
        }
        .monospacedDigit()
        .navigationTitle(record.kindLabel)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Where a session stands in Health, with the fix when it isn't there.
/// Shared by the end-of-session summary and session history.
struct HealthSyncStatusView: View {
    let status: HealthSyncStatus
    let kindLabel: String
    let retry: @MainActor () -> Void

    var body: some View {
        switch status {
        case .recording:
            Label("Recording — saved to Health when you end the session.", systemImage: "record.circle")
                .foregroundStyle(.secondary)
        case .saving:
            HStack(spacing: 8) {
                ProgressView()
                Text("Saving to Health…")
            }
            .foregroundStyle(.secondary)
        case .synced:
            VStack(alignment: .leading, spacing: 4) {
                Label("Saved to Health as \(kindLabel)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("In the Health app: Browse › Activity › Workouts.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .pending:
            VStack(alignment: .leading, spacing: 8) {
                Label("Not in Health yet", systemImage: "clock")
                    .font(.headline)
                Text("Kept on this phone and saved automatically next time flow opens.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Save Now", action: retry)
                    .buttonStyle(.bordered)
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label("Not saved to Health", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.headline)
                Text("\(message) Your session is kept on this phone and retried each time flow opens. Check that flow can write workouts in Settings › Health › Data Access & Devices › flow.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Try Again", action: retry)
                    .buttonStyle(.bordered)
            }
        }
    }
}

private struct SyncBadge: View {
    let status: HealthSyncStatus

    var body: some View {
        Group {
            switch status {
            case .synced:
                Label("In Health", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .saving:
                Label("Saving", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(.secondary)
            case .pending:
                Label("Pending", systemImage: "clock").foregroundStyle(.secondary)
            case .failed:
                Label("Not saved", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            case .recording:
                Label("Recording", systemImage: "record.circle").foregroundStyle(.red)
            }
        }
        .font(.caption)
        .labelStyle(.titleAndIcon)
    }
}

private extension TrainingSessionRecord {
    var kindLabel: String {
        WorkoutKind(rawValue: kindRaw)?.label ?? kindRaw.capitalized
    }

    /// nil while still recording.
    var duration: TimeInterval? {
        endedAt.map { max($0.timeIntervalSince(startedAt), 0) }
    }
}
#endif
