import Foundation

/// What `ReferenceDatabase.findFoods` hands back.
public struct FoodSearchResults: Sendable, Equatable {
    public var foods: [FoodRecord]
    /// False when no food has every word that was typed, so `foods` are the
    /// closest ones instead: the most words matched.
    /// A screen should say so rather than present them as answers.
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
    /// What the food must be called. The last is the food itself, usually,
    /// and the only one that may be unfinished.
    let words: [String]
    /// A size ("medium", "large"). It helps find a row that says it and is
    /// never a word a food must have.
    let sizes: [String]
    /// Letters and digits only, so a typed brand is recognised however it is
    /// spelt: "Chick-fil-A", "chick fil a" and "chickfila" are all "chickfila".
    let letters: String

    /// More words than anyone types for one food. A pasted paragraph is cut
    /// here rather than ranked word by word against every row.
    static let mostWords = 8

    init(_ text: String) {
        let kept = FoodQuery.tokens(in: text).filter { !FoodQuery.isAmountOrFiller($0) }
        var words = kept.filter { !FoodQuery.sizeWords.contains($0) }
        var sizes = kept.filter { FoodQuery.sizeWords.contains($0) }
        // "large" alone is still something to look for.
        if words.isEmpty { (words, sizes) = (sizes, []) }
        self.words = Array(words.prefix(FoodQuery.mostWords))
        self.sizes = Array(sizes.prefix(FoodQuery.mostWords))
        letters = FoodQuery.letters(of: text)
    }

    /// Lowercased with accents folded ("jalapeño" is food.db's "jalapeno"),
    /// apostrophes dropped ("McDonald's" is "mcdonalds"), split on anything
    /// but a letter, a digit or `%` -- "2%" is a kind of milk, a lone "%" is
    /// nothing.
    static func tokens(in text: String) -> [String] {
        fold(text)
            .split { !($0.isLetter || $0.isNumber || $0 == "%") }
            .map(String.init)
            .filter { $0.contains { $0.isLetter || $0.isNumber } }
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
    }

    static func letters(of text: String) -> String {
        String(fold(text).filter { $0.isLetter || $0.isNumber })
    }

    private static let units: Set<String> = [
        "g", "gram", "grams", "kg", "mg", "oz", "ounce", "ounces", "lb", "lbs",
        "pound", "pounds", "ml", "l", "cup", "cups", "tbsp", "tablespoon",
        "tablespoons", "tsp", "teaspoon", "teaspoons", "slice", "slices",
        "piece", "pieces", "serving", "servings", "scoop", "scoops", "glass",
        "glasses", "bowl", "bowls", "half", "dozen",
    ]
    private static let filler: Set<String> = [
        "a", "an", "the", "and", "or", "with", "of", "on", "in",
    ]
    private static let sizeWords: Set<String> = ["small", "medium", "large", "big", "extra"]

    static func isAmountOrFiller(_ word: String) -> Bool {
        if units.contains(word) || filler.contains(word) { return true }
        // A number, alone or run into its unit: "2", "150g", "6oz".
        guard let first = word.first, first.isNumber, !word.contains("%") else { return false }
        let unit = word.drop { $0.isNumber }
        return unit.isEmpty || units.contains(String(unit))
    }

    /// The word and the singulars it might be, enough for food names: eggs,
    /// berries, tomatoes, peaches, cheeses, veggies. Two words meet when they
    /// share a form, so a plural USDA writes singular ("veggie burgers") and
    /// one it writes plural ("Strawberries") both find. Not a stemmer --
    /// "glass" and "gas" stay as they are, and so do "fries", which are not
    /// one "fry" ("Tortillas, ready-to-bake or -fry").
    static func forms(of word: String) -> Set<String> {
        var forms: Set<String> = [word]
        guard word != "fries" else { return forms }
        let n = word.count
        if n > 3, word.hasSuffix("s"), !word.hasSuffix("ss") { forms.insert(String(word.dropLast())) }
        if n > 4, word.hasSuffix("es") { forms.insert(String(word.dropLast(2))) }
        if n > 4, word.hasSuffix("ies") { forms.insert(String(word.dropLast(3)) + "y") }
        return forms
    }
}

/// One food's name, read once into the shape the ranking needs.
struct FoodName {
    struct Word {
        let offset: Int
        let text: String
        let forms: Set<String>
    }

    let words: [Word]
    let length: Int
    /// A brand or restaurant row ("CHICK-FIL-A, ...", "PIZZA HUT ...",
    /// "Fast foods, ...", "Babyfood, ..."), as the letters someone would type
    /// to ask for it. nil for a plain food.
    let setAsideUnless: String?
    /// The brand alone, so "chickfila" typed as one word finds the rows that
    /// USDA spells "CHICK-FIL-A". nil when the row has no brand.
    let brand: String?
    let meatless: Bool
    /// What this row answers to, when it is the everyday form of a staple.
    let everyday: Set<String>?
    /// The word the name is a name of. USDA leads with it and qualifies after
    /// the comma, and the head of the lead is its last word: "Sweet potato,
    /// cooked" is a potato, "Olive loaf, pork" is a loaf. A lead that is only
    /// a group ("Beverages", "Fish") hands over to the part after it:
    /// "Fish, salmon, Atlantic" is a salmon.
    let head: Word?

    init(_ name: String, id: String) {
        var words: [Word] = []
        var offset = 0
        var current = ""
        func close() {
            guard !current.isEmpty else { return }
            words.append(Word(offset: offset - current.count, text: current,
                              forms: FoodQuery.forms(of: current)))
            current = ""
        }
        for character in FoodQuery.fold(name) {
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
        let brand = FoodName.brand(name)
        self.brand = brand
        setAsideUnless = FoodName.group(name) ?? brand
        meatless = words.contains { $0.text == "meatless" }
        everyday = FoodRanking.everyday[id].map { Set($0.flatMap(FoodQuery.forms)) }
        head = FoodName.head(name, words: words)
    }

    private static let groupLeads: Set<String> = [
        "beverages", "fish", "cereals", "cereals ready-to-eat", "nuts", "spices",
        "alcoholic beverage", "snacks", "candies",
    ]

    private static func head(_ name: String, words: [Word]) -> Word? {
        let parts = FoodQuery.fold(name).split(separator: ",", omittingEmptySubsequences: false)
        guard let lead = parts.first else { return nil }
        var end = lead.count
        if groupLeads.contains(lead.trimmingCharacters(in: .whitespaces)), parts.count > 1 {
            end += 1 + parts[1].count
        }
        return words.last { $0.offset < end }
    }

    private static let groups = ["fast food", "restaurant", "babyfood", "infant formula"]

    private static func group(_ name: String) -> String? {
        let lead = name.prefix { $0 != "," }.lowercased()
        return groups.first(where: { lead.hasPrefix($0) }).map(FoodQuery.letters)
    }

    /// USDA writes a brand in capitals, leading the name: "SILK Coffee,
    /// soymilk", "McDONALD'S, Hamburger". The brand is the run of words
    /// written that way.
    private static func brand(_ name: String) -> String? {
        let lead = name.prefix { $0 != "," }
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
/// A food is listed when it has at least one of the typed words. Only the
/// last word may match the start of a longer word, because only the last can
/// still be being typed: "chick" finds chicken, but "soy milk" does not find
/// "non-soy". Two typed words may spell one of USDA's ("soy milk" is
/// "Soymilk"). When some food has every word, only those are listed.
///
/// Then, in order of weight:
///   1. More of the typed words.
///   2. Any sizes typed ("medium").
///   3. Plain foods before brand and restaurant rows and meatless stand-ins,
///      unless that is what was typed.
///   4. Whole words before the start of one, so "pea" is peas before peanut
///      butter, and "egg" is not "Eggnog".
///   5. The everyday form of a staple (`everyday`), when the food word typed
///      is what that staple is called.
///   6. A name whose head is the food word -- the last word typed, which is
///      usually the food, the words before it describing it ("black coffee",
///      "string cheese"). `FoodName.head`: "potato" is potatoes before sweet
///      potato, "olives" is olives before "Olive loaf", "pea" is peas before
///      "Soup, pea". Only a tie-break: as a rule above the others it sent
///      "turkey burger" to veggie burgers rather than ground turkey.
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
    /// Each answers only to what it is called. Olive oil is "salad or
    /// cooking" oil and canned tuna is "canned in water", and before this was
    /// a list of names "salad" led with olive oil and "water" with tuna.
    ///
    /// It only reorders: a food here still needs the typed words, and still
    /// waits behind a food with more of them. `FoodSearchTests` checks that
    /// every id is in food.db, so a rebuild that renumbers one fails there.
    static let everyday: [String: [String]] = [
        // Meat, fish, eggs
        "usda:171477": ["chicken", "breast"], // Chicken, broilers or fryers, breast, meat only, cooked, roasted
        "usda:172388": ["chicken", "thigh"], // Chicken, broilers or fryers, thigh, meat only, cooked, roasted
        "usda:171496": ["turkey", "breast"], // Turkey, whole, breast, meat only, cooked, roasted
        "usda:174034": ["beef", "ground"], // Beef, ground, 85% lean meat / 15% fat, crumbles, cooked, pan-browned
        "usda:168635": ["steak", "sirloin"], // Beef, top sirloin, steak, separable lean only, trimmed to 0" fat, choice, cooked, broiled
        "usda:167914": ["bacon"], // Pork, cured, bacon, cooked, baked
        "usda:175168": ["salmon"], // Fish, salmon, Atlantic, farmed, cooked, dry heat
        "usda:334194": ["tuna"], // Fish, tuna, light, canned in water, drained solids
        "usda:171287": ["egg"], // Egg, whole, raw, fresh
        "usda:173424": ["egg"], // Egg, whole, cooked, hard-boiled
        "usda:173423": ["egg"], // Egg, whole, cooked, fried
        "usda:172187": ["egg"], // Egg, whole, cooked, scrambled
        "usda:172183": ["egg", "white"], // Egg, white, raw, fresh
        "usda:173180": ["protein", "whey", "powder"], // Beverages, Protein powder whey based
        // Dairy
        "usda:171265": ["milk"], // Milk, whole, 3.25% milkfat, with added vitamin D
        "usda:171267": ["milk"], // Milk, reduced fat, fluid, 2% milkfat, with added vitamin A and vitamin D
        "usda:170872": ["milk"], // Milk, lowfat, fluid, 1% milkfat, with added vitamin A and vitamin D
        "usda:171269": ["milk"], // Milk, nonfat, fluid, with added vitamin A and vitamin D (fat free or skim)
        "usda:170894": ["yogurt"], // Yogurt, Greek, plain, nonfat
        "usda:170886": ["yogurt"], // Yogurt, plain, low fat
        "usda:172182": ["cheese", "cottage"], // Cheese, cottage, lowfat, 2% milkfat
        "usda:328637": ["cheese", "cheddar"], // Cheese, cheddar
        "usda:170847": ["cheese", "mozzarella"], // Cheese, mozzarella, part skim milk
        "usda:173410": ["butter"], // Butter, salted
        // Grains
        "usda:168878": ["rice"], // Rice, white, long-grain, regular, enriched, cooked
        "usda:169704": ["rice"], // Rice, brown, long-grain, cooked
        "usda:173904": ["oat"], // Cereals, oats, regular and quick, not fortified, dry
        "usda:173905": ["oat"], // Cereals, oats, regular and quick, unenriched, cooked with water, without salt
        "usda:172688": ["bread"], // Bread, whole-wheat, commercially prepared
        "usda:325871": ["bread"], // Bread, white, commercially prepared
        "usda:169737": ["pasta"], // Pasta, cooked, enriched, without added salt
        "usda:167535": ["tortilla"], // Tortillas, ready-to-bake or -fry, flour, shelf stable
        "usda:174899": ["bagel"], // Bagels, plain, enriched, with calcium propionate
        // Fruit and vegetables
        "usda:173944": ["banana"], // Bananas, raw
        "usda:171688": ["apple"], // Apples, raw, with skin
        "usda:169097": ["orange"], // Oranges, raw, all commercial varieties
        "usda:167762": ["strawberry"], // Strawberries, raw
        "usda:171711": ["blueberry"], // Blueberries, raw
        "usda:174683": ["grape"], // Grapes, red or green (European type, such as Thompson seedless), raw
        "usda:171705": ["avocado"], // Avocados, raw, all commercial varieties
        "usda:170379": ["broccoli"], // Broccoli, raw
        "usda:168462": ["spinach"], // Spinach, raw
        "usda:170393": ["carrot"], // Carrots, raw
        "usda:170000": ["onion"], // Onions, raw
        "usda:170457": ["tomato"], // Tomatoes, red, ripe, raw, year round average
        "usda:170093": ["potato"], // Potatoes, baked, flesh and skin, without salt
        "usda:168483": ["potato"], // Sweet potato, cooked, baked in skin, flesh, without salt
        "usda:173735": ["bean"], // Beans, black, mature seeds, cooked, boiled, without salt
        "usda:172421": ["lentil"], // Lentils, mature seeds, cooked, boiled, without salt
        // Everything else
        "usda:324860": ["peanut", "butter"], // Peanut butter, smooth style, with salt
        "usda:170567": ["almond"], // Nuts, almonds
        "usda:171413": ["oil"], // Oil, olive, salad or cooking
        "usda:169640": ["honey"], // Honey
        "usda:169655": ["sugar"], // Sugars, granulated
        "usda:171890": ["coffee"], // Beverages, coffee, brewed, prepared with tap water
        "usda:169098": ["juice"], // Orange juice, raw
        "usda:168746": ["beer"], // Alcoholic beverage, beer, regular, all
    ]

    /// What people type for a food USDA spells another way.
    static let alsoWritten: [String: String] = ["oatmeal": "oats"]

    /// Lower is better, compared in this order.
    private struct Score: Comparable {
        var missing: Int
        var sizesMissing: Int
        var setAside: Int
        var startsOnly: Int
        var notEveryday: Int
        var notHead: Int
        var place: Int
        var index: Int

        private var keys: [Int] {
            [missing, sizesMissing, setAside, startsOnly, notEveryday, notHead, place, index]
        }

        static func < (a: Score, b: Score) -> Bool { a.keys.lexicographicallyPrecedes(b.keys) }
    }

    private struct Fit {
        var whole: Bool
        var offset: Int
    }

    /// Indices into `names`, best first, and whether they have every word.
    static func rank(_ names: [FoodName], for query: FoodQuery,
                     limit: Int) -> (indices: [Int], matchesEveryWord: Bool) {
        let words = query.words
        guard !words.isEmpty, limit > 0 else { return ([], true) }
        let last = words.count - 1
        let forms = words.map(FoodQuery.forms)
        let alternates = words.map { alsoWritten[$0].map { ($0, FoodQuery.forms(of: $0)) } }
        // Two typed words that USDA writes as one: "soy milk", "Soymilk".
        let joined = words.indices.dropLast().map { words[$0] + words[$0 + 1] }
        let joinedForms = joined.map(FoodQuery.forms)
        // The food word: as typed, as also written, or run into the word
        // before it ("soy milk" is a soymilk, not a milk).
        let foodForms = forms[last].union(alternates[last]?.1 ?? []).union(joinedForms.last ?? [])

        var scored: [Score] = []
        for (index, name) in names.enumerated() {
            var fits: [Fit?] = words.indices.map { position in
                let unfinished = position == last
                return fit(words[position], forms: forms[position], unfinished: unfinished, in: name)
                    ?? alternates[position].flatMap {
                        fit($0.0, forms: $0.1, unfinished: unfinished, in: name)
                    }
            }
            for (position, word) in joined.enumerated()
            where fits[position]?.whole != true || fits[position + 1]?.whole != true {
                let unfinished = position + 1 == last
                if let both = fit(word, forms: joinedForms[position], unfinished: unfinished, in: name) {
                    fits[position] = Fit(whole: true, offset: both.offset)
                    fits[position + 1] = both
                }
            }
            let found = fits.compactMap { $0 }
            guard !found.isEmpty else { continue }

            var setAside = 0
            if let letters = name.setAsideUnless, !query.letters.contains(letters) { setAside += 1 }
            if name.meatless, !words.contains("meatless") { setAside += 1 }

            let sizesFound = query.sizes.filter { size in
                name.words.contains { $0.text == size }
            }.count

            let isEveryday = fits[last] != nil && name.everyday.map { called in
                !called.isDisjoint(with: foodForms)
                    || called.contains { $0.hasPrefix(words[last]) }
            } == true

            let isHead = fits[last] != nil && name.head.map { head in
                !head.forms.isDisjoint(with: foodForms)
                    || (words[last].count >= 3 && head.text.hasPrefix(words[last]))
            } == true

            scored.append(Score(missing: words.count - found.count,
                                sizesMissing: query.sizes.count - sizesFound,
                                setAside: setAside,
                                startsOnly: found.filter { !$0.whole }.count,
                                notEveryday: isEveryday ? 0 : 1,
                                notHead: isHead ? 0 : 1,
                                place: found.reduce(0) { $0 + $1.offset } * 100 + name.length,
                                index: index))
        }

        let everyWord = scored.contains { $0.missing == 0 }
        if everyWord { scored.removeAll { $0.missing > 0 } }
        scored.sort()
        return (scored.prefix(limit).map(\.index), everyWord || scored.isEmpty)
    }

    /// Where `word` sits in the name: a whole word (any shared form), or --
    /// only for a word still being typed -- the start of one. A brand typed
    /// as one word ("chickfila") is the brand at the front of the name.
    private static func fit(_ word: String, forms: Set<String>, unfinished: Bool,
                            in name: FoodName) -> Fit? {
        var best: Fit?
        for candidate in name.words {
            let whole = !candidate.forms.isDisjoint(with: forms)
            guard whole || (unfinished && candidate.text.hasPrefix(word)) else { continue }
            if let current = best {
                if current.whole && !whole { continue }
                if current.whole == whole && current.offset <= candidate.offset { continue }
            }
            best = Fit(whole: whole, offset: candidate.offset)
        }
        if best?.whole != true, let brand = name.brand, brand.count > 3,
           brand == word || (unfinished && word.count >= 3 && brand.hasPrefix(word)) {
            best = Fit(whole: brand == word, offset: 0)
        }
        return best
    }
}
