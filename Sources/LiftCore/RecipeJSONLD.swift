import Foundation

/// Reads a recipe out of a web page's schema.org JSON-LD block.
///
/// Almost every recipe site publishes one, because Google requires it for a
/// rich result. That makes it the one import path that does not involve
/// scraping a layout: the publisher has already labelled the ingredients and
/// the steps, and we read the labels rather than guessing at markup.
///
/// Pure Foundation on purpose. `LiftCore` carries no GRDB and no networking —
/// the widget extension links it — so this takes a `String` of already-fetched
/// HTML and hands back a value type. Fetching the URL is the app target's job,
/// and resolving an ingredient to macros stays in `LiftReference`.
///
/// The parse follows the same rule as `IngredientParser`: read what is plainly
/// stated, leave `nil` for everything else. A publisher's nutrition block is a
/// claim, not a measurement, so it arrives flagged as estimated and nothing
/// here is ever auto-logged — see `Recipe.sourceTranscript`.
///
/// Parity note: LIFT's Android and web builds will need the same reader before
/// an imported recipe can travel between clients through the wire format at
/// `homelab/cook-ingest/schema/recipe.schema.json`. The field mapping below is
/// the contract those copies must match.
public enum RecipeJSONLD {

    // MARK: - Entry points

    /// Pulls the first schema.org Recipe out of a fetched HTML page.
    ///
    /// Returns nil when the page publishes no JSON-LD, or publishes some that
    /// contains no Recipe. Both are ordinary outcomes for a page that is not a
    /// recipe, not errors worth surfacing.
    public static func recipe(fromHTML html: String) -> ImportedRecipe? {
        for block in jsonLDBlocks(in: html) {
            if let found = recipe(fromJSON: block) { return found }
        }
        return nil
    }

    /// Parses one JSON-LD payload that has already been isolated.
    ///
    /// Separate from the HTML entry point so a caller holding JSON from an API
    /// — or a test holding a fixture — does not have to wrap it in a fake page.
    public static func recipe(fromJSON json: String) -> ImportedRecipe? {
        guard let data = json.data(using: .utf8),
              let any = try? JSONSerialization.jsonObject(with: data),
              let node = findRecipeNode(any)
        else { return nil }
        return build(from: node, transcript: json)
    }

    // MARK: - Locating the Recipe node

    /// Finds the Recipe object inside a payload of any of the shapes sites use.
    ///
    /// Publishers wrap it three common ways: the bare object, a top-level
    /// array of objects, and an `@graph` array holding the page's whole entity
    /// set. Walking all three costs a few lines and removes a whole class of
    /// "works on one blog, not the next".
    private static func findRecipeNode(_ any: Any) -> [String: Any]? {
        if let array = any as? [Any] {
            for element in array {
                if let found = findRecipeNode(element) { return found }
            }
            return nil
        }

        guard let object = any as? [String: Any] else { return nil }

        if isRecipe(object) { return object }

        if let graph = object["@graph"] {
            return findRecipeNode(graph)
        }
        return nil
    }

    /// `@type` is a string on most pages and an array on the ones that also
    /// declare the page an Article, so both are accepted.
    private static func isRecipe(_ object: [String: Any]) -> Bool {
        let type = object["@type"]
        if let single = type as? String { return single.caseInsensitiveCompare("Recipe") == .orderedSame }
        if let many = type as? [Any] {
            return many.contains { ($0 as? String)?.caseInsensitiveCompare("Recipe") == .orderedSame }
        }
        return false
    }

    // MARK: - Field mapping

    private static func build(from node: [String: Any], transcript: String) -> ImportedRecipe? {
        // A recipe with no name is not one we can show in a list, and every
        // real page has one. Bailing here keeps a half-read blob from
        // reaching the editor as an untitled recipe.
        guard let name = text(node["name"]), !name.isEmpty else { return nil }

        return ImportedRecipe(
            name: name,
            ingredientLines: ingredientLines(node),
            steps: steps(node["recipeInstructions"]),
            servings: servings(node["recipeYield"]),
            prepMinutes: minutes(node["prepTime"]),
            cookMinutes: minutes(node["cookTime"]),
            author: author(node["author"]),
            nutritionPerServing: nutrition(node["nutrition"]),
            sourceTranscript: transcript
        )
    }

    /// `recipeIngredient` is the current property; `ingredients` is the
    /// pre-2017 spelling still emitted by older plugins.
    private static func ingredientLines(_ node: [String: Any]) -> [String] {
        let raw = node["recipeIngredient"] ?? node["ingredients"]
        return stringList(raw)
    }

    /// Instructions arrive as a paragraph, a list of strings, a list of
    /// `HowToStep` objects, or `HowToSection`s holding those steps.
    ///
    /// A single paragraph is split on newlines only. Splitting on sentences
    /// would cut "Bake at 200 C. for 20 minutes" in half, and a step that is
    /// too long is a great deal easier for the reader to fix than a step that
    /// has been quietly cut in two.
    private static func steps(_ any: Any?) -> [String] {
        guard let any else { return [] }

        if let single = any as? String {
            return clean(single)
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }

        if let array = any as? [Any] {
            return array.flatMap { element -> [String] in
                if let string = element as? String {
                    let cleaned = clean(string)
                    return cleaned.isEmpty ? [] : [cleaned]
                }
                guard let object = element as? [String: Any] else { return [] }
                // A section holds its own steps under itemListElement.
                if let nested = object["itemListElement"] {
                    return steps(nested)
                }
                if let step = text(object["text"]) ?? text(object["name"]) {
                    return step.isEmpty ? [] : [step]
                }
                return []
            }
        }

        if let object = any as? [String: Any] {
            return steps(object["itemListElement"] ?? object["text"])
        }
        return []
    }

    /// `recipeYield` is "4", "4 servings", "Serves 4" or a bare number.
    ///
    /// The first number in the string wins. A yield with no number at all
    /// ("1 loaf" parses, "a crowd" does not) stays nil rather than defaulting
    /// to 1, so the editor can ask instead of inventing a serving count that
    /// every macro on the recipe would then be divided by.
    private static func servings(_ any: Any?) -> Double? {
        guard let any else { return nil }
        if let value = numeric(any) {
            return value > 0 ? value : nil
        }
        let candidate: String?
        if let string = any as? String {
            candidate = string
        } else if let array = any as? [Any] {
            candidate = array.compactMap { text($0) }.first
        } else {
            candidate = nil
        }
        guard let candidate, let value = firstNumber(in: candidate), value > 0 else { return nil }
        return value
    }

    /// ISO 8601 durations, the only form schema.org allows for these — "PT30M",
    /// "PT1H15M", occasionally "P0DT0H30M".
    ///
    /// Written out rather than handed to a formatter so the result is the same
    /// on every OS version the two apps still support, and so the Android and
    /// web copies have something unambiguous to match.
    private static func minutes(_ any: Any?) -> Int? {
        guard let raw = text(any), !raw.isEmpty else { return nil }

        var scanning = Substring(raw.uppercased())
        guard scanning.first == "P" else { return nil }
        scanning = scanning.dropFirst()

        var inTimeSection = false
        var digits = ""
        var totalMinutes = 0
        var sawAnything = false

        for character in scanning {
            if character == "T" {
                inTimeSection = true
                digits = ""
                continue
            }
            if character.isNumber {
                digits.append(character)
                continue
            }
            guard let value = Int(digits) else { digits = ""; continue }
            switch character {
            case "D": totalMinutes += value * 24 * 60; sawAnything = true
            case "H" where inTimeSection: totalMinutes += value * 60; sawAnything = true
            case "M" where inTimeSection: totalMinutes += value; sawAnything = true
            // A leading "M" outside the time section is months. Nothing sane
            // publishes a recipe in months, and treating it as minutes would
            // be a silent 30-fold error, so it is ignored.
            default: break
            }
            digits = ""
        }
        return sawAnything ? totalMinutes : nil
    }

    /// `author` is a string, a Person object, or a list of either.
    private static func author(_ any: Any?) -> String? {
        guard let any else { return nil }
        if let string = text(any), !string.isEmpty { return string }
        if let object = any as? [String: Any] { return text(object["name"]) }
        if let array = any as? [Any] {
            for element in array {
                if let found = author(element), !found.isEmpty { return found }
            }
        }
        return nil
    }

    /// schema.org states NutritionInformation is per serving, which is the same
    /// contract `Recipe.nutritionPerServing` already holds — so this maps
    /// straight across with no scaling.
    ///
    /// Values arrive as strings with units attached ("350 calories", "12 g").
    /// Only the number is read. Calories are required: a block with no energy
    /// value is not worth carrying, because every screen that shows macros
    /// leads with calories.
    private static func nutrition(_ any: Any?) -> NutritionFacts? {
        guard let object = any as? [String: Any] else { return nil }
        guard let calories = quantity(object["calories"]) else { return nil }

        return NutritionFacts(
            calories: calories,
            proteinG: quantity(object["proteinContent"]) ?? 0,
            carbsG: quantity(object["carbohydrateContent"]) ?? 0,
            fatG: quantity(object["fatContent"]) ?? 0,
            fiberG: quantity(object["fiberContent"]),
            sugarG: quantity(object["sugarContent"]),
            sodiumMg: sodiumMilligrams(object["sodiumContent"])
        )
    }

    /// Sodium is the one field published in two units — "320 mg" on most sites,
    /// "0.32 g" on a few European ones. A gram value read as milligrams would
    /// be wrong by a thousand, so the unit is checked rather than assumed.
    private static func sodiumMilligrams(_ any: Any?) -> Double? {
        guard let raw = text(any), let value = firstNumber(in: raw) else { return nil }
        let lowered = raw.lowercased()
        if lowered.contains("mg") { return value }
        if lowered.contains("g") { return value * 1000 }
        return value
    }

    private static func quantity(_ any: Any?) -> Double? {
        if let value = numeric(any) { return value }
        guard let raw = text(any) else { return nil }
        return firstNumber(in: raw)
    }

    /// `JSONSerialization` returns `true`/`false` as `NSNumber` as well as real
    /// numbers, so a stray `"recipeYield": true` would otherwise read as 1.
    /// A boolean is not a quantity; it is rejected rather than coerced.
    private static func numeric(_ any: Any?) -> Double? {
        guard let number = any as? NSNumber else { return nil }
        guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number.doubleValue
    }

    // MARK: - Small shared helpers

    /// Strings and numbers both reach here, because a publisher may emit
    /// `"recipeYield": 4` or `"recipeYield": "4"` for the same dish.
    private static func text(_ any: Any?) -> String? {
        if let string = any as? String { return clean(string) }
        if let value = numeric(any) { return CookFormat.trimmed(value) }
        return nil
    }

    private static func stringList(_ any: Any?) -> [String] {
        guard let any else { return [] }
        if let string = text(any) { return string.isEmpty ? [] : [string] }
        if let array = any as? [Any] {
            return array.compactMap { text($0) }.filter { !$0.isEmpty }
        }
        return []
    }

    /// First run of digits, with an optional decimal part.
    ///
    /// Commas are stripped first so "1,200 calories" reads as 1200 rather than
    /// stopping at 1. A comma used as a decimal separator would be misread, but
    /// JSON-LD nutrition is overwhelmingly written in English-locale numerals
    /// and reading "1,5 g" as 15 is the same class of confident-wrong answer
    /// `IngredientParser` refuses to produce elsewhere — so it is left alone.
    private static func firstNumber(in string: String) -> Double? {
        let stripped = string.replacingOccurrences(of: ",", with: "")
        var digits = ""
        var sawDot = false
        for character in stripped {
            if character.isNumber {
                digits.append(character)
            } else if character == "." && !digits.isEmpty && !sawDot {
                sawDot = true
                digits.append(character)
            } else if !digits.isEmpty {
                break
            }
        }
        if digits.hasSuffix(".") { digits.removeLast() }
        return digits.isEmpty ? nil : Double(digits)
    }

    /// Publishers put markup inside JSON-LD string values more often than the
    /// spec would suggest — `<p>` around a step, `&amp;` in a title.
    private static func clean(_ string: String) -> String {
        stripTags(string)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripTags(_ string: String) -> String {
        guard string.contains("<") else { return string }
        var output = ""
        var insideTag = false
        for character in string {
            switch character {
            case "<": insideTag = true
            case ">": insideTag = false
            default: if !insideTag { output.append(character) }
            }
        }
        return output
    }

    // MARK: - Finding the blocks in a page

    /// Every `<script type="application/ld+json">` body on the page, in order.
    ///
    /// Attribute order and quoting vary by CMS, so the opening tag is matched
    /// loosely: a `<script` whose attributes mention the JSON-LD media type.
    private static func jsonLDBlocks(in html: String) -> [String] {
        var blocks: [String] = []
        var cursor = html.startIndex

        while let openStart = html.range(of: "<script", options: [.caseInsensitive], range: cursor ..< html.endIndex) {
            guard let openEnd = html.range(of: ">", range: openStart.upperBound ..< html.endIndex) else { break }

            let attributes = html[openStart.upperBound ..< openEnd.lowerBound].lowercased()
            guard let closeRange = html.range(of: "</script", options: [.caseInsensitive], range: openEnd.upperBound ..< html.endIndex) else {
                cursor = openEnd.upperBound
                continue
            }

            if attributes.contains("application/ld+json") {
                let body = html[openEnd.upperBound ..< closeRange.lowerBound]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !body.isEmpty { blocks.append(body) }
            }
            cursor = closeRange.upperBound
        }
        return blocks
    }
}

// MARK: - The value it produces

/// One recipe read off a page, before any of it has been accepted.
///
/// A value type, never persisted — the same split `ShoppingListLine` uses.
/// Nothing here is written to the store until `makeRecipe` is called and the
/// caller inserts the result, which keeps the review step in
/// `Recipe.sourceTranscript`'s doc comment honest: an import is shown next to
/// its source text before it is saved.
public struct ImportedRecipe: Equatable, Sendable {
    public var name: String
    /// Raw lines, exactly as published. Parsing happens in `makeRecipe` so the
    /// unparsed text survives for the reviewer either way.
    public var ingredientLines: [String]
    public var steps: [String]
    /// nil when the page never said, rather than a guessed 1.
    public var servings: Double?
    public var prepMinutes: Int?
    public var cookMinutes: Int?
    public var author: String?
    /// Per serving, as schema.org defines it. The publisher's claim.
    public var nutritionPerServing: NutritionFacts?
    /// The JSON-LD block verbatim, kept for the review screen.
    public var sourceTranscript: String

    public init(name: String,
                ingredientLines: [String] = [],
                steps: [String] = [],
                servings: Double? = nil,
                prepMinutes: Int? = nil,
                cookMinutes: Int? = nil,
                author: String? = nil,
                nutritionPerServing: NutritionFacts? = nil,
                sourceTranscript: String = "") {
        self.name = name
        self.ingredientLines = ingredientLines
        self.steps = steps
        self.servings = servings
        self.prepMinutes = prepMinutes
        self.cookMinutes = cookMinutes
        self.author = author
        self.nutritionPerServing = nutritionPerServing
        self.sourceTranscript = sourceTranscript
    }

    /// Builds the model graph for this import.
    ///
    /// Returns the ingredients alongside the recipe rather than only hanging
    /// them off it: SwiftData needs each one inserted into the context, and
    /// `CookSampleData` already follows this shape. The caller inserts both,
    /// then sets the relationship.
    ///
    /// `nutritionIsEstimated` is always true for an import. The number came
    /// from the publisher, not from resolving ingredients against the food
    /// database, and that flag is what the UI shows before anything is logged.
    public func makeRecipe(sourceURL: URL?) -> (recipe: Recipe, ingredients: [RecipeIngredient]) {
        let recipe = Recipe(
            name: name,
            servings: servings ?? 1,
            steps: steps,
            sourceURL: sourceURL,
            sourceAuthor: author,
            nutritionPerServing: nutritionPerServing,
            nutritionIsEstimated: nutritionPerServing != nil,
            sourceTranscript: sourceTranscript
        )
        recipe.prepMinutes = prepMinutes
        recipe.cookMinutes = cookMinutes

        let ingredients = ingredientLines.enumerated().map { index, line in
            IngredientParser.parse(line, sortOrder: index)
        }
        return (recipe, ingredients)
    }
}
