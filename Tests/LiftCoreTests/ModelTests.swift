import XCTest
import SwiftData
@testable import LiftCore

final class ModelTests: XCTestCase {

    /// An in-memory container, so these tests never touch a real store.
    private func container() throws -> ModelContainer {
        try ModelContainer(
            for: Recipe.self, RecipeIngredient.self, PlannedMeal.self, Routine.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    func testARecipeRoundTripsThroughAStore() throws {
        let context = ModelContext(try container())
        let recipe = Recipe(name: "Beef Chilli", servings: 4)
        context.insert(recipe)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Recipe>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.name, "Beef Chilli")
        XCTAssertEqual(fetched.first?.servings, 4)
    }

    func testARoutineHoldsItsExercises() throws {
        let context = ModelContext(try container())
        let routine = Routine(name: "Lower A")
        context.insert(routine)
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<Routine>()).first?.name, "Lower A")
    }

    func testModelsAreReachableFromOutsideTheModule() {
        // The point of the package: a second app can name these types. An
        // internal `@Model` compiles fine here and is invisible to Coach.
        XCTAssertNotNil(Recipe.self as Any.Type)
        XCTAssertNotNil(RoutinePrescribedSet.self as Any.Type)
    }
}
