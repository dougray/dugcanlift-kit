import XCTest
import LiftCore
@testable import LiftReference

final class RecipeCatalogTests: XCTestCase {

    private let db = ReferenceDatabase()

    // MARK: - The bundled file

    func testTheCatalogueIsBundledAndPopulated() async throws {
        let count = try await db.recipeCount()
        XCTAssertGreaterThan(count, 500, "the starter catalogue should ship hundreds of recipes")
    }

    func testEveryRecipeCarriesItsOwnLicenceAndAttribution() async throws {
        // CC BY-SA 4.0 requires the credit be given, and the public-domain
        // rows must stay identifiable as public domain rather than being
        // absorbed into the share-alike half.
        let attributions = try await db.recipeAttributions()
        XCTAssertFalse(attributions.isEmpty)
        XCTAssertTrue(attributions.contains { $0.contains("CC BY-SA 4.0") })
        XCTAssertTrue(attributions.contains { $0.contains("Public domain") })
    }

    // MARK: - Search

    func testSearchFindsRecipesByName() async throws {
        let hits = try await db.searchRecipes("carbonara")
        XCTAssertFalse(hits.isEmpty)
        XCTAssertTrue(hits.contains { $0.recipe.name.localizedCaseInsensitiveContains("carbonara") })
    }

    func testSearchReturnsIngredientsWithEachHit() async throws {
        let hits = try await db.searchRecipes("carbonara")
        let entry = try XCTUnwrap(hits.first)
        XCTAssertFalse(entry.ingredientLines.isEmpty,
                       "a hit with no ingredients cannot build a shopping list")
    }

    func testAOneLetterQueryReturnsNothingRatherThanEverything() async throws {
        // Same floor as `searchFoods`: one character is a keystroke, not a query.
        let hits = try await db.searchRecipes("c")
        XCTAssertTrue(hits.isEmpty)
    }

    func testBrowseInterleavesBothCollections() async throws {
        // Ordered by name, not by source: 501 world recipes ahead of the
        // heritage ones would read as though the second were an afterthought.
        let page = try await db.browseRecipes(limit: 300)
        let sources = Set(page.map(\.recipe.source))
        XCTAssertGreaterThan(sources.count, 1, "the first page should not be one source only")
        XCTAssertEqual(page.map(\.recipe.name), page.map(\.recipe.name).sorted())
    }

    // MARK: - Nutrition honesty

    func testAPublishedPerServingFigureIsNotRescaled() async throws {
        // The publisher measured the dish. Dividing their per-serving number
        // again would be inventing a second opinion about it.
        let hits = try await db.searchRecipes("carbonara")
        let entry = try XCTUnwrap(hits.first)
        let recipe = entry.recipe
        try XCTSkipIf(recipe.caloriesPerServing == nil)

        let atStated = recipe.nutrition(servings: recipe.servings ?? 1)
        let atDouble = recipe.nutrition(servings: (recipe.servings ?? 1) * 2)
        XCTAssertEqual(atStated?.calories, atDouble?.calories,
                       "a published per-serving figure must not move with the stepper")
    }

    func testAWholeDishRecipeDividesByTheServingsGiven() async throws {
        let page = try await db.browseRecipes(limit: 700)
        let entry = try XCTUnwrap(page.first { $0.recipe.needsServings },
                                  "expected at least one recipe whose source stated no yield")

        let whole = try XCTUnwrap(entry.recipe.caloriesTotal)
        let atFour = try XCTUnwrap(entry.recipe.nutrition(servings: 4))
        XCTAssertEqual(atFour.calories, whole / 4, accuracy: 0.001)
    }

    func testAYieldlessRecipeHasNoPerServingFigureOfItsOwn() async throws {
        // Storing whole-pot macros in a per-serving column would silently
        // claim the pot feeds one.
        let page = try await db.browseRecipes(limit: 700)
        for entry in page where entry.recipe.needsServings {
            XCTAssertNil(entry.recipe.caloriesPerServing)
            XCTAssertNil(entry.recipe.servings)
        }
    }

    func testExactlyOneNutritionSetIsEverPopulated() async throws {
        let page = try await db.browseRecipes(limit: 700)
        for entry in page {
            let r = entry.recipe
            XCTAssertFalse(r.caloriesPerServing != nil && r.caloriesTotal != nil,
                           "\(r.name) carries both per-serving and whole-dish macros")
        }
    }

    func testARecipeWithNoCostableIngredientsSaysWhyRatherThanShowingZero() async throws {
        let page = try await db.browseRecipes(limit: 700)
        let bare = page.filter { $0.recipe.caloriesPerServing == nil && $0.recipe.caloriesTotal == nil }
        let entry = try XCTUnwrap(bare.first)
        XCTAssertNil(entry.recipe.nutrition(servings: 4), "no macros must stay nil, never .zero")
        XCTAssertNotNil(entry.recipe.nutritionNote,
                        "a gap the reader can see needs to say what it is")
    }

    // MARK: - Copying into the library

    func testMakeRecipeParsesIngredientsAndKeepsTheAttribution() async throws {
        let hits = try await db.searchRecipes("carbonara")
        let entry = try XCTUnwrap(hits.first)
        let (recipe, ingredients) = entry.makeRecipe(servings: 2)

        XCTAssertEqual(recipe.name, entry.recipe.name)
        XCTAssertEqual(recipe.servings, 2)
        XCTAssertEqual(ingredients.count, entry.ingredientLines.count)
        XCTAssertTrue(recipe.nutritionIsEstimated)

        // BY-SA credit travels with the copy.
        let transcript = try XCTUnwrap(recipe.sourceTranscript)
        XCTAssertTrue(transcript.contains(entry.recipe.attribution))
        XCTAssertTrue(transcript.contains(entry.recipe.license))
    }

    func testCopyingAYieldlessRecipeUsesTheServingsTheReaderChose() async throws {
        let page = try await db.browseRecipes(limit: 700)
        let entry = try XCTUnwrap(page.first { $0.recipe.needsServings })

        let (recipe, _) = entry.makeRecipe(servings: 6)
        let whole = try XCTUnwrap(entry.recipe.caloriesTotal)
        XCTAssertEqual(recipe.servings, 6)
        XCTAssertEqual(try XCTUnwrap(recipe.nutritionPerServing).calories, whole / 6, accuracy: 0.001)
    }

    func testIngredientLinesSurviveTheCopyVerbatim() async throws {
        // The raw line is the contract -- reparsing is how the clients stay in
        // agreement about what it means, so the text must not be rewritten.
        let hits = try await db.searchRecipes("carbonara")
        let entry = try XCTUnwrap(hits.first)
        let (_, ingredients) = entry.makeRecipe(servings: 2)
        XCTAssertEqual(ingredients.map(\.rawText), entry.ingredientLines)
    }
}
