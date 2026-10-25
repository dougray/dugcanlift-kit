import Foundation

/// What `ReferenceDatabase.findFoods` hands back.
public struct FoodSearchResults: Sendable, Equatable {
    public var foods: [FoodRecord]
    /// False when no food has every word that was typed, so `foods` are the
    /// closest ones instead -- the most words matched, the last word typed
    /// first. A screen should say so rather than present them as answers.
    public var matchesEveryWord: Bool

    public init(foods: [FoodRecord], matchesEveryWord: Bool) {
        self.foods = foods
        self.matchesEveryWord = matchesEveryWord
    }

    static let none = FoodSearchResults(foods: [], matchesEveryWord: true)
}

/// The words of what someone typed to find a food.
///
/// An amount is not one of them: LIFT asks how much on the next step, and
/// "2 large eggs" or "chicken breast 6 oz" used to find nothing because no
/// USDA name contains "2" or "oz". Filler goes too ("oats with milk").
struct FoodQuery {
    let words: [String]
    /// Letters and digits only, so a typed brand is recognised however it is
    /// spelt: "Chick-fil-A" and "chick fil a" are both "chickfila".
    let letters: String

    init(_ text: String) {
        words = FoodQuery.tokens(in: text).filter { !FoodQuery.isAmountOrFiller($0) }
        letters = FoodQuery.letters(of: text)
    }

    /// Lowercased words, apostrophes dropped ("McDonald's" is "mcdonalds"),
    /// split on anything but a letter, a digit or `%` -- "2%" is a kind of milk.
    static func tokens(in text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
            .split { !($0.isLetter || $0.isNumber || $0 == "%") }
            .map(String.init)
    }

    static func letters(of text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    private static let units: Set<String> = [
        "g", "gram", "grams", "kg", "mg", "oz", "ounce", "ounces", "lb", "lbs",
        "pound", "pounds", "ml", "l", "cup", "cups", "tbsp", "tablespoon",
        "tablespoons", "tsp", "teaspoon", "teaspoons", "slice", "slices",
        "piece", "pieces", "serving", "servings",
    ]
    private static let filler: Set<String> = [
        "a", "an", "the", "and", "or", "with", "of", "on", "in",
    ]

    static func isAmountOrFiller(_ word: String) -> Bool {
        if units.contains(word) || filler.contains(word) { return true }
        // A number, alone or run into its unit: "2", "150g", "6oz".
        guard let first = word.first, first.isNumber, !word.contains("%") else { return false }
        let unit = word.drop { $0.isNumber }
        return unit.isEmpty || units.contains(String(unit))
    }

    /// English plurals, enough for food names: eggs, berries, tomatoes,
    /// peaches. Not a stemmer -- "glass" and "gas" stay as they are, and so do
    /// "fries", which are not one "fry" ("Tortillas, ready-to-bake or -fry").
    static func singular(_ word: String) -> String {
        if word == "fries" { return word }
        let n = word.count
        if n > 4, word.hasSuffix("ies") { return String(word.dropLast(3)) + "y" }
        if n > 4, word.hasSuffix("oes") { return String(word.dropLast(2)) }
        if n > 4, ["ses", "xes", "zes", "ches", "shes"].contains(where: word.hasSuffix) {
            return String(word.dropLast(2))
        }
        if n > 3, word.hasSuffix("s"), !word.hasSuffix("ss") { return String(word.dropLast()) }
        return word
    }
}

/// One food's name, read once into the shape the ranking needs.
struct FoodName {
    struct Word {
        let offset: Int
        let text: String
        let singular: String
    }

    let words: [Word]
    let length: Int
    /// A brand or restaurant row ("CHICK-FIL-A, ...", "PIZZA HUT ...",
    /// "Fast foods, ...", "Babyfood, ..."), as the letters someone would type
    /// to ask for it. nil for a plain food.
    let setAsideUnless: String?
    let meatless: Bool
    let everyday: Bool

    init(_ name: String, id: String) {
        var words: [Word] = []
        let lowered = name.lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
        var offset = 0
        var current = ""
        func close() {
            guard !current.isEmpty else { return }
            words.append(Word(offset: offset - current.count, text: current,
                              singular: FoodQuery.singular(current)))
            current = ""
        }
        for character in lowered {
            if character.isLetter || character.isNumber || character == "%" {
                current.append(character)
            } else {
                close()
            }
            offset += 1
        }
        close()

        self.words = words
        length = name.count
        setAsideUnless = FoodName.setAside(name)
        meatless = words.contains { $0.text == "meatless" }
        everyday = FoodRanking.everyday.contains(id)
    }

    private static let groups = ["fast food", "restaurant", "babyfood", "infant formula"]

    private static func setAside(_ name: String) -> String? {
        let lead = name.prefix { $0 != "," }
        if let group = groups.first(where: { lead.lowercased().hasPrefix($0) }) {
            return FoodQuery.letters(of: group)
        }
        // USDA writes a brand in capitals, leading the name: "SILK Coffee,
        // soymilk", "McDONALD'S, Hamburger". The brand is the run of words
        // written that way.
        let brand = lead.split(separator: " ").prefix { word in
            let upper = word.filter(\.isUppercase).count
            let lower = word.filter(\.isLowercase).count
            return upper >= 2 && upper > lower
        }
        guard !brand.isEmpty else { return nil }
        return FoodQuery.letters(of: brand.joined())
    }
}

/// Which foods a query finds, best first.
///
/// In order of weight:
///   1. More of the typed words. A food must have one of them to be listed;
///      when none has all of them the rest are the closest, not nothing.
///   2. Among those, the last word typed: it is usually the food, and the
///      words before it describe it ("black coffee", "string cheese").
///   3. Plain foods before brand and restaurant rows and meatless stand-ins,
///      unless that is what was typed.
///   4. The everyday form of a staple (`everyday`) before the rest.
///   5. Whole words before words that merely start the same way, so "egg"
///      is not "Eggnog" and "apple" is not "APPLEBEE'S". A start still
///      counts, because someone typing "chick" has not finished.
///   6. Where the last word typed sits in the name, so "skim milk" is milk
///      before it is a part-skim cheese.
///   7. LIFT web's rule (`lift/foods.js`): where the words start, then the
///      shorter name. USDA qualifies as it elaborates, so the plain food is
///      usually the shortest row that matches.
enum FoodRanking {
    /// The ordinary form of about fifty staples, which USDA names too long to
    /// win on length: plain roasted chicken is "Chicken, broilers or fryers,
    /// breast, meat only, cooked, roasted", and without this "chicken" led
    /// with "Chicken spread", "eggs" with dried yolk and "milk" with sheep's
    /// milk. Chosen by hand, SR Legacy where USDA has the same food twice,
    /// because those rows carry every nutrient.
    ///
    /// It only reorders: a food here still needs the typed words, and still
    /// waits behind a food with more of them. `FoodSearchTests` checks that
    /// every id is in food.db, so a rebuild that renumbers one fails there.
    static let everyday: Set<String> = [
        // Meat, fish, eggs
        "usda:171477", // Chicken, broilers or fryers, breast, meat only, cooked, roasted
        "usda:172388", // Chicken, broilers or fryers, thigh, meat only, cooked, roasted
        "usda:171496", // Turkey, whole, breast, meat only, cooked, roasted
        "usda:174034", // Beef, ground, 85% lean meat / 15% fat, crumbles, cooked, pan-browned
        "usda:168635", // Beef, top sirloin, steak, separable lean only, trimmed to 0" fat, choice, cooked, broiled
        "usda:167914", // Pork, cured, bacon, cooked, baked
        "usda:175168", // Fish, salmon, Atlantic, farmed, cooked, dry heat
        "usda:334194", // Fish, tuna, light, canned in water, drained solids
        "usda:171287", // Egg, whole, raw, fresh
        "usda:173424", // Egg, whole, cooked, hard-boiled
        "usda:173423", // Egg, whole, cooked, fried
        "usda:172187", // Egg, whole, cooked, scrambled
        "usda:172183", // Egg, white, raw, fresh
        "usda:173180", // Beverages, Protein powder whey based
        // Dairy
        "usda:171265", // Milk, whole, 3.25% milkfat, with added vitamin D
        "usda:171267", // Milk, reduced fat, fluid, 2% milkfat, with added vitamin A and vitamin D
        "usda:170872", // Milk, lowfat, fluid, 1% milkfat, with added vitamin A and vitamin D
        "usda:171269", // Milk, nonfat, fluid, with added vitamin A and vitamin D (fat free or skim)
        "usda:170894", // Yogurt, Greek, plain, nonfat
        "usda:170886", // Yogurt, plain, low fat
        "usda:172182", // Cheese, cottage, lowfat, 2% milkfat
        "usda:328637", // Cheese, cheddar
        "usda:170847", // Cheese, mozzarella, part skim milk
        "usda:173410", // Butter, salted
        // Grains
        "usda:168878", // Rice, white, long-grain, regular, enriched, cooked
        "usda:169704", // Rice, brown, long-grain, cooked
        "usda:173904", // Cereals, oats, regular and quick, not fortified, dry
        "usda:173905", // Cereals, oats, regular and quick, unenriched, cooked with water, without salt
        "usda:172688", // Bread, whole-wheat, commercially prepared
        "usda:325871", // Bread, white, commercially prepared
        "usda:169737", // Pasta, cooked, enriched, without added salt
        "usda:167535", // Tortillas, ready-to-bake or -fry, flour, shelf stable
        "usda:174899", // Bagels, plain, enriched, with calcium propionate
        // Fruit and vegetables
        "usda:173944", // Bananas, raw
        "usda:171688", // Apples, raw, with skin
        "usda:169097", // Oranges, raw, all commercial varieties
        "usda:167762", // Strawberries, raw
        "usda:171711", // Blueberries, raw
        "usda:174683", // Grapes, red or green (European type, such as Thompson seedless), raw
        "usda:171705", // Avocados, raw, all commercial varieties
        "usda:170379", // Broccoli, raw
        "usda:168462", // Spinach, raw
        "usda:170393", // Carrots, raw
        "usda:170000", // Onions, raw
        "usda:170457", // Tomatoes, red, ripe, raw, year round average
        "usda:170093", // Potatoes, baked, flesh and skin, without salt
        "usda:168483", // Sweet potato, cooked, baked in skin, flesh, without salt
        "usda:173735", // Beans, black, mature seeds, cooked, boiled, without salt
        "usda:172421", // Lentils, mature seeds, cooked, boiled, without salt
        // Everything else
        "usda:324860", // Peanut butter, smooth style, with salt
        "usda:170567", // Nuts, almonds
        "usda:171413", // Oil, olive, salad or cooking
        "usda:169640", // Honey
        "usda:169655", // Sugars, granulated
        "usda:171890", // Beverages, coffee, brewed, prepared with tap water
        "usda:169098", // Orange juice, raw
        "usda:168746", // Alcoholic beverage, beer, regular, all
    ]

    /// What people type for a food USDA spells another way.
    static let alsoWritten: [String: String] = ["oatmeal": "oats"]

    /// Lower is better, compared in this order.
    private struct Score: Comparable {
        var missing: Int
        var lastWordMissing: Int
        var setAside: Int
        var notEveryday: Int
        var startsOnly: Int
        var foodWordAt: Int
        var place: Int
        var index: Int

        private var keys: [Int] {
            [missing, lastWordMissing, setAside, notEveryday, startsOnly, foodWordAt, place, index]
        }

        static func < (a: Score, b: Score) -> Bool { a.keys.lexicographicallyPrecedes(b.keys) }
    }

    /// Indices into `names`, best first, and whether they have every word.
    static func rank(_ names: [FoodName], for query: FoodQuery,
                     limit: Int) -> (indices: [Int], matchesEveryWord: Bool) {
        let words = query.words
        guard !words.isEmpty, limit > 0 else { return ([], true) }
        let singulars = words.map(FoodQuery.singular)
        let alternates = words.map { alsoWritten[$0] }

        var scored: [Score] = []
        for (index, name) in names.enumerated() {
            var matched = 0
            var startsOnly = 0
            var offsets = 0
            var foodWordAt: Int?
            for (position, word) in words.enumerated() {
                guard let fit = fit(word, singular: singulars[position], in: name)
                        ?? alternates[position].flatMap({ fit($0, singular: FoodQuery.singular($0), in: name) })
                else { continue }
                matched += 1
                offsets += fit.offset
                if !fit.whole { startsOnly += 1 }
                if position == words.count - 1 { foodWordAt = fit.offset }
            }
            guard matched > 0 else { continue }

            var setAside = 0
            if let letters = name.setAsideUnless, !query.letters.contains(letters) { setAside += 1 }
            if name.meatless, !words.contains("meatless") { setAside += 1 }

            scored.append(Score(missing: words.count - matched,
                                lastWordMissing: foodWordAt == nil ? 1 : 0,
                                setAside: setAside,
                                notEveryday: name.everyday ? 0 : 1,
                                startsOnly: startsOnly,
                                foodWordAt: foodWordAt ?? 0,
                                place: offsets * 100 + name.length,
                                index: index))
        }

        let everyWord = scored.contains { $0.missing == 0 }
        if everyWord { scored.removeAll { $0.missing > 0 } }
        scored.sort()
        return (scored.prefix(limit).map(\.index), everyWord || scored.isEmpty)
    }

    private static func fit(_ word: String, singular: String,
                            in name: FoodName) -> (whole: Bool, offset: Int)? {
        var best: (whole: Bool, offset: Int)?
        for candidate in name.words {
            let whole = candidate.text == word || candidate.singular == singular
            guard whole || candidate.text.hasPrefix(word) else { continue }
            if let current = best {
                if current.whole && !whole { continue }
                if current.whole == whole && current.offset <= candidate.offset { continue }
            }
            best = (whole, candidate.offset)
        }
        return best
    }
}
