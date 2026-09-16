import XCTest
@testable import LiftCore

final class RecipeJSONLDTests: XCTestCase {

    // MARK: - Finding the block

    func testReadsARecipeOutOfAPage() {
        let html = """
        <html><head>
        <script type="application/ld+json">
        {"@context":"https://schema.org","@type":"Recipe","name":"Chilli",
         "recipeIngredient":["500 g beef mince","1 tbsp olive oil"],
         "recipeInstructions":["Brown the mince.","Simmer."]}
        </script>
        </head><body></body></html>
        """
        let imported = RecipeJSONLD.recipe(fromHTML: html)
        XCTAssertEqual(imported?.name, "Chilli")
        XCTAssertEqual(imported?.ingredientLines, ["500 g beef mince", "1 tbsp olive oil"])
        XCTAssertEqual(imported?.steps, ["Brown the mince.", "Simmer."])
    }

    func testSkipsNonRecipeBlocksAndKeepsLooking() {
        // Sites commonly emit an Organization block before the Recipe one.
        let html = """
        <script type="application/ld+json">{"@type":"Organization","name":"A Blog"}</script>
        <script type="application/ld+json">{"@type":"Recipe","name":"Soup"}</script>
        """
        XCTAssertEqual(RecipeJSONLD.recipe(fromHTML: html)?.name, "Soup")
    }

    func testFindsARecipeInsideAGraph() {
        let json = """
        {"@context":"https://schema.org","@graph":[
          {"@type":"WebSite","name":"A Blog"},
          {"@type":"Recipe","name":"Dal"}]}
        """
        XCTAssertEqual(RecipeJSONLD.recipe(fromJSON: json)?.name, "Dal")
    }

    func testAcceptsAnArrayOfTypes() {
        // Some CMSes declare the page both an Article and a Recipe.
        let json = #"{"@type":["Article","Recipe"],"name":"Stew"}"#
        XCTAssertEqual(RecipeJSONLD.recipe(fromJSON: json)?.name, "Stew")
    }

    func testAPageWithNoRecipeReturnsNilRatherThanAnEmptyRecipe() {
        XCTAssertNil(RecipeJSONLD.recipe(fromHTML: "<html><body>no json-ld here</body></html>"))
        XCTAssertNil(RecipeJSONLD.recipe(fromJSON: #"{"@type":"Recipe"}"#), "a nameless recipe is not importable")
    }

    // MARK: - Instructions

    func testReadsHowToStepObjects() {
        let json = """
        {"@type":"Recipe","name":"Bread","recipeInstructions":[
          {"@type":"HowToStep","text":"Mix."},
          {"@type":"HowToStep","text":"Bake."}]}
        """
        XCTAssertEqual(RecipeJSONLD.recipe(fromJSON: json)?.steps, ["Mix.", "Bake."])
    }

    func testFlattensHowToSections() {
        let json = """
        {"@type":"Recipe","name":"Cake","recipeInstructions":[
          {"@type":"HowToSection","name":"Sponge","itemListElement":[
            {"@type":"HowToStep","text":"Cream butter."}]},
          {"@type":"HowToSection","name":"Icing","itemListElement":[
            {"@type":"HowToStep","text":"Whip cream."}]}]}
        """
        XCTAssertEqual(RecipeJSONLD.recipe(fromJSON: json)?.steps, ["Cream butter.", "Whip cream."])
    }

    func testASingleParagraphSplitsOnNewlinesOnly() {
        // "Bake at 200 C. for 20 minutes" must survive intact -- splitting on
        // sentences would cut it in half.
        let json = #"{"@type":"Recipe","name":"X","recipeInstructions":"Bake at 200 C. for 20 minutes\nRest."}"#
        XCTAssertEqual(RecipeJSONLD.recipe(fromJSON: json)?.steps,
                       ["Bake at 200 C. for 20 minutes", "Rest."])
    }

    func testStripsMarkupAndEntitiesFromText() {
        let json = #"{"@type":"Recipe","name":"Mac &amp; Cheese","recipeInstructions":["<p>Stir well.</p>"]}"#
        let imported = RecipeJSONLD.recipe(fromJSON: json)
        XCTAssertEqual(imported?.name, "Mac & Cheese")
        XCTAssertEqual(imported?.steps, ["Stir well."])
    }

    // MARK: - Yield

    func testReadsServingsFromTheUsualSpellings() {
        func yield(_ value: String) -> Double? {
            RecipeJSONLD.recipe(fromJSON: #"{"@type":"Recipe","name":"X","recipeYield":\#(value)}"#)?.servings
        }
        XCTAssertEqual(yield("4"), 4)
        XCTAssertEqual(yield(#""4""#), 4)
        XCTAssertEqual(yield(#""4 servings""#), 4)
        XCTAssertEqual(yield(#""Serves 6""#), 6)
        XCTAssertEqual(yield(#"["8 slices"]"#), 8)
    }

    func testAYieldWithNoNumberStaysNilRatherThanDefaultingToOne() {
        // Every macro on the recipe is divided by this. A guessed 1 would be a
        // confident wrong answer; nil lets the editor ask.
        let json = #"{"@type":"Recipe","name":"X","recipeYield":"a crowd"}"#
        XCTAssertNil(RecipeJSONLD.recipe(fromJSON: json)?.servings)
    }

    // MARK: - Durations

    func testReadsISO8601Durations() {
        func minutes(_ value: String) -> Int? {
            RecipeJSONLD.recipe(fromJSON: #"{"@type":"Recipe","name":"X","prepTime":"\#(value)"}"#)?.prepMinutes
        }
        XCTAssertEqual(minutes("PT30M"), 30)
        XCTAssertEqual(minutes("PT1H"), 60)
        XCTAssertEqual(minutes("PT1H15M"), 75)
        XCTAssertEqual(minutes("P0DT0H45M"), 45)
        XCTAssertNil(minutes("half an hour"))
    }

    func testMonthsAreIgnoredRatherThanReadAsMinutes() {
        // "M" before the T is months. Reading it as minutes would be a silent
        // 30-fold error on a value a user never typed.
        let json = #"{"@type":"Recipe","name":"X","prepTime":"P2M"}"#
        XCTAssertNil(RecipeJSONLD.recipe(fromJSON: json)?.prepMinutes)
    }

    // MARK: - Author

    func testReadsAuthorAsStringOrPerson() {
        let asString = #"{"@type":"Recipe","name":"X","author":"Nigel"}"#
        XCTAssertEqual(RecipeJSONLD.recipe(fromJSON: asString)?.author, "Nigel")

        let asPerson = #"{"@type":"Recipe","name":"X","author":{"@type":"Person","name":"Nigella"}}"#
        XCTAssertEqual(RecipeJSONLD.recipe(fromJSON: asPerson)?.author, "Nigella")
    }

    // MARK: - Nutrition

    func testReadsNutritionAsPerServing() {
        let json = """
        {"@type":"Recipe","name":"X","nutrition":{"@type":"NutritionInformation",
         "calories":"350 kcal","proteinContent":"12 g","carbohydrateContent":"40 g",
         "fatContent":"14 g","fiberContent":"5 g","sodiumContent":"320 mg"}}
        """
        let facts = RecipeJSONLD.recipe(fromJSON: json)?.nutritionPerServing
        XCTAssertEqual(facts?.calories, 350)
        XCTAssertEqual(facts?.proteinG, 12)
        XCTAssertEqual(facts?.carbsG, 40)
        XCTAssertEqual(facts?.fatG, 14)
        XCTAssertEqual(facts?.fiberG, 5)
        XCTAssertEqual(facts?.sodiumMg, 320)
    }

    func testSodiumInGramsIsConvertedRatherThanReadAsMilligrams() {
        let json = """
        {"@type":"Recipe","name":"X","nutrition":{"calories":"100","sodiumContent":"0.32 g"}}
        """
        XCTAssertEqual(RecipeJSONLD.recipe(fromJSON: json)?.nutritionPerServing?.sodiumMg, 320)
    }

    func testSodiumUnitIsReadAsAWordNotASubstring() {
        // "320 milligrams" contains a "g" and no "mg"; a substring check read
        // it as grams and stored 320,000 mg.
        let cases: [(String, Double)] = [
            (#""320 mg""#, 320), (#""320 milligrams""#, 320), (#""320 Milligram""#, 320),
            (#""320mg""#, 320), (#""0.32 g""#, 320), (#""0.32 grams""#, 320),
            (#""0.32g""#, 320), (#""0.32 GRAMS""#, 320), (#""320""#, 320), ("320", 320),
        ]
        for (sodium, expected) in cases {
            let json = #"{"@type":"Recipe","name":"X","nutrition":{"calories":"100","sodiumContent":\#(sodium)}}"#
            let value = RecipeJSONLD.recipe(fromJSON: json)?.nutritionPerServing?.sodiumMg
            XCTAssertEqual(value ?? -1, expected, accuracy: 1e-9, sodium)
        }
    }

    func testReadsSaturatedFatInGrams() {
        let json = """
        {"@type":"Recipe","name":"X","nutrition":{"calories":"100","fatContent":"14 g",
         "saturatedFatContent":"5.5 g","sugarContent":"9 g"}}
        """
        let facts = RecipeJSONLD.recipe(fromJSON: json)?.nutritionPerServing
        XCTAssertEqual(facts?.saturatedFatG, 5.5)
        XCTAssertEqual(facts?.sugarG, 9)

        let without = #"{"@type":"Recipe","name":"X","nutrition":{"calories":"100","fatContent":"14 g"}}"#
        XCTAssertNil(RecipeJSONLD.recipe(fromJSON: without)?.nutritionPerServing?.saturatedFatG,
                     "absent stays nil, never 0 g")
    }

    func testNutritionWithoutCaloriesIsDropped() {
        let json = #"{"@type":"Recipe","name":"X","nutrition":{"proteinContent":"12 g"}}"#
        XCTAssertNil(RecipeJSONLD.recipe(fromJSON: json)?.nutritionPerServing)
    }

    func testThousandsSeparatorsAreRead() {
        let json = #"{"@type":"Recipe","name":"X","nutrition":{"calories":"1,200 calories"}}"#
        XCTAssertEqual(RecipeJSONLD.recipe(fromJSON: json)?.nutritionPerServing?.calories, 1200)
    }

    // MARK: - Building the model

    func testMakeRecipeParsesIngredientsAndFlagsTheMacrosAsEstimated() {
        let imported = ImportedRecipe(
            name: "Chilli",
            ingredientLines: ["500 g beef mince", "2 tbsp olive oil"],
            steps: ["Brown.", "Simmer."],
            servings: 4,
            prepMinutes: 10,
            cookMinutes: 40,
            author: "Doug",
            nutritionPerServing: NutritionFacts(calories: 500, proteinG: 30),
            sourceTranscript: "{}"
        )
        let url = URL(string: "https://example.com/chilli")!
        let (recipe, ingredients) = imported.makeRecipe(sourceURL: url)

        XCTAssertEqual(recipe.name, "Chilli")
        XCTAssertEqual(recipe.servings, 4)
        XCTAssertEqual(recipe.prepMinutes, 10)
        XCTAssertEqual(recipe.cookMinutes, 40)
        XCTAssertEqual(recipe.sourceAuthor, "Doug")
        XCTAssertEqual(recipe.sourceURL, url)
        XCTAssertTrue(recipe.wasImported)

        // The publisher's number is a claim, not a resolved lookup.
        XCTAssertTrue(recipe.nutritionIsEstimated)

        XCTAssertEqual(ingredients.count, 2)
        XCTAssertEqual(ingredients[0].qty, 500)
        XCTAssertEqual(ingredients[0].unit, "g")
        XCTAssertEqual(ingredients[0].item, "beef mince")
        XCTAssertEqual(ingredients[0].grams, 500)
        XCTAssertEqual(ingredients[1].sortOrder, 1)
    }

    func testAnImportWithNoPublishedMacrosIsNotFlaggedAsEstimated() {
        // nutritionIsEstimated means "there is a number and it is a guess".
        // With no number at all it must stay false, or the UI warns about
        // macros that do not exist.
        let (recipe, _) = ImportedRecipe(name: "X").makeRecipe(sourceURL: nil)
        XCTAssertNil(recipe.nutritionPerServing)
        XCTAssertFalse(recipe.nutritionIsEstimated)
        XCTAssertFalse(recipe.wasImported, "no source URL means hand-entered")
    }

    func testTheSourceTranscriptSurvivesTheImport() {
        // Recipe.sourceTranscript's contract: an import is shown next to its
        // source text before it is saved, so this must never be dropped.
        let json = #"{"@type":"Recipe","name":"Soup","recipeIngredient":["1 onion"]}"#
        let imported = RecipeJSONLD.recipe(fromJSON: json)
        XCTAssertEqual(imported?.sourceTranscript, json)

        let (recipe, _) = imported!.makeRecipe(sourceURL: nil)
        XCTAssertEqual(recipe.sourceTranscript, json)
    }

    func testUnparseableIngredientLinesSurviveAsRawText() {
        // IngredientParser's rule: give up cleanly, keep the line visible.
        let imported = ImportedRecipe(name: "X", ingredientLines: ["salt to taste"])
        let (_, ingredients) = imported.makeRecipe(sourceURL: nil)
        XCTAssertEqual(ingredients[0].rawText, "salt to taste")
        XCTAssertNil(ingredients[0].qty)
        XCTAssertEqual(ingredients[0].displayText, "salt to taste")
    }
}
