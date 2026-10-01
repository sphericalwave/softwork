//
//  AppModelContainer.swift
//  flow
//
//  The app's SwiftData container, shared by the iOS and macOS entry points.
//
//  Data-loss rules (see build plan, M0 "Persistence safety"):
//  - The configuration must keep resolving to the default store URL
//    (Application Support/default.store). Never pass a new `url:` or name —
//    that silently orphans existing MetricSnapshot rows.
//  - FlowSchemaV1 must exactly match the shape shipped before versioning.
//    Schema changes add a new VersionedSchema and one migration stage per
//    milestone; never edit V1 in place.
//  - Load failure stays fatal. No wipe-and-recreate recovery.
//

import Foundation
import SwiftData
import Persistence

nonisolated enum FlowSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [MetricSnapshot.self] }
}

/// Adds training-session metadata. New entities only, every attribute
/// optional or defaulted, so V1 → V2 is a lightweight migration and existing
/// MetricSnapshot rows are untouched.
nonisolated enum FlowSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [MetricSnapshot.self, TrainingSessionRecord.self, SparringRoundRecord.self]
    }
}

nonisolated enum FlowMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [FlowSchemaV1.self, FlowSchemaV2.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: FlowSchemaV1.self, toVersion: FlowSchemaV2.self)]
    }
}

enum AppModelContainer {
    static func make() -> ModelContainer {
        let schema = Schema(versionedSchema: FlowSchemaV2.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema,
                                      migrationPlan: FlowMigrationPlan.self,
                                      configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
}
