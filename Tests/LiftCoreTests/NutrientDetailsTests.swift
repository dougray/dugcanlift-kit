import XCTest
import SwiftData
@testable import LiftCore

/// Saturated fat, sugar and sodium: `NutritionFacts.saturatedFatG`, and the
/// share link's `fx`/`fe` and the plan link's `ux` (SHARE-FORMAT.md and
/// PLAN-FORMAT.md, "Saturated fat, sugar and sodium").
final class NutrientDetailsTests: XCTestCase {

    private func json<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ text: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(text.utf8))
    }

    // MARK: - NutritionFacts

    func testFactsRoundTripWithSaturatedFat() throws {
        let facts = NutritionFacts(calories: 100, fatG: 11, sugarG: 1, sodiumMg: 90, saturatedFatG: 7.2)
        let back = try decode(NutritionFacts.self, try json(facts))
        XCTAssertEqual(back, facts)
        XCTAssertEqual(back.saturatedFatG, 7.2)
    }

    func testFactsRoundTripWithoutSaturatedFat() throws {
        let facts = NutritionFacts(calories: 100, sugarG: 1)
        XCTAssertFalse(try json(facts).contains("saturatedFatG"), "nil is omitted, not written as null")
        XCTAssertNil(try decode(NutritionFacts.self, try json(facts)).saturatedFatG)
    }

    func testAValueEncodedBeforeSaturatedFatExistedStillDecodes() throws {
        // Exactly what 1.8.0's synthesized encoder wrote.
        let old = #"{"calories":250,"proteinG":10,"carbsG":30,"fatG":9,"fiberG":2,"sugarG":12,"sodiumMg":410}"#
        let facts = try decode(NutritionFacts.self, old)
        XCTAssertEqual(facts, NutritionFacts(calories: 250, proteinG: 10, carbsG: 30, fatG: 9,
                                             fiberG: 2, sugarG: 12, sodiumMg: 410))
        XCTAssertNil(facts.saturatedFatG)
    }

    func testSummingKeepsUnknownUnknownAndSumsOnlyKnownValues() {
        let a = NutritionFacts(calories: 100, saturatedFatG: 3)
        let b = NutritionFacts(calories: 50)
        XCTAssertEqual((a + b).saturatedFatG, 3, "a known value plus unknown is the known value")
        XCTAssertNil((b + b).saturatedFatG, "unknown plus unknown never becomes 0 g")
        XCTAssertEqual((a + a).saturatedFatG, 6)
        XCTAssertEqual([a, b, a].reduce(.zero, +).saturatedFatG, 6)
        XCTAssertNil([b, b].reduce(NutritionFacts.zero, +).saturatedFatG)
    }

    func testScalingCarriesSaturatedFatAndKeepsNilNil() {
        XCTAssertEqual(NutritionFacts(saturatedFatG: 4).scaled(by: 2.5).saturatedFatG, 10)
        XCTAssertNil(NutritionFacts(calories: 10).scaled(by: 3).saturatedFatG)
    }

    func testAFoodEntrysSaturatedFatSurvivesAStore() throws {
        let container = try ModelContainer(for: FoodEntry.self, Recipe.self, RecipeIngredient.self, PlannedMeal.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        context.insert(FoodEntry(foodRefID: "usda:173410", name: "Butter", quantity: 14, servingUnit: "g",
                                 nutrition: NutritionFacts(calories: 100, fatG: 11.4, saturatedFatG: 7.2),
                                 mealType: .breakfast))
        context.insert(FoodEntry(foodRefID: "x", name: "Unknown", quantity: 1, servingUnit: "serving",
                                 nutrition: NutritionFacts(calories: 5), mealType: .snack))
        try context.save()

        let entries = try ModelContext(container).fetch(FetchDescriptor<FoodEntry>(sortBy: [SortDescriptor(\.name)]))
        XCTAssertEqual(entries.map(\.nutrition.saturatedFatG), [7.2, nil])
        XCTAssertEqual(entries.totalNutrition.saturatedFatG, 7.2)
    }

    func testAPlannedMealScalesTheRecipesSaturatedFat() {
        let recipe = Recipe(name: "Chilli", servings: 4,
                            nutritionPerServing: NutritionFacts(calories: 500, saturatedFatG: 6))
        let meal = PlannedMeal(recipe: recipe, mealType: .dinner, plannedFor: .now, servings: 1.5)
        XCTAssertEqual(meal.scaledNutrition?.saturatedFatG, 9)
        XCTAssertEqual(recipe.totalNutrition?.saturatedFatG, 24)
    }

    func testMergingTakesOnlyWhatTheDetailsKnow() {
        let facts = NutritionFacts(calories: 100, sugarG: 5, sodiumMg: 200)
        let merged = facts.merging(WireNutrientDetails(saturatedFatG: 2, sugarG: nil, sodiumMg: 250))
        XCTAssertEqual(merged, NutritionFacts(calories: 100, sugarG: 5, sodiumMg: 250, saturatedFatG: 2))
        XCTAssertEqual(facts.merging(nil), facts)
    }

    // MARK: - Rounding

    func testRoundingIsHalfUpGramsToOneDecimalSodiumWhole() {
        XCTAssertEqual(ShareNutrients.roundGrams(2.25), 2.3)
        XCTAssertEqual(ShareNutrients.roundGrams(2.24), 2.2)
        XCTAssertEqual(ShareNutrients.roundGrams(0.05), 0.1)
        XCTAssertEqual(ShareNutrients.roundGrams(48), 48)
        XCTAssertEqual(ShareNutrients.roundMilligrams(2309.5), 2310)
        XCTAssertEqual(ShareNutrients.roundMilligrams(2.5), 3, "half-up, not half-even")
        XCTAssertEqual(ShareNutrients.roundMilligrams(2309.49), 2309)
    }

    // MARK: - fx

    func testDayTotalsSumPerServingTimesServingsOverOnlyTheFoodsThatRecordedEach() throws {
        let totals = try XCTUnwrap(ShareNutrients.dayTotals([
            (servings: 2, details: WireNutrientDetails(saturatedFatG: 3.1, sugarG: 2, sodiumMg: 540)),
            (servings: 1, details: nil),
            (servings: 1.5, details: WireNutrientDetails(sugarG: 12)),
            (servings: 1, details: WireNutrientDetails(sodiumMg: 0.4)),
        ]))
        XCTAssertEqual(totals, WireNutrientTotals(saturatedFatG: 6.2, sugarG: 22, sodiumMg: 1080,
                                                  foods: 4, withSaturatedFat: 1, withSugar: 2, withSodium: 2))
        XCTAssertEqual(try json(totals), "[6.2,22,1080,4,1,2,2]")
    }

    func testDayTotalsAreRoundedOnceAfterSumming() throws {
        // Three foods of 0.04 g: rounding each first would give 0.
        let item = (servings: 1.0, details: Optional(WireNutrientDetails(saturatedFatG: 0.04)))
        XCTAssertEqual(ShareNutrients.dayTotals([item, item, item])?.saturatedFatG, 0.1)
    }

    func testATotalNoFoodRecordedIsNullNotZero() throws {
        let totals = try XCTUnwrap(ShareNutrients.dayTotals([(servings: 1, details: WireNutrientDetails(sodiumMg: 300))]))
        XCTAssertNil(totals.saturatedFatG)
        XCTAssertNil(totals.sugarG)
        XCTAssertEqual(try json(totals), "[null,null,300,1,0,0,1]")
    }

    func testNoFxWhenNoFoodRecordedAny() {
        XCTAssertNil(ShareNutrients.dayTotals([]))
        XCTAssertNil(ShareNutrients.dayTotals([(servings: 1, details: nil),
                                               (servings: 2, details: WireNutrientDetails()),
                                               (servings: 1, details: WireNutrientDetails(sugarG: .nan))]))
    }

    func testAKnownZeroIsCountedAndSent() throws {
        let totals = try XCTUnwrap(ShareNutrients.dayTotals([(servings: 1, details: WireNutrientDetails(sugarG: 0))]))
        XCTAssertEqual(totals.sugarG, 0)
        XCTAssertEqual(totals.withSugar, 1)
    }

    // MARK: - fe / ux rows

    func testItemRowsTrimOnlyTrailingNulls() throws {
        XCTAssertEqual(try json(ShareNutrients.itemRow(WireNutrientDetails(saturatedFatG: 3.14, sugarG: 2, sodiumMg: 540.4))),
                       "[3.1,2,540]")
        XCTAssertEqual(try json(ShareNutrients.itemRow(WireNutrientDetails(sugarG: 12))), "[null,12]")
        XCTAssertEqual(try json(ShareNutrients.itemRow(WireNutrientDetails(saturatedFatG: 1))), "[1]")
        XCTAssertEqual(try json(ShareNutrients.itemRow(WireNutrientDetails(sodiumMg: 90))), "[null,null,90]")
        XCTAssertNil(ShareNutrients.itemRow(WireNutrientDetails()))
        XCTAssertNil(ShareNutrients.itemRow(perServing: NutritionFacts(calories: 100)))
        XCTAssertEqual(ShareNutrients.itemRow(perServing: NutritionFacts(sugarG: 4.44, saturatedFatG: 1.05)),
                       WireNutrientDetails(saturatedFatG: 1.1, sugarG: 4.4))
    }

    func testFeOmittedWhenEveryEntryIsUnknown() {
        XCTAssertNil(ShareNutrients.items([nil, WireNutrientDetails()]))
        XCTAssertEqual(ShareNutrients.items([nil, WireNutrientDetails(sugarG: 1)]),
                       [nil, WireNutrientDetails(sugarG: 1)])
    }

    func testAShortTupleReadsItsMissingSlotsAsNilAndExtraSlotsAreIgnored() throws {
        XCTAssertEqual(try decode(WireNutrientDetails.self, "[null,12]"), WireNutrientDetails(sugarG: 12))
        XCTAssertEqual(try decode(WireNutrientDetails.self, "[1,2,3,4,5]"),
                       WireNutrientDetails(saturatedFatG: 1, sugarG: 2, sodiumMg: 3))
    }

    // MARK: - fx / fe on a day

    private let foodDay = #"{"k":3,"ft":[500,20,10,60,5],"f":[[0,1,300,10,5,30,2,0],[1,2,100,5,2,15,1,1],[2,1,1,0,0,0,0,3]]"#

    func testADayCarriesFxAndFe() throws {
        let day = try decode(WireDay.self, foodDay + #","fx":[21.5,48,2310,3,2,2,3],"fe":[[3.1,2,540],null,[null,12]]}"#)
        XCTAssertEqual(day.fx, WireNutrientTotals(saturatedFatG: 21.5, sugarG: 48, sodiumMg: 2310,
                                                  foods: 3, withSaturatedFat: 2, withSugar: 2, withSodium: 3))
        XCTAssertEqual(day.fe, [WireNutrientDetails(saturatedFatG: 3.1, sugarG: 2, sodiumMg: 540), nil,
                                WireNutrientDetails(sugarG: 12)])
        XCTAssertEqual(day.f?.count, 3)

        let again = try decode(WireDay.self, try json(day))
        XCTAssertEqual(again.fx, day.fx)
        XCTAssertEqual(again.fe, day.fe)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(day)) as? [String: Any])
        XCTAssertEqual(object["fe"] as? NSArray, [[3.1, 2, 540], NSNull(), [NSNull(), 12]] as NSArray)
    }

    func testAnOlderDayWithoutTheKeysIsUnchanged() throws {
        let day = try decode(WireDay.self, foodDay + "}")
        XCTAssertNil(day.fx)
        XCTAssertNil(day.fe)
        XCTAssertEqual(day.ft, [500, 20, 10, 60, 5])
        XCTAssertEqual(day.f?.count, 3)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(day)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["k", "ft", "f"], "nil keys are omitted, never sent as null")
    }

    func testAMalformedFxCostsOnlyFx() throws {
        for fx in [#""lots""#, "[1,2]", #"[1,2,3,"four",1,1,1]"#, "{}"] {
            let day = try decode(WireDay.self, foodDay + #","fx":\#(fx)}"#)
            XCTAssertNil(day.fx, fx)
            XCTAssertEqual(day.f?.count, 3, fx)
            XCTAssertEqual(day.ft?.count, 5, fx)
        }
    }

    func testAMalformedFeEntryCostsOnlyThatEntry() throws {
        let day = try decode(WireDay.self, foodDay + #","fe":[["a",1],[1],{"x":1}]}"#)
        XCTAssertEqual(day.fe, [nil, WireNutrientDetails(saturatedFatG: 1), nil])
        XCTAssertEqual(day.f?.count, 3)
    }

    func testAnFeThatDisagreesWithFIsDroppedWhole() throws {
        let short = try decode(WireDay.self, foodDay + #","fe":[[1],[2]]}"#)
        XCTAssertNil(short.fe, "a misaligned fe would pin sodium on the wrong food")
        XCTAssertEqual(short.f?.count, 3)

        let withoutF = try decode(WireDay.self, #"{"k":1,"fe":[[1]]}"#)
        XCTAssertNil(withoutF.fe)

        let notAnArray = try decode(WireDay.self, foodDay + #","fe":"no"}"#)
        XCTAssertNil(notAnArray.fe)
        XCTAssertEqual(notAnArray.f?.count, 3)
    }

    func testAWholePayloadWithABadFxStillDecodes() throws {
        let payload = #"{"v":1,"c":{"i":"a","n":"Sam","u":"lb"},"r":"2026-09-01","t":"2026-09-07","z":1,"x":[],"d":[\#(foodDay),"fx":"bad","fe":[[1],[2],[3]]}]}"#
        let decoded = try decode(ShareLinkPayload.self, payload)
        XCTAssertNil(decoded.d.first?.fx)
        XCTAssertEqual(decoded.d.first?.fe?.count, 3)
    }

    // MARK: - ux

    private let recipe = #"{"n":"Chilli","s":4,"u":[500,30,40,20,8],"i":["500 g beef"]"#

    func testAPlanRecipeCarriesUx() throws {
        let decoded = try decode(PlanRecipe.self, recipe + #","ux":[6,null,820]}"#)
        XCTAssertEqual(decoded.ux, WireNutrientDetails(saturatedFatG: 6, sodiumMg: 820))
        XCTAssertEqual(decoded.u, [500, 30, 40, 20, 8])

        let built = PlanRecipe(n: "Chilli", s: 4, u: nil, i: nil, t: nil,
                               ux: ShareNutrients.itemRow(perServing: NutritionFacts(sugarG: 3.04)))
        XCTAssertTrue(try json(built).contains(#""ux":[null,3]"#))
        XCTAssertEqual(try decode(PlanRecipe.self, try json(built)), built)
    }

    func testUxIsOmittedWhenNil() throws {
        let plain = PlanRecipe(n: "Chilli", s: 4, u: [1, 2, 3, 4, 5], i: nil, t: nil)
        XCTAssertFalse(try json(plain).contains("ux"))
        XCTAssertNil(try decode(PlanRecipe.self, recipe + "}").ux)
    }

    func testAMalformedUxCostsOnlyUx() throws {
        for ux in [#""x""#, #"["a"]"#, "[null,null]", "{}"] {
            let decoded = try decode(PlanRecipe.self, recipe + #","ux":\#(ux)}"#)
            XCTAssertNil(decoded.ux, ux)
            XCTAssertEqual(decoded.n, "Chilli", ux)
            XCTAssertEqual(decoded.u?.count, 5, ux)
        }
    }
}
