import Foundation
import GRDB
import LiftCore

// MARK: - Records

public struct FoodRecord: Codable, FetchableRecord, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var brand: String?
    public var servingGrams: Double?
    public var servingLabel: String?

    public var caloriesPer100g: Double
    public var proteinPer100g: Double
    public var carbsPer100g: Double
    public var fatPer100g: Double
    public var fiberPer100g: Double?
    public var sugarPer100g: Double?
    public var sodiumPer100g: Double?
    public var source: String

    public static let databaseTableName = "foods"

    /// Convert a chosen portion into the immutable snapshot stored on FoodEntry.
    public func nutrition(grams: Double) -> NutritionFacts {
        let factor = grams / 100.0
        return NutritionFacts(
            calories: caloriesPer100g * factor,
            proteinG: proteinPer100g * factor,
            carbsG:   carbsPer100g * factor,
            fatG:     fatPer100g * factor,
            fiberG:   fiberPer100g.map { $0 * factor },
            sugarG:   sugarPer100g.map { $0 * factor },
            sodiumMg: sodiumPer100g.map { $0 * factor }
        )
    }
}

public struct ExerciseRecord: Codable, FetchableRecord, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var primaryMuscle: String?
    public var equipment: String?
    public var category: String?
    public var mechanic: String?
    public var level: String?
    public var instructions: String?
    public var source: String

    public static let databaseTableName = "exercises"
}

public enum ReferenceDatabaseError: Error {
    case bundleResourceMissing(String)
}

/// Read-only access to the reference data shipped inside the app bundle.
///
/// THREE separate databases, deliberately never joined:
///
///   food.db       USDA (public domain) + Open Food Facts (ODbL)
///   exercises.db  free-exercise-db (public domain) + wger (CC-BY-SA 3.0)
///   recipes.db    UniTools world recipes (CC BY-SA 4.0) + public-domain
///                 cookbooks, built by `Tools/build_recipes.py`
///
/// ODbL, CC-BY-SA 3.0 and CC BY-SA 4.0 are all share-alike, and the first two
/// are mutually incompatible. Keeping them in separate files makes this a
/// Collective Database rather than a Derivative one, so each obligation stays
/// scoped to its own file. Never write a query spanning any two.
///
/// `recipes.db` mixes two licenses *within* one file, which the rule above
/// permits only because they do not conflict: public-domain text can be
/// combined into a BY-SA work and the result is simply BY-SA. Every row still
/// records its own `license` and `attribution` so a public-domain recipe stays
/// identifiable as one. `recipeAttributions()` exists because BY-SA requires
/// the credit to be given, and it must stay reachable from the UI.
///
/// Deliberately NOT SwiftData: this data is static, large, never user-edited,
/// and needs full-text search. Shipping an update is a file replacement with
/// no migration of user data.
public actor ReferenceDatabase {

    public static let shared = ReferenceDatabase()

    private let bundle: Bundle

    private var foodQueue: DatabaseQueue?
    private var exerciseQueue: DatabaseQueue?
    private var recipeQueue: DatabaseQueue?

    /// Designated initializer. `Bundle.module` cannot be used as a default
    /// argument value here — SwiftPM generates it `internal`, and Swift
    /// rejects an internal symbol in a public default argument — so the
    /// convenience initializer below supplies it instead.
    public init(bundle: Bundle) {
        self.bundle = bundle
    }

    public init() {
        self.init(bundle: .module)
    }

    private func open(_ resource: String) throws -> DatabaseQueue {
        guard let url = bundle.url(forResource: resource, withExtension: "db") else {
            throw ReferenceDatabaseError.bundleResourceMissing("\(resource).db")
        }
        var configuration = Configuration()
        configuration.readonly = true
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA query_only = ON")
        }
        return try DatabaseQueue(path: url.path, configuration: configuration)
    }

    private func foods() throws -> DatabaseQueue {
        if let foodQueue { return foodQueue }
        let queue = try open("food")
        foodQueue = queue
        return queue
    }

    private func exercises() throws -> DatabaseQueue {
        if let exerciseQueue { return exerciseQueue }
        let queue = try open("exercises")
        exerciseQueue = queue
        return queue
    }

    /// `recipes.db`  UniTools world recipes (CC BY-SA 4.0) + public-domain
    /// cookbooks. A third file for the same reason as the first two: its
    /// share-alike obligation stays scoped to the file that carries it, and no
    /// query ever spans it and another. See `Tools/build_recipes.py`.
    func recipes() throws -> DatabaseQueue {
        if let recipeQueue { return recipeQueue }
        let queue = try open("recipes")
        recipeQueue = queue
        return queue
    }

    // MARK: Food

    /// Prefix-matched full-text search, ranked by bm25 then name length so
    /// short exact-ish matches win. Matters when someone types "chick"
    /// mid-meal and wants plain chicken breast, not "Chickpea Snack Bar".
    public func searchFoods(_ text: String, limit: Int = 30) throws -> [FoodRecord] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        return try foods().read { db in
            guard let pattern = FTS5Pattern(matchingAllPrefixesIn: trimmed) else { return [] }
            return try FoodRecord.fetchAll(db, sql: """
                SELECT foods.*
                FROM foods
                JOIN foods_fts ON foods_fts.rowid = foods.rowid
                WHERE foods_fts MATCH ?
                ORDER BY bm25(foods_fts), length(foods.name)
                LIMIT ?
                """, arguments: [pattern, limit])
        }
    }

    public func food(barcode: String) throws -> FoodRecord? {
        try foods().read { db in
            try FoodRecord.fetchOne(db,
                sql: "SELECT * FROM foods WHERE barcode = ? LIMIT 1", arguments: [barcode])
        }
    }

    public func food(id: String) throws -> FoodRecord? {
        try foods().read { db in
            try FoodRecord.fetchOne(db, sql: "SELECT * FROM foods WHERE id = ?", arguments: [id])
        }
    }

    // MARK: Exercises

    public func searchExercises(_ text: String, limit: Int = 30) throws -> [ExerciseRecord] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return try allExercises(limit: limit) }

        return try exercises().read { db in
            guard let pattern = FTS5Pattern(matchingAllPrefixesIn: trimmed) else { return [] }
            // Ranking is layered, because no single signal works alone.
            // bm25 by itself put "Barbell Rollout from Bench" next to bench
            // presses; a raw name-prefix boost then put "Bench Jump" on top.
            // Ordering by category and mechanic first pushes plyometrics and
            // stretches below strength work, which is what someone mid-workout
            // is almost always searching for.
            return try ExerciseRecord.fetchAll(db, sql: """
                SELECT exercises.*
                FROM exercises
                JOIN exercises_fts ON exercises_fts.rowid = exercises.rowid
                WHERE exercises_fts MATCH ?
                ORDER BY
                    CASE exercises.category
                        WHEN 'strength' THEN 0
                        WHEN 'olympic weightlifting' THEN 1
                        WHEN 'powerlifting' THEN 1
                        ELSE 2 END,
                    CASE WHEN exercises.mechanic = 'compound' THEN 0 ELSE 1 END,
                    CASE WHEN exercises.name LIKE ? THEN 0 ELSE 1 END,
                    bm25(exercises_fts, 10.0, 1.0),
                    length(exercises.name)
                LIMIT ?
                """, arguments: [pattern, "\(trimmed)%", limit])
        }
    }

    public func allExercises(limit: Int = 1000) throws -> [ExerciseRecord] {
        try exercises().read { db in
            try ExerciseRecord.fetchAll(db,
                sql: "SELECT * FROM exercises ORDER BY name LIMIT ?", arguments: [limit])
        }
    }

    public func exercise(id: String) throws -> ExerciseRecord? {
        try exercises().read { db in
            try ExerciseRecord.fetchOne(db,
                sql: "SELECT * FROM exercises WHERE id = ?", arguments: [id])
        }
    }
}
