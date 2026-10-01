// Persistence — scaffolded for the Softwork Sparring build plan (M0/M6/M7).
// Two SwiftData containers per plan: Main.store (classes Z/T/P/C) and
// Health.store (HRSeries only) — see /Users/darkknight/.claude/plans/atomic-floating-feather.md
//
// Training sessions keep only metadata here (Main.store): heart rate, energy
// and the workout itself live in HealthKit once a session is saved. Until
// then the readings sit in AthleteFeatures' per-session buffer file.
