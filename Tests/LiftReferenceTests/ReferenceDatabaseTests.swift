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

    func testAnUnknownIdentifierIsNilRatherThanAThrow() async throws {
        let food = try await database.food(id: "usda:this-does-not-exist")
        XCTAssertNil(food)
        let exercise = try await database.exercise(id: "no-such-exercise")
        XCTAssertNil(exercise)
    }
}
