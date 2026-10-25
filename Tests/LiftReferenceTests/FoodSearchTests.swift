import XCTest
@testable import LiftReference

/// `findFoods`, the search a person logging a meal types into.
///
/// Every expectation here was written by hand from the USDA rows themselves --
/// what someone who typed the query would want at the top -- never captured
/// from the ranking's own output, which would only prove it agrees with itself.
final class FoodSearchTests: XCTestCase {

    private var database: ReferenceDatabase { ReferenceDatabase.shared }

    private func names(_ query: String, limit: Int = 5) async throws -> [String] {
        try await database.findFoods(query, limit: limit).foods.map(\.name)
    }

    private func first(_ query: String) async throws -> String {
        let found = try await names(query, limit: 1)
        return try XCTUnwrap(found.first, query)
    }

    // MARK: Never nothing for a food word

    /// The defect: every typed word had to be in the name, so one word USDA
    /// does not use emptied the list and the screen offered hand entry instead.
    func testAWordNoFoodHasStillShowsTheClosestFoods() async throws {
        for query in ["baked chicken", "black coffee", "string cheese"] {
            let found = try await database.findFoods(query, limit: 5)
            XCTAssertFalse(found.foods.isEmpty, query)
            XCTAssertFalse(found.matchesEveryWord, query)
        }
    }

    /// The food is the last word; the ones before it describe it. Without this,
    /// "black coffee" led with "Bear, black, meat". It is a tie-break, not a
    /// rule over word count: "turkey burger" is closer to ground turkey than
    /// to a veggie burger alone.
    func testClosestMatchesFavourTheLastWordTyped() async throws {
        for (query, food) in [("baked chicken", "chicken"), ("black coffee", "coffee"),
                              ("string cheese", "cheese")] {
            for name in try await names(query) {
                XCTAssertTrue(name.lowercased().contains(food), "\(query): \(name)")
            }
        }
        // Closest matches are a judgement; these pin only that the right food
        // is near the top, not which reading of the phrase wins.
        let turkey = try await names("turkey burger", limit: 3)
        XCTAssertTrue(turkey.contains { $0.hasPrefix("Turkey") }, "\(turkey)")
        let tuna = try await first("tuna salad sandwich")
        XCTAssertTrue(tuna.lowercased().contains("tuna"), tuna)
    }

    /// LIFT asks for the amount on the next step, so an amount typed into the
    /// search is not a word to find.
    func testAmountsAndUnitsAreNotWordsToFind() async throws {
        let eggs = try await database.findFoods("2 large eggs", limit: 3)
        XCTAssertTrue(eggs.matchesEveryWord)
        XCTAssertTrue(try XCTUnwrap(eggs.foods.first).name.hasPrefix("Egg"))

        let breast = try await database.findFoods("chicken breast 6 oz", limit: 5)
        XCTAssertTrue(breast.matchesEveryWord)
        for name in breast.foods.map({ $0.name.lowercased() }) {
            XCTAssertTrue(name.contains("chicken") && name.contains("breast"), name)
        }

        let rice = try await database.findFoods("1 cup rice", limit: 3)
        XCTAssertTrue(rice.matchesEveryWord)
        XCTAssertTrue(try XCTUnwrap(rice.foods.first).name.hasPrefix("Rice"))
    }

    func testAPercentIsAWordNotAnAmount() async throws {
        for name in try await names("2% milk") {
            // "2%", not the end of "12%".
            XCTAssertNotNil(name.range(of: #"(^|[^0-9.])2%"#, options: .regularExpression), name)
        }
    }

    /// "medium", "glass of": how much, not what. They help find a row that
    /// has them and never make a right answer only "the closest".
    func testSizesAreNotWordsAFoodMustHave() async throws {
        for (query, lead) in [("1 medium banana", "Bananas, raw"), ("glass of milk", "Milk,"),
                              ("1 scoop whey", "Beverages, Protein powder whey based")] {
            let found = try await database.findFoods(query, limit: 1)
            XCTAssertTrue(found.matchesEveryWord, query)
            XCTAssertTrue(try XCTUnwrap(found.foods.first).name.hasPrefix(lead), query)
        }
        let eggs = try await database.findFoods("2 large eggs", limit: 1)
        XCTAssertTrue(eggs.matchesEveryWord)
    }

    // MARK: The plain food first

    /// A whole word beats a word that merely starts the same way.
    func testAWholeWordBeatsALongerWordStartingWithIt() async throws {
        let egg = try await first("egg")
        XCTAssertTrue(egg.hasPrefix("Egg,") || egg.hasPrefix("Eggs,"), egg)

        let apple = try await first("apple")
        XCTAssertTrue(apple.hasPrefix("Apples,"), apple)

        for name in try await names("salmon") {
            XCTAssertFalse(name.hasPrefix("Salmonberries"), name)
        }
    }

    func testPluralsAndSingularsFindEachOther() async throws {
        let found1 = try await names("banana", limit: 1)
        XCTAssertEqual(found1, ["Bananas, raw"])
        let found2 = try await names("bananas", limit: 1)
        XCTAssertEqual(found2, ["Bananas, raw"])
        let found3 = try await names("strawberry", limit: 1)
        XCTAssertEqual(found3, ["Strawberries, raw"])
        let tomato = try await first("tomatoes")
        XCTAssertTrue(tomato.hasPrefix("Tomato"), tomato)
    }

    func testWordsMatchInAnyOrder() async throws {
        let found4 = try await names("cheddar cheese", limit: 1)
        XCTAssertEqual(found4, ["Cheese, cheddar"])
        let yogurt = try await first("greek yogurt")
        XCTAssertTrue(yogurt.hasPrefix("Yogurt, Greek"), yogurt)
    }

    /// Brand and restaurant rows wait behind plain foods unless the brand was
    /// typed. "chick" is someone halfway through "chicken".
    func testBrandsAndRestaurantsComeAfterPlainFoods() async throws {
        let chick = try await first("chick")
        XCTAssertFalse(chick.hasPrefix("CHICK-FIL-A"), chick)

        let pizza = try await first("pizza")
        XCTAssertFalse(pizza.hasPrefix("PIZZA HUT"), pizza)

        let coffee = try await first("coffee")
        XCTAssertFalse(coffee.hasPrefix("SILK"), coffee)

        for name in try await names("chicken") {
            XCTAssertFalse(name.lowercased().contains("meatless"), name)
        }
    }

    func testTypingTheBrandBringsItUp() async throws {
        let brand = try await first("chick-fil-a")
        XCTAssertTrue(brand.hasPrefix("CHICK-FIL-A"), brand)

        let pizza = try await first("pizza hut")
        XCTAssertTrue(pizza.hasPrefix("PIZZA HUT"), pizza)
    }

    // MARK: Words that are not the food

    /// A staple is lifted only by what it is called. A word in the middle of
    /// its name ("salad or cooking", "canned in water", "with salt") is not
    /// what it is, and must not pull it above the food that word names.
    func testAWordInsideAStaplesNameDoesNotPullItUp() async throws {
        let expected: [(String, (String) -> Bool)] = [
            ("salad", { !$0.hasPrefix("Oil,") }),
            ("water", { $0.hasPrefix("Water") }),
            ("salt", { $0 == "Salt, table" }),
            ("flour", { !$0.hasPrefix("Tortillas") }),
            ("olives", { $0.hasPrefix("Olives,") }),
            ("seeds", { !$0.hasPrefix("Lentils") }),
            ("greens", { !$0.hasPrefix("Grapes") }),
            ("peas", { $0.hasPrefix("Peas,") }),
            ("pea", { $0.hasPrefix("Peas,") }),
            ("almond milk", { $0.lowercased().contains("almond milk") }),
        ]
        for (query, isRight) in expected {
            let top = try await first(query)
            XCTAssertTrue(isRight(top), "\(query): \(top)")
        }
    }

    /// Only the last word can still be being typed. "soy" is a finished word,
    /// so it is not "soymilk" or "non-soy" on its own -- but "soy milk" together
    /// spells USDA's "Soymilk".
    func testOnlyTheLastWordMayBeUnfinished() async throws {
        let soy = try await first("soy milk")
        XCTAssertTrue(soy.hasPrefix("Soymilk"), soy)

        let cream = try await first("cream cheese")
        XCTAssertTrue(cream.hasPrefix("Cheese, cream"), cream)

        for name in try await names("toast with butter", limit: 10) {
            XCTAssertFalse(name.hasPrefix("Seeds, sesame butter"), name)
        }
    }

    func testPluralsUSDAWritesSingularStillFind() async throws {
        let cheese = try await first("cheeses")
        XCTAssertTrue(cheese.hasPrefix("Cheese"), cheese)
        let veggie = try await first("veggies")
        XCTAssertTrue(veggie.lowercased().contains("veggie"), veggie)
        let smoothies = try await database.findFoods("smoothies")
        XCTAssertGreaterThan(smoothies.foods.count, 3)
    }

    func testAnAccentDoesNotEmptyTheList() async throws {
        let pepper = try await first("jalapeño")
        XCTAssertTrue(pepper.hasPrefix("Peppers, jalapeno"), pepper)
    }

    /// DENNY'S would win on place and length; only the brand rule puts the
    /// plain food first. (The cost, accepted: a restaurant dish such as
    /// "fried chicken" also waits behind plain rows until the place is typed.)
    func testABrandWaitsEvenWhereItWouldWinOnLength() async throws {
        let hash = try await first("hash browns")
        XCTAssertTrue(hash.hasPrefix("Potatoes, hash brown"), hash)
        let fries = try await first("french fries")
        XCTAssertTrue(fries.hasPrefix("Potatoes, french fried"), fries)
    }

    func testABrandTypedAsOneWordIsTheBrand() async throws {
        let brand = try await first("chickfila")
        XCTAssertTrue(brand.hasPrefix("CHICK-FIL-A"), brand)
    }

    /// When some foods have every word, only those are listed.
    func testFoodsMissingAWordAreLeftOutWhenOthersHaveThemAll() async throws {
        let found = try await database.findFoods("grilled chicken breast", limit: 10)
        XCTAssertTrue(found.matchesEveryWord)
        for name in found.foods.map({ $0.name.lowercased() }) {
            XCTAssertTrue(name.contains("grilled") && name.contains("chicken") && name.contains("breast"), name)
        }
    }

    // MARK: Second review

    /// "half" is an amount ("half a bagel") and a food ("half and half").
    func testHalfAndHalfIsAFood() async throws {
        let cream = try await first("half and half")
        XCTAssertTrue(cream.hasPrefix("Cream,") && cream.contains("half and half"), cream)
    }

    /// A shortened word may come before the food word: "mac and cheese",
    /// "chick breast". It may match the start of a longer word only when no
    /// plain food has it whole -- "toast" (French toast) and "soy" (soy sauce)
    /// do, so they stay whole.
    func testAShortenedWordBeforeTheFoodWordStillFinds() async throws {
        let mac = try await first("mac and cheese")
        XCTAssertTrue(mac.lowercased().hasPrefix("macaroni and cheese"), mac)
        let chick = try await first("chick breast")
        XCTAssertTrue(chick.hasPrefix("Chicken"), chick)
    }

    /// A size narrows a staple; it does not outrank it. "2 large eggs" led
    /// with egg yolk, about twice a whole egg's calories.
    func testASizeDoesNotOutrankTheEverydayFood() async throws {
        let eggs = try await first("2 large eggs")
        XCTAssertTrue(eggs.hasPrefix("Egg, whole") || eggs == "Eggs, Grade A, Large, egg whole", eggs)
    }

    /// A word no plain food uses is someone asking for the product.
    func testAProductsOwnWordBringsTheBrandUp() async throws {
        let whopper = try await first("beef whopper")
        XCTAssertTrue(whopper.contains("WHOPPER"), whopper)
        let muffin = try await first("bacon mcmuffin")
        XCTAssertTrue(muffin.contains("McMUFFIN"), muffin)
    }

    /// "Fast foods, ..." and "Restaurant, ..." are generic dishes, not brands.
    func testAGenericRestaurantDishIsNotSetAside() async throws {
        let burger = try await first("cheeseburger")
        XCTAssertTrue(burger.hasPrefix("Fast foods, cheeseburger"), burger)
    }

    func testContainersAreAmounts() async throws {
        let cola = try await database.findFoods("can of coke", limit: 1)
        XCTAssertTrue(cola.matchesEveryWord)
        XCTAssertEqual(cola.foods.first?.name, "Beverages, carbonated, cola, regular")
    }

    /// The cut keeps the last word, the food, whatever comes before it.
    func testALongQueryKeepsItsLastWord() {
        let words = FoodQuery("grilled chicken breast with brown rice steamed broccoli and black beans").words
        XCTAssertEqual(words.last, "beans")
        XCTAssertLessThanOrEqual(words.count, FoodQuery.mostWords)
    }

    // MARK: Third review

    /// The one probe that logged wrong numbers: regular cola, about 140 kcal
    /// a can, for a diet one. USDA writes diet as "low calorie".
    func testADietDrinkIsTheLowCalorieOne() async throws {
        let found = try await database.findFoods("diet coke", limit: 1)
        let drink = try XCTUnwrap(found.foods.first)
        XCTAssertLessThan(drink.caloriesPer100g, 5, drink.name)
        XCTAssertTrue(drink.name.lowercased().contains("cola"), drink.name)
    }

    /// Peanut butter is called butter; peanuts are peanuts.
    func testPeanutsAreNotPeanutButter() async throws {
        let nuts = try await first("peanuts")
        XCTAssertTrue(nuts.hasPrefix("Peanuts,"), nuts)
        let spread = try await first("peanut butter")
        XCTAssertTrue(spread.hasPrefix("Peanut butter"), spread)
    }

    /// USDA leads some rows with a group ("Crustaceans", "Mollusks",
    /// "Alcoholic beverage, distilled"); the food is the part after it.
    func testAGroupLeadIsNotTheFood() async throws {
        let shrimp = try await first("shrimp")
        XCTAssertTrue(shrimp.hasPrefix("Crustaceans, shrimp"), shrimp)
        let oysters = try await first("oysters")
        XCTAssertTrue(oysters.hasPrefix("Mollusks, oyster"), oysters)
        let whiskey = try await first("whiskey")
        XCTAssertTrue(whiskey.hasPrefix("Alcoholic beverage, distilled"), whiskey)
    }

    // MARK: Everyday foods

    /// The plain staple, not whatever USDA happened to name shortest. Without
    /// the everyday list "chicken" led with "Chicken spread", "eggs" with
    /// dried yolk, "rice" with rice crackers and "milk" with sheep's milk.
    func testAStapleLeadsWithItsEverydayForm() async throws {
        let expected: [(String, (String) -> Bool)] = [
            ("chicken", { $0.hasPrefix("Chicken, broilers or fryers,") }),
            ("chick", { $0.hasPrefix("Chicken, broilers or fryers,") }),
            ("chicken breast", { $0 == "Chicken, broilers or fryers, breast, meat only, cooked, roasted" }),
            ("chicken thigh", { $0 == "Chicken, broilers or fryers, thigh, meat only, cooked, roasted" }),
            ("eggs", { $0.hasPrefix("Egg, whole,") }),
            ("hard boiled egg", { $0 == "Egg, whole, cooked, hard-boiled" }),
            ("egg whites", { $0 == "Egg, white, raw, fresh" }),
            ("rice", { $0.hasPrefix("Rice, white, long-grain") || $0.hasPrefix("Rice, brown, long-grain") }),
            ("brown rice", { $0.hasPrefix("Rice, brown, long-grain, cooked") }),
            ("milk", { $0.hasPrefix("Milk, whole,") || $0.hasPrefix("Milk, reduced fat,")
                        || $0.hasPrefix("Milk, lowfat,") || $0.hasPrefix("Milk, nonfat,") }),
            ("skim milk", { $0.hasPrefix("Milk, nonfat, fluid") }),
            ("oats", { $0.hasPrefix("Cereals, oats, regular and quick") }),
            ("oatmeal", { $0.hasPrefix("Cereals, oats, regular and quick") }),
            ("bacon", { $0.hasPrefix("Pork, cured, bacon, cooked") }),
            ("salmon", { $0.hasPrefix("Fish, salmon, Atlantic") }),
            ("steak", { $0.hasPrefix("Beef, top sirloin, steak") }),
            ("ground beef", { $0.hasPrefix("Beef, ground, 85% lean") }),
            ("potato", { $0.hasPrefix("Potatoes, baked, flesh and skin") }),
            ("coffee", { $0 == "Beverages, coffee, brewed, prepared with tap water" }),
            ("tuna", { $0.hasPrefix("Fish, tuna, light, canned in water") }),
            ("bread", { $0.hasPrefix("Bread, whole-wheat, commercially prepared")
                         || $0.hasPrefix("Bread, white, commercially prepared") }),
        ]
        for (query, isRight) in expected {
            let top = try await first(query)
            XCTAssertTrue(isRight(top), "\(query): \(top)")
        }
    }

    /// The list only reorders what the words already found. It never adds a
    /// food that does not match, and never beats a food with more of the words.
    func testTheEverydayListNeverOverridesTheWords() async throws {
        for name in try await names("chicken spread") {
            XCTAssertTrue(name.lowercased().contains("spread"), name)
        }
        let tenders = try await first("chicken breast tenders")
        XCTAssertTrue(tenders.lowercased().contains("tenders"), tenders)
    }

    /// The list names rows by id. A rebuilt food.db that drops or renumbers
    /// one must fail here, not quietly stop ranking that food first.
    func testEveryEverydayFoodIsInTheDatabase() async throws {
        for id in FoodRanking.everyday.keys {
            let found = try await database.food(id: id)
            XCTAssertNotNil(found, id)
        }
    }

    // MARK: Edges

    func testNothingToFindFindsNothing() async throws {
        for query in ["", " ", "x", "with", "2 cups"] {
            let found = try await database.findFoods(query)
            XCTAssertTrue(found.foods.isEmpty, "\(query)")
            XCTAssertTrue(found.matchesEveryWord, "\(query)")
        }
    }

    func testLimitIsHonoured() async throws {
        let seven = try await database.findFoods("chicken", limit: 7)
        XCTAssertEqual(seven.foods.count, 7)
    }

    func testAFoundFoodIsTheSameRecordAsByIdentifier() async throws {
        let found = try await database.findFoods("butter", limit: 1)
        let hit = try XCTUnwrap(found.foods.first)
        let again = try await database.food(id: hit.id)
        XCTAssertEqual(again, hit)
    }

    // MARK: The query's words

    func testQueryWordsDropAmountsUnitsAndFiller() {
        XCTAssertEqual(FoodQuery("2 large eggs").words, ["eggs"])
        XCTAssertEqual(FoodQuery("2 large eggs").sizes, ["large"])
        XCTAssertEqual(FoodQuery("Chicken breast, 6 oz").words, ["chicken", "breast"])
        XCTAssertEqual(FoodQuery("1/2 cup oats with milk").words, ["oats", "milk"])
        XCTAssertEqual(FoodQuery("150g rice").words, ["rice"])
        XCTAssertEqual(FoodQuery("2% milk").words, ["2%", "milk"])
        XCTAssertEqual(FoodQuery("McDonald's").words, ["mcdonalds"])
    }

    func testAWordMeetsItsOtherForms() {
        XCTAssertTrue(FoodQuery.forms(of: "eggs").contains("egg"))
        XCTAssertTrue(FoodQuery.forms(of: "berries").contains("berry"))
        XCTAssertTrue(FoodQuery.forms(of: "tomatoes").contains("tomato"))
        XCTAssertTrue(FoodQuery.forms(of: "peaches").contains("peach"))
        XCTAssertTrue(FoodQuery.forms(of: "cheeses").contains("cheese"))
        XCTAssertTrue(FoodQuery.forms(of: "veggies").contains("veggie"))
        XCTAssertEqual(FoodQuery.forms(of: "glass"), ["glass"])
        XCTAssertEqual(FoodQuery.forms(of: "gas"), ["gas"])
        // Not "fry": that is "Tortillas, ready-to-bake or -fry".
        XCTAssertEqual(FoodQuery.forms(of: "fries"), ["fries"])
    }

    func testAccentsAreFolded() {
        XCTAssertEqual(FoodQuery("Jalapeño").words, ["jalapeno"])
    }

    func testAPasteIsCutToAFewWords() {
        let paste = Array(repeating: "chicken", count: 2_000).joined(separator: " ")
        XCTAssertLessThanOrEqual(FoodQuery(paste).words.count, 8)
    }

    func testALonePercentIsNotAWord() {
        XCTAssertEqual(FoodQuery("chicken %").words, ["chicken"])
    }
}
