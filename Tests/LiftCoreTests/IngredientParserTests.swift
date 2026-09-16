import XCTest
@testable import LiftCore

final class IngredientParserTests: XCTestCase {

    func testPullsQuantityAndUnitOffTheFront() {
        let parsed = IngredientParser.parse("2 tbsp olive oil", sortOrder: 0)
        XCTAssertEqual(parsed.qty, 2)
        XCTAssertEqual(parsed.unit, "tbsp")
        XCTAssertEqual(parsed.item, "olive oil")
        XCTAssertEqual(parsed.rawText, "2 tbsp olive oil")
    }

    func testAMissingUnitBecomesTheCountSentinelNotNil() {
        // "2 eggs" needs a grouping key so two eggs are never added to two
        // cups of anything -- but it is not a unit and must not print as one.
        let parsed = IngredientParser.parse("2 eggs", sortOrder: 0)
        XCTAssertEqual(parsed.qty, 2)
        XCTAssertEqual(parsed.unit, IngredientParser.countUnit)
        XCTAssertEqual(parsed.item, "eggs")
    }

    func testTheCountSentinelIsByteIdenticalToTheWebAppsCountUnit() {
        // parser.js declares COUNT_UNIT as a NUL character followed by
        // "count". All four clients aggregate on this key, so a drift here
        // would split one shopping line into two on different platforms.
        XCTAssertEqual(IngredientParser.countUnit.unicodeScalars.first?.value, 0)
        XCTAssertEqual(IngredientParser.countUnit.count, 6)
        XCTAssertTrue(IngredientParser.countUnit.hasSuffix("count"))
    }

    func testReadsFractionsAndMixedNumbers() {
        XCTAssertEqual(IngredientParser.parse("1/2 cup rice", sortOrder: 0).qty, 0.5)
        XCTAssertEqual(IngredientParser.parse("1 1/2 cups flour", sortOrder: 0).qty, 1.5)
    }

    func testAZeroDenominatorDoesNotDivideByZero() {
        let parsed = IngredientParser.parse("1/0 cup rice", sortOrder: 0)
        XCTAssertNil(parsed.qty, "a malformed fraction must give up, not produce infinity")
        XCTAssertNil(parsed.item)
        XCTAssertEqual(parsed.rawText, "1/0 cup rice")
    }

    func testAnUnparseableLineKeepsItsRawTextAndNothingElse() {
        let parsed = IngredientParser.parse("a handful of parsley", sortOrder: 3)
        XCTAssertNil(parsed.qty)
        XCTAssertNil(parsed.item)
        XCTAssertEqual(parsed.rawText, "a handful of parsley")
        XCTAssertEqual(parsed.sortOrder, 3)
    }

    func testGramsResolveOnlyForWeightUnits() throws {
        let grams = IngredientParser.parse("400 g chicken thigh", sortOrder: 0)
        XCTAssertEqual(IngredientParser.grams(for: grams), 400)

        let kilos = IngredientParser.parse("1.2 kg beef mince", sortOrder: 0)
        XCTAssertEqual(try XCTUnwrap(IngredientParser.grams(for: kilos)), 1200, accuracy: 0.001)

        let ounces = IngredientParser.parse("8 oz salmon", sortOrder: 0)
        XCTAssertEqual(try XCTUnwrap(IngredientParser.grams(for: ounces)), 226.796, accuracy: 0.001)
    }

    func testVolumeAndCountsNeverResolveToGrams() {
        // Pricing "2 tbsp olive oil" means inventing a density. The gap is
        // deliberate and is reported to the coach in words instead.
        XCTAssertNil(IngredientParser.grams(for: IngredientParser.parse("2 tbsp olive oil", sortOrder: 0)))
        XCTAssertNil(IngredientParser.grams(for: IngredientParser.parse("1 cup rice", sortOrder: 0)))
        XCTAssertNil(IngredientParser.grams(for: IngredientParser.parse("2 eggs", sortOrder: 0)))
    }

    func testAmountsLabelPrintsCountsBare() {
        let label = CookFormat.amountsLabel([IngredientParser.countUnit: 2, "g": 400])
        XCTAssertTrue(label.contains("2"))
        XCTAssertTrue(label.contains("400 g"))
        XCTAssertFalse(label.contains("count"), "the sentinel must never reach a screen")
    }

    func testTrimmedSurvivesNumbersIntCannotHold() {
        XCTAssertEqual(CookFormat.trimmed(4), "4")
        XCTAssertEqual(CookFormat.trimmed(2.5), "2.5")
        // Would have trapped in `String(Int(value))`.
        XCTAssertFalse(CookFormat.trimmed(1e30).isEmpty)
        XCTAssertFalse(CookFormat.trimmed(.nan).isEmpty)
        XCTAssertFalse(CookFormat.trimmed(.infinity).isEmpty)
    }

    func testServingsLabelSingular() {
        XCTAssertEqual(CookFormat.servingsLabel(1), "1 serving")
        XCTAssertEqual(CookFormat.servingsLabel(4), "4 servings")
        XCTAssertEqual(CookFormat.servingsLabel(2.5), "2.5 servings")
    }

    func testDisplayTextNeverPrintsTheCountSentinelAsAUnit() {
        // The sentinel contains a NUL, so leaking it into a label reads as a
        // stray "count" -- "2 count onion" -- rather than looking broken.
        // CookFormat.amountsLabel already drops it for the shopping list.
        let counted = IngredientParser.parse("1 onion finely chopped", sortOrder: 0)
        XCTAssertEqual(counted.unit, IngredientParser.countUnit)
        XCTAssertEqual(counted.displayText, "1 onion finely chopped")
        XCTAssertFalse(counted.displayText.contains("count"))

        // A real unit still prints.
        let measured = IngredientParser.parse("2 tbsp olive oil", sortOrder: 0)
        XCTAssertEqual(measured.displayText, "2 tbsp olive oil")
    }
}
