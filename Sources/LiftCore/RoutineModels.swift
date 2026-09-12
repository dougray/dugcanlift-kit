import Foundation
import SwiftData

/// A saved, reusable workout template — the iOS counterpart to Android's
/// `Routine`/`RoutineExercise` (see `LIFT/android/.../data/Routines.kt`).
///
/// A routine's sets are *targets*, not history. Starting a routine creates a
/// real `WorkoutDay`/`ExerciseEntry`/`SetEntry` prefilled from those targets,
/// exactly like logging any other day — the routine itself is never mutated
/// by training against it.
@Model
public final class Routine {
    public var id: UUID = UUID()
    public var name: String = ""
    public var folder: String = ""
    public var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \RoutineExercise.routine)
    public var exercises: [RoutineExercise]? = []

    public init(name: String, folder: String = "", createdAt: Date = .now) {
        self.id = UUID()
        self.name = name
        self.folder = folder
        self.createdAt = createdAt
        self.exercises = []
    }

    public var orderedExercises: [RoutineExercise] {
        (exercises ?? []).sorted { $0.orderIndex < $1.orderIndex }
    }
}

@Model
public final class RoutineExercise {
    public var id: UUID = UUID()
    public var name: String = ""
    public var equipment: String = ""
    public var orderIndex: Int = 0
    public var note: String?
    public var routine: Routine?

    @Relationship(deleteRule: .cascade, inverse: \RoutinePrescribedSet.exercise)
    public var prescribedSets: [RoutinePrescribedSet]? = []

    public init(name: String, equipment: String = "", orderIndex: Int, note: String? = nil) {
        self.id = UUID()
        self.name = name
        self.equipment = equipment
        self.orderIndex = orderIndex
        self.note = note
        self.prescribedSets = []
    }

    public var orderedSets: [RoutinePrescribedSet] {
        (prescribedSets ?? []).sorted { $0.orderIndex < $1.orderIndex }
    }

    /// "Deadlift (Barbell)" — same convention as `ExerciseEntry.displayName`.
    public var displayName: String {
        guard !equipment.isEmpty else { return name }
        return "\(name) (\(equipment.capitalized))"
    }
}

@Model
public final class RoutinePrescribedSet {
    public var id: UUID = UUID()
    public var orderIndex: Int = 0

    // All five optional, matching PLAN-FORMAT's
    // [weightLb, reps, rpe, durationSec, distanceMeters] tuple — a
    // prescription is often partial. Weight is converted to kilograms at
    // decode time (PlanImporter), so this is already canonical.
    public var targetWeightKg: Double?
    public var targetReps: Int?
    public var targetRPE: Double?
    public var targetDurationSec: Int?
    public var targetDistanceMeters: Double?

    public var exercise: RoutineExercise?

    public init(orderIndex: Int,
         targetWeightKg: Double? = nil,
         targetReps: Int? = nil,
         targetRPE: Double? = nil,
         targetDurationSec: Int? = nil,
         targetDistanceMeters: Double? = nil) {
        self.id = UUID()
        self.orderIndex = orderIndex
        self.targetWeightKg = targetWeightKg
        self.targetReps = targetReps
        self.targetRPE = targetRPE
        self.targetDurationSec = targetDurationSec
        self.targetDistanceMeters = targetDistanceMeters
    }

    /// A set with no weight and no reps has nothing iOS can log today — see
    /// the "Out of scope" note in this feature's plan. Duration/distance are
    /// still stored above so nothing is lost if iOS's SetEntry gains those
    /// fields later.
    public var isLoggableToday: Bool { targetWeightKg != nil || targetReps != nil }
}

// NOTE: `extension Routine { func startSession(on:in:) }` from
// lift-ios/Sources/Shared/RoutineModels.swift is intentionally NOT moved
// here. It calls `WorkoutQueries.fetchOrCreate`, `WorkoutDay`, `ExerciseEntry`
// and `SetEntry`, all of which live in lift-ios/Sources/Shared/WorkoutModels.swift
// — a file outside both task-4-brief.md and task-5-brief.md's scope, and one
// the dispatch instructions explicitly say must not move (it encodes LIFT's
// own store identity). Moving the extension verbatim, as the brief's "change
// nothing else" instruction otherwise asks, would fail to compile: LiftCore
// cannot see those types. See task-4-5-report.md for the flagged discrepancy.
