import XCTest
@testable import LiftCore

/// The fixtures here are shaped like real captions, not like ideal input.
/// Emoji headings, hashtag tails, mixed bullets and numbering are the normal
/// case for the thing this parser exists to read.
final class CaptionRecipeTests: XCTestCase {

    // MARK: - The common case

    func testLabelledCaptionSplitsOnItsOwnHeadings() {
        let parsed = CaptionRecipe.parse("""
        Creamy Tuscan Chicken 🍗

        Ingredients:
        - 2 chicken breasts
        - 1 cup heavy cream
        - 200g spinach

        Method:
        1. Sear the chicken
        2. Add the cream and wilt the spinach

        #mealprep #highprotein
        """)

        XCTAssertEqual(parsed.split, .labelled)
        XCTAssertEqual(parsed.name, "Creamy Tuscan Chicken 🍗")
        XCTAssertEqual(parsed.ingredientLines,
                       ["2 chicken breasts", "1 cup heavy cream", "200g spinach"])
        XCTAssertEqual(parsed.steps,
                       ["Sear the chicken", "Add the cream and wilt the spinach"])
    }

    func testHeadingsAreFoundThroughDecoration() {
        let parsed = CaptionRecipe.parse("""
        🛒 INGREDIENTS 👇
        2 eggs
        — Instructions —
        Whisk them
        """)

        XCTAssertEqual(parsed.split, .labelled)
        XCTAssertEqual(parsed.ingredientLines, ["2 eggs"])
        XCTAssertEqual(parsed.steps, ["Whisk them"])
    }

    func testWhatYoullNeedIsAnIngredientHeading() {
        let parsed = CaptionRecipe.parse("""
        What you'll need:
        1 banana
        How to make it:
        Mash it
        """)

        XCTAssertEqual(parsed.split, .labelled)
        XCTAssertEqual(parsed.ingredientLines, ["1 banana"])
        XCTAssertEqual(parsed.steps, ["Mash it"])
    }

    // MARK: - Bullets and numbering

    func testListNumberingIsStrippedButDecimalQuantitiesSurvive() {
        // "1.5 cups" losing its "1." would silently become five cups.
        let parsed = CaptionRecipe.parse("""
        Ingredients
        1. 1.5 cups flour
        2) 2 eggs
        """)

        XCTAssertEqual(parsed.ingredientLines, ["1.5 cups flour", "2 eggs"])
    }

    func testMixedBulletsAreRemoved() {
        let parsed = CaptionRecipe.parse("""
        Ingredients
        • 100 g rice
        ▢ 1 tbsp oil
        * 2 cloves garlic
        """)

        XCTAssertEqual(parsed.ingredientLines, ["100 g rice", "1 tbsp oil", "2 cloves garlic"])
    }

    // MARK: - Partial and absent structure

    func testOnlyAnIngredientHeadingIsInferred() {
        let parsed = CaptionRecipe.parse("""
        Ingredients:
        2 eggs
        1 cup milk
        """)

        XCTAssertEqual(parsed.split, .inferred)
        XCTAssertEqual(parsed.ingredientLines, ["2 eggs", "1 cup milk"])
        XCTAssertTrue(parsed.steps.isEmpty)
    }

    func testOnlyAMethodHeadingTakesTheIngredientsFromAbove() {
        let parsed = CaptionRecipe.parse("""
        Garlic Butter Rice
        200 g rice
        2 cloves garlic
        Method
        Boil the rice
        """)

        XCTAssertEqual(parsed.split, .inferred)
        XCTAssertEqual(parsed.name, "Garlic Butter Rice")
        XCTAssertEqual(parsed.ingredientLines, ["200 g rice", "2 cloves garlic"])
        XCTAssertEqual(parsed.steps, ["Boil the rice"])
    }

    func testMethodFirstIsStillLabelled() {
        let parsed = CaptionRecipe.parse("""
        Instructions:
        Melt the butter
        Ingredients:
        50 g butter
        """)

        XCTAssertEqual(parsed.split, .labelled)
        XCTAssertEqual(parsed.steps, ["Melt the butter"])
        XCTAssertEqual(parsed.ingredientLines, ["50 g butter"])
    }

    func testUnstructuredPasteIsUnsortedRatherThanGuessedAt() {
        let parsed = CaptionRecipe.parse("""
        Banana Pancakes
        2 eggs
        1 banana
        Blend and fry
        """)

        XCTAssertEqual(parsed.split, .unsorted)
        XCTAssertEqual(parsed.name, "Banana Pancakes")
        // Everything lands on one side. The editor cuts the method out; the
        // parser does not pretend to know where it starts.
        XCTAssertEqual(parsed.ingredientLines, ["2 eggs", "1 banana", "Blend and fry"])
        XCTAssertTrue(parsed.steps.isEmpty)
    }

    func testEmptyInput() {
        let parsed = CaptionRecipe.parse("")
        XCTAssertTrue(parsed.isEmpty)
        XCTAssertNil(parsed.name)
        XCTAssertEqual(parsed.split, .unsorted)
    }

    // MARK: - Servings

    func testExplicitYieldIsRead() {
        for line in ["Serves 4", "Servings: 4", "Makes about 4 bowls", "Feeds 4"] {
            let parsed = CaptionRecipe.parse("Ingredients\n2 eggs\n\(line)")
            XCTAssertEqual(parsed.servings, 4, "failed on \(line)")
            XCTAssertEqual(parsed.ingredientLines, ["2 eggs"],
                           "the yield line must not also be an ingredient")
        }
    }

    /// The exact line that made yield inference a bad idea: it is a cooking
    /// time, and reading it as a yield halves every macro in the dish.
    func testACookingTimeIsNotAYield() {
        let parsed = CaptionRecipe.parse("""
        Ingredients
        1 ham bone
        Method
        Cook slowly with the ham bone for 2 hours
        """)

        XCTAssertNil(parsed.servings)
    }

    func testAYieldWordWithoutANumberIsNotAYield() {
        let parsed = CaptionRecipe.parse("Ingredients\n100 g rice\nServes with rice")
        XCTAssertNil(parsed.servings)
    }

    // MARK: - The name

    func testAQuantityLineIsNeverTheName() {
        let parsed = CaptionRecipe.parse("2 eggs\n1 banana\nBlend")
        XCTAssertNil(parsed.name)
        XCTAssertEqual(parsed.ingredientLines, ["2 eggs", "1 banana", "Blend"])
    }

    func testTheNameIsNotAlsoAnIngredient() {
        let parsed = CaptionRecipe.parse("Banana Pancakes\n2 eggs")
        XCTAssertEqual(parsed.name, "Banana Pancakes")
        XCTAssertEqual(parsed.ingredientLines, ["2 eggs"])
    }

    func testALineBelowTheHeadingIsNeverTheName() {
        let parsed = CaptionRecipe.parse("Ingredients\nSalt\nPepper")
        XCTAssertNil(parsed.name)
        XCTAssertEqual(parsed.ingredientLines, ["Salt", "Pepper"])
    }

    // MARK: - Noise

    func testHashtagAndEmojiLinesAreDropped() {
        let parsed = CaptionRecipe.parse("""
        Ingredients
        2 eggs
        🔥🔥🔥
        #foodie #mealprep
        @somecreator
        """)

        XCTAssertEqual(parsed.ingredientLines, ["2 eggs"])
    }

    // MARK: - Reparsing an edited box

    func testLinesFromStripsBulletsAndBlanks() {
        let lines = CaptionRecipe.lines(from: """
        - 2 eggs

        • 1 cup milk

        3. 200 g flour
        """)

        XCTAssertEqual(lines, ["2 eggs", "1 cup milk", "200 g flour"])
    }

    // MARK: - Handing over to the shared save path

    func testImportedCarriesTheApprovedTextAndNoMacros() {
        let parsed = CaptionRecipe.parse("Ingredients\n2 eggs")
        let imported = parsed.imported(name: "Scramble",
                                       ingredientLines: ["2 eggs", "10 g butter"],
                                       steps: ["Whisk"],
                                       servings: 2)

        XCTAssertEqual(imported.name, "Scramble")
        XCTAssertEqual(imported.ingredientLines, ["2 eggs", "10 g butter"])
        XCTAssertEqual(imported.steps, ["Whisk"])
        XCTAssertEqual(imported.servings, 2)
        // A caption states none, so the costing pass fills the gap exactly as
        // it does for a page that published none.
        XCTAssertNil(imported.nutritionPerServing)
        XCTAssertTrue(imported.sourceTranscript.contains("2 eggs"))
    }

    /// The parser only splits; quantities stay `IngredientParser`'s job, and
    /// it still refuses to guess at a volume it cannot weigh.
    func testQuantitiesAreStillTheParsersJobOnSave() {
        let parsed = CaptionRecipe.parse("Ingredients\n- 1 1/2 cups oats\n- a handful of nuts")

        let oats = IngredientParser.parse(parsed.ingredientLines[0], sortOrder: 0)
        XCTAssertEqual(oats.qty, 1.5)
        XCTAssertEqual(oats.unit, "cups")
        XCTAssertNil(IngredientParser.grams(for: oats))

        let nuts = IngredientParser.parse(parsed.ingredientLines[1], sortOrder: 1)
        XCTAssertNil(nuts.qty)
    }
}
