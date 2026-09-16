import XCTest
@testable import LiftReference

final class ReferenceDatabaseTests: XCTestCase {

    private var database: ReferenceDatabase { ReferenceDatabase.shared }

    func testSearchesFoodsByName() async throws {
        let hits = try await database.searchFoods("chicken breast", limit: 30)
        XCTAssertFalse(hits.isEmpty)
        XCTAssertLessThanOrEqual(hits.count, 30)
    }

    func testResolvesAFoodByItsIdentifier() async throws {
        let matches = try await database.searchFoods("chicken", limit: 1)
        let hit = try XCTUnwrap(matches.first)
        let resolved = try await database.food(id: hit.id)
        let again = try XCTUnwrap(resolved)
        XCTAssertEqual(again.id, hit.id)
        XCTAssertEqual(again.name, hit.name)
    }

    func testSearchesExercises() async throws {
        let hits = try await database.searchExercises("squat", limit: 30)
        XCTAssertFalse(hits.isEmpty)
        XCTAssertTrue(hits.contains { $0.name.lowercased().contains("squat") })
    }

    func testExerciseLibraryIsFullySized() async throws {
        // 873 exercises ship in exercises.db. A floor, not an equality, so a
        // data refresh doesn't fail this — but an empty or missing resource must.
        let count = try await database.allExercises(limit: 2000).count
        XCTAssertGreaterThan(count, 800)
    }

    func testNutritionScalesWithGrams() async throws {
        let matches = try await database.searchFoods("chicken", limit: 1)
        let food = try XCTUnwrap(matches.first)
        let hundred = food.nutrition(grams: 100)
        let fifty = food.nutrition(grams: 50)
        XCTAssertEqual(fifty.calories, hundred.calories / 2, accuracy: 0.51)
    }

    func testFoodsCarrySaturatedFatPer100g() async throws {
        // USDA SR Legacy 173410, "Butter, salted": 81.11 g fat, 51.368 g saturated.
        let found = try await database.food(id: "usda:173410")
        let butter = try XCTUnwrap(found)
        XCTAssertEqual(butter.saturatedFatPer100g, 51.368)
        XCTAssertEqual(butter.nutrition(grams: 14).saturatedFatG ?? 0, 7.19152, accuracy: 1e-9)
        // The columns that were already there are unchanged by the rebuild.
        XCTAssertEqual(butter.fatPer100g, 81.11)
        XCTAssertEqual(butter.sodiumPer100g, 643)
        XCTAssertEqual(butter.sugarPer100g, 0.06)
    }

    func testAFoodUSDAGaveNoSaturatedFatForIsNilNotZero() async throws {
        // Foundation food 323505, "Kale, raw": fat is published, saturated fat is not.
        let found = try await database.food(id: "usda:323505")
        let kale = try XCTUnwrap(found)
        XCTAssertNil(kale.saturatedFatPer100g)
        XCTAssertNil(kale.nutrition(grams: 100).saturatedFatG)
        XCTAssertEqual(kale.fatPer100g, 1.49)
    }

    func testAnUnknownIdentifierIsNilRatherThanAThrow() async throws {
        let food = try await database.food(id: "usda:this-does-not-exist")
        XCTAssertNil(food)
        let exercise = try await database.exercise(id: "no-such-exercise")
        XCTAssertNil(exercise)
    }
}
