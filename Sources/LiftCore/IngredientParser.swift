import Foundation

/// Pulls a quantity and unit off the front of an ingredient line.
///
/// Deliberately small. It handles the shapes people actually type and gives up
/// cleanly on everything else, leaving `item` nil so the shopping list shows
/// the raw line instead. Guessing harder here would produce confident wrong
/// quantities, which is worse than an unparsed line the reader can see.
///
/// These rules exist in four places — here, `coach/parser.js`, and the Android
/// and web builds of LIFT — and all four must give the same answer for the
/// same line, because a recipe written on one client reaches the others
/// through the shared wire format. This copy is the one the two iOS apps
/// share; it moved here from LIFT iOS's app target on 2026-09-12 rather than
/// being copied a fifth time into Coach.
public enum IngredientParser {

    /// Grouping key for an ingredient with no unit — "2 eggs", "1 banana".
    ///
    /// A sentinel, not a unit. It keeps counts in their own bucket during
    /// aggregation, and the shopping list drops it when printing, because
    /// "2 x banana" is not how anyone writes a shopping list. Byte-identical
    /// to `parser.js`'s `COUNT_UNIT`; it contains a NUL so it can never
    /// collide with something typed.
    public static let countUnit = "\u{0000}count"

    private static let units: Set<String> = [
        "g", "kg", "mg", "ml", "l",
        "tsp", "tbsp", "cup", "cups", "oz", "lb", "lbs",
        "clove", "cloves", "slice", "slices", "scoop", "scoops",
        "can", "cans", "pinch", "handful"
    ]

    /// Unit words spelled out, as US recipe sites write them ("1.5 pounds
    /// ground beef"), each stored as the abbreviation above. Storing the
    /// abbreviation is the whole design: costing, shopping-list grouping and
    /// the count sentinel already key on it, so a spelled-out line behaves
    /// exactly like its abbreviated twin and nothing downstream changes.
    ///
    /// The same table, word for word, is in `coach/parser.js`, LIFT web's
    /// `app.js` and the Android kit's `IngredientParser.kt`. Deliberately not
    /// here: `fl oz`, a bare `t` or `T`, `c.`, `pt`, `qt`, `stick`, or
    /// anything that needs a density.
    private static let spelledUnits: [String: String] = [
        "gram": "g", "grams": "g", "gramme": "g", "grammes": "g",
        "kilogram": "kg", "kilograms": "kg", "kilogramme": "kg", "kilogrammes": "kg",
        "kilo": "kg", "kilos": "kg",
        "milligram": "mg", "milligrams": "mg", "milligramme": "mg", "milligrammes": "mg",
        "ounce": "oz", "ounces": "oz",
        "pound": "lb", "pounds": "lb",
        "teaspoon": "tsp", "teaspoons": "tsp",
        "tablespoon": "tbsp", "tablespoons": "tbsp",
        "milliliter": "ml", "milliliters": "ml", "millilitre": "ml", "millilitres": "ml",
        "liter": "l", "liters": "l", "litre": "l", "litres": "l"
    ]

    /// Every whitespace character, written out rather than left to the
    /// platform's idea of whitespace: U+0009-U+000D, U+0020, U+00A0, U+1680,
    /// U+2000-U+200A, U+2028, U+2029, U+202F, U+205F, U+3000, U+FEFF
    /// (JavaScript's `\s`). Before parsing, each one becomes a plain space, so
    /// a non-breaking space or a tab pasted from a recipe page splits words
    /// like a space does. `rawText` keeps the line as it was. The same set,
    /// character for character, is in all four parsers.
    private static let whitespace: Set<UInt32> = {
        var set: Set<UInt32> = [0x20, 0xA0, 0x1680, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF]
        set.formUnion(0x09...0x0D)
        set.formUnion(0x2000...0x200A)
        return set
    }()

    /// The line with every character in `whitespace` replaced by U+0020.
    static func normalizingWhitespace(_ raw: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in raw.unicodeScalars {
            scalars.append(whitespace.contains(scalar.value) ? " " : scalar)
        }
        return String(scalars)
    }

    /// Grams for the units that convert to a weight without guessing.
    ///
    /// Volume and vague units are deliberately absent. A tablespoon of oil and
    /// a tablespoon of flour are not the same mass, and "a handful" is not a
    /// measurement — costing them would mean inventing densities, and a
    /// confident wrong calorie count is worse than an obvious gap.
    private static let gramsPerUnit: [String: Double] = [
        "g": 1, "kg": 1000, "mg": 0.001, "oz": 28.3495, "lb": 453.592, "lbs": 453.592
    ]

    public static func parse(_ raw: String, sortOrder: Int) -> RecipeIngredient {
        let line = normalizingWhitespace(raw)
        var rest = line[...]
        let quantity = takeQuantity(&rest)

        guard let quantity else {
            return RecipeIngredient(rawText: raw, sortOrder: sortOrder)
        }

        var unit: String?
        let words = rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        if let first = words.first {
            let candidate = String(first).lowercased().trimmingCharacters(in: .punctuationCharacters)
            if let known = units.contains(candidate) ? candidate : spelledUnits[candidate] {
                unit = known
                rest = words.count > 1 ? words[1] : ""[...]
            }
        }

        // Plain spaces only: the line is already normalized, and Foundation's
        // `.whitespaces` would also strip U+200B, which no other parser does.
        let item = rest.trimmingCharacters(in: [" "])
        guard !item.isEmpty else {
            return RecipeIngredient(rawText: raw, sortOrder: sortOrder)
        }

        return RecipeIngredient(
            rawText: raw,
            item: item,
            qty: quantity,
            // No unit means a count — "2 eggs". It still needs a key, so that
            // two eggs are never added to two cups of anything, but it is not
            // a unit and must never be printed as one. See `countUnit`.
            unit: unit ?? countUnit,
            grams: unit == "g" ? quantity : nil,
            sortOrder: sortOrder
        )
    }

    /// The weight this ingredient represents, when one can be had without
    /// guessing. `nil` for volume, counts, and anything that did not parse —
    /// and a `nil` here must be surfaced to the person, never treated as zero.
    public static func grams(for ingredient: RecipeIngredient) -> Double? {
        guard let qty = ingredient.qty,
              let unit = ingredient.unit,
              let factor = gramsPerUnit[unit] else { return nil }
        return qty * factor
    }

    /// Reads a leading number, including "1/2" and "1 1/2".
    private static func takeQuantity(_ text: inout Substring) -> Double? {
        text = text.drop(while: { $0 == " " })[...]

        func takeNumber() -> Double? {
            let digits = text.prefix { $0.isNumber || $0 == "." }
            guard !digits.isEmpty, let value = Double(digits) else { return nil }
            text = text.dropFirst(digits.count)
            return value
        }

        guard var value = takeNumber() else { return nil }

        if text.first == "/" {
            text = text.dropFirst()
            guard let denominator = takeNumber(), denominator != 0 else { return nil }
            value /= denominator
        } else if text.first == " " {
            // "1 1/2" — a whole number followed by a fraction.
            let save = text
            text = text.dropFirst()
            if let whole = takeNumber(), text.first == "/" {
                text = text.dropFirst()
                if let denominator = takeNumber(), denominator != 0 {
                    value += whole / denominator
                } else {
                    text = save
                }
            } else {
                text = save
            }
        }

        text = text.drop(while: { $0 == " " })[...]
        return value
    }
}
