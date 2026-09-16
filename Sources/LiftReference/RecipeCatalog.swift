import Foundation
import GRDB
import LiftCore

/// One recipe from the bundled starter catalogue.
///
/// Read-only reference data, like `FoodRecord` and `ExerciseRecord`. It is not
/// a `Recipe`: nothing here is in the user's library until they choose to add
/// it, and `makeRecipe(servings:)` is what performs that copy.
public struct CatalogRecipe: Codable, FetchableRecord, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var summary: String?
    /// ISO country code, for the world recipes. nil for the heritage books.
    public var country: String?
    public var category: String?

    /// How many the source says it feeds. **nil when the source never said**,
    /// which is most of the public-domain books: every macro is divided by
    /// this, so it is left empty rather than guessed at.
    public var servings: Double?
    public var prepMinutes: Int?
    public var cookMinutes: Int?

    public var caloriesPerServing: Double?
    public var proteinPerServing: Double?
    public var carbsPerServing: Double?
    public var fatPerServing: Double?

    /// The whole finished dish, populated only when `servings` is nil.
    /// Exactly one of the two sets is ever filled in.
    public var caloriesTotal: Double?
    public var proteinTotal: Double?
    public var carbsTotal: Double?
    public var fatTotal: Double?

    public var nutritionIsEstimated: Bool
    /// Plain-English coverage: which ingredients could be costed and which
    /// could not, or why there are no macros at all. Shown before the recipe
    /// is added, never hidden behind a disclosure.
    public var nutritionNote: String?

    /// Newline-separated, matching how `Recipe.steps` is stored.
    public var steps: String
    public var source: String
    public var license: String
    public var attribution: String
    public var sourceURL: String?

    public static let databaseTableName = "recipes"

    public var stepLines: [String] {
        steps.split(whereSeparator: \.isNewline).map(String.init)
    }

    /// True when the macros describe the whole dish because the source stated
    /// no yield. The reader supplies a serving count on add, the same way the
    /// link importer asks when a page does not state one.
    public var needsServings: Bool { servings == nil && caloriesTotal != nil }

    /// Per serving at the given count.
    ///
    /// For a source that published per-serving figures this ignores the
    /// argument, because those are already per serving and rescaling them
    /// would be inventing a second opinion about a number the publisher
    /// measured. For a whole-dish recipe it divides.
    public func nutrition(servings count: Double) -> NutritionFacts? {
        if let caloriesPerServing {
            return NutritionFacts(
                calories: caloriesPerServing,
                proteinG: proteinPerServing ?? 0,
                carbsG: carbsPerServing ?? 0,
                fatG: fatPerServing ?? 0)
        }
        guard let caloriesTotal else { return nil }
        let divisor = (count.isFinite && count > 0) ? count : 1
        return NutritionFacts(
            calories: caloriesTotal / divisor,
            proteinG: (proteinTotal ?? 0) / divisor,
            carbsG: (carbsTotal ?? 0) / divisor,
            fatG: (fatTotal ?? 0) / divisor)
    }
}

/// One ingredient line, kept exactly as the catalogue stores it.
///
/// Raw text only, and parsed on add rather than here, for the reason
/// `WebLibraryImporter` reparses too: the line is the contract, and reparsing
/// is how every client stays in agreement about what it means.
public struct CatalogIngredient: Codable, FetchableRecord, Sendable {
    public var recipeID: String
    public var sortOrder: Int
    public var rawText: String

    public static let databaseTableName = "recipe_ingredients"
}

/// A catalogue entry with its ingredients, ready to show or to copy.
public struct CatalogEntry: Identifiable, Sendable {
    public var recipe: CatalogRecipe
    public var ingredientLines: [String]

    public var id: String { recipe.id }

    public init(recipe: CatalogRecipe, ingredientLines: [String]) {
        self.recipe = recipe
        self.ingredientLines = ingredientLines
    }

    /// Copies this entry into the user's own library.
    ///
    /// Returns the ingredients alongside the recipe rather than only hanging
    /// them off it, because SwiftData needs each inserted into the context.
    /// The caller inserts both and sets the relationship, the same shape
    /// `ImportedRecipe.makeRecipe` uses.
    ///
    /// `nutritionIsEstimated` carries over: a world recipe's macros are its
    /// publisher's figure and a heritage recipe's were costed from whichever
    /// lines were written in a weight. Neither was resolved ingredient by
    /// ingredient against the food database for this user's copy.
    public func makeRecipe(servings: Double) -> (recipe: Recipe, ingredients: [RecipeIngredient]) {
        let made = Recipe(
            name: recipe.name,
            servings: servings,
            steps: recipe.stepLines,
            sourceURL: recipe.sourceURL.flatMap(URL.init(string:)),
            sourceAuthor: recipe.attribution,
            nutritionPerServing: recipe.nutrition(servings: servings),
            nutritionIsEstimated: recipe.nutritionIsEstimated,
            // Attribution and the costing caveat travel with the copy. CC
            // BY-SA requires the credit; the caveat is what stops a short
            // macro figure being read as a whole one.
            sourceTranscript: [recipe.attribution, recipe.license, recipe.nutritionNote]
                .compactMap { $0 }
                .joined(separator: "\n"))
        made.prepMinutes = recipe.prepMinutes
        made.cookMinutes = recipe.cookMinutes

        let ingredients = ingredientLines.enumerated().map { index, line in
            IngredientParser.parse(line, sortOrder: index)
        }
        return (made, ingredients)
    }
}

extension ReferenceDatabase {

    // MARK: Recipe catalogue

    /// Prefix-matched full-text search over the bundled catalogue, ranked the
    /// same way `searchFoods` is: bm25 first, then name length, so a short
    /// exact-ish match beats a long one that merely contains the word.
    public func searchRecipes(_ text: String, limit: Int = 40) throws -> [CatalogEntry] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        return try recipes().read { db in
            guard let pattern = FTS5Pattern(matchingAllPrefixesIn: trimmed) else { return [] }
            let found = try CatalogRecipe.fetchAll(db, sql: """
                SELECT recipes.*
                FROM recipes
                JOIN recipes_fts ON recipes_fts.rowid = recipes.rowid
                WHERE recipes_fts MATCH ?
                ORDER BY bm25(recipes_fts), length(recipes.name)
                LIMIT ?
                """, arguments: [pattern, limit])
            return try Self.attachIngredients(found, db)
        }
    }

    /// The catalogue's opening page, before anyone has typed anything.
    ///
    /// Ordered by name rather than by source so the two collections interleave:
    /// a browsing list that ran 501 world recipes before reaching the heritage
    /// ones would read as though the second collection were an afterthought.
    public func browseRecipes(limit: Int = 60, offset: Int = 0) throws -> [CatalogEntry] {
        try recipes().read { db in
            let found = try CatalogRecipe.fetchAll(db, sql: """
                SELECT * FROM recipes ORDER BY name LIMIT ? OFFSET ?
                """, arguments: [limit, offset])
            return try Self.attachIngredients(found, db)
        }
    }

    public func catalogRecipe(id: String) throws -> CatalogEntry? {
        try recipes().read { db in
            guard let found = try CatalogRecipe.fetchOne(
                db, sql: "SELECT * FROM recipes WHERE id = ?", arguments: [id])
            else { return nil }
            return try Self.attachIngredients([found], db).first
        }
    }

    public func recipeCount() throws -> Int {
        try recipes().read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM recipes") ?? 0
        }
    }

    /// Every distinct attribution in the catalogue, for the credits screen.
    ///
    /// CC BY-SA 4.0 requires the credit be given, so this is not decoration:
    /// it is the obligation, and it must not be possible to ship the data
    /// without it being reachable in the UI.
    public func recipeAttributions() throws -> [String] {
        try recipes().read { db in
            try String.fetchAll(db, sql: """
                SELECT DISTINCT attribution || ' — ' || license
                FROM recipes ORDER BY 1
                """)
        }
    }

    /// One query for the ingredients of every recipe in the page, rather than
    /// one query per recipe: a 60-row browse would otherwise be 61 round trips.
    private static func attachIngredients(_ found: [CatalogRecipe],
                                          _ db: Database) throws -> [CatalogEntry] {
        guard !found.isEmpty else { return [] }
        let ids = found.map(\.id)
        let placeholders = databaseQuestionMarks(count: ids.count)
        let rows = try CatalogIngredient.fetchAll(db, sql: """
            SELECT * FROM recipe_ingredients
            WHERE recipeID IN (\(placeholders))
            ORDER BY recipeID, sortOrder
            """, arguments: StatementArguments(ids))

        var byRecipe: [String: [String]] = [:]
        for row in rows { byRecipe[row.recipeID, default: []].append(row.rawText) }

        return found.map { CatalogEntry(recipe: $0, ingredientLines: byRecipe[$0.id] ?? []) }
    }
}
