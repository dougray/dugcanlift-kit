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
/// being copied a fifth time into Coach. `data/ingredient-lines.json` is the
/// case table all four are checked against, and `data/README.md` has the
/// rules it was written from.
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

    /// The vulgar fractions read as quantities, as (numerator, denominator):
    /// the eighteen in Unicode that name a fraction, alone ("½ cup") or after
    /// a whole number with or without a space ("1½", "1 ½"). Not ⅟ (U+215F),
    /// which is half of a fraction, or ↉ (U+2189), zero thirds. The same
    /// eighteen are in all four parsers.
    private static let vulgarFractions: [Unicode.Scalar: (Double, Double)] = [
        "¼": (1, 4), "½": (1, 2), "¾": (3, 4),
        "⅐": (1, 7), "⅑": (1, 9), "⅒": (1, 10), "⅓": (1, 3), "⅔": (2, 3),
        "⅕": (1, 5), "⅖": (2, 5), "⅗": (3, 5), "⅘": (4, 5), "⅙": (1, 6), "⅚": (5, 6),
        "⅛": (1, 8), "⅜": (3, 8), "⅝": (5, 8), "⅞": (7, 8)
    ]

    /// The slash and U+2044 FRACTION SLASH, which reads as one.
    private static let slashes: Set<Unicode.Scalar> = ["/", "\u{2044}"]

    /// Characters that join a number to another one: `.`, `,`, and the dashes
    /// - ‐ ‑ ‒ – — − (U+002D, U+2010-U+2014, U+2212). See `endsCleanly`.
    private static let joiners: Set<Unicode.Scalar> = [
        ".", ",", "-", "\u{2010}", "\u{2011}", "\u{2012}", "\u{2013}", "\u{2014}", "\u{2212}"
    ]

    /// The punctuation trimmed from the end of a unit word, so "2 tbsp. oil",
    /// "2 tbsp: oil" and "1 cup; sugar" all read the unit. Only the end, and
    /// only these four: "(tbsp)", "tbsp)" and "tbsp-" are not units. The same
    /// four are in all four parsers.
    private static let unitTrailingPunctuation: Set<Unicode.Scalar> = [".", ",", ":", ";"]

    /// Unicode category N -- a digit, a vulgar fraction, a superscript, another
    /// script's digit -- read from the general category rather than
    /// `Character.isNumber`, which also counts Han numerals, so that it is the
    /// same set JavaScript's `\p{N}` and Kotlin's `Character.getType` read.
    private static func isNumberCharacter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .decimalNumber, .letterNumber, .otherNumber: return true
        default: return false
        }
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
        // Scalars, not Characters, throughout: JavaScript and Kotlin read code
        // units, and a combining mark after a space must not glue the two
        // into one Character here and nowhere else.
        let line = Array(normalizingWhitespace(raw).unicodeScalars)
        var rest = line.drop(while: { $0 == " " })

        guard let quantity = takeQuantity(&rest) else {
            return RecipeIngredient(rawText: raw, sortOrder: sortOrder)
        }

        var unit: String?
        let firstWord = rest.prefix(while: { $0 != " " })
        var trimmed = firstWord
        while let last = trimmed.last, unitTrailingPunctuation.contains(last) { trimmed = trimmed.dropLast() }
        let candidate = string(trimmed).lowercased()
        if let known = units.contains(candidate) ? candidate : spelledUnits[candidate] {
            unit = known
            rest = rest.dropFirst(firstWord.count)
        }

        // Plain spaces only: the line is already normalized, and Foundation's
        // `.whitespaces` would also strip U+200B, which no other parser does.
        let item = string(rest).trimmingCharacters(in: [" "])
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

    private typealias Scalars = ArraySlice<Unicode.Scalar>

    private static func string(_ scalars: Scalars) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }

    /// Reads the quantity off the front of a normalized line with no leading
    /// spaces, leaving `text` at the rest of the line (leading spaces
    /// dropped), or returns nil to give up on the line. A quantity is a
    /// decimal ("2", "1.5", "1.", ".5"; ASCII digits and at most one point), a
    /// fraction of whole numbers ("1/2", the fraction slash U+2044 read as
    /// "/"), a whole number then spaces then a fraction ("1 1/2"), or a vulgar
    /// fraction, alone or after a whole number ("½", "1½", "1 ½"). Every number
    /// in it must be finite and a denominator must not be zero.
    private static func takeQuantity(_ text: inout Scalars) -> Double? {
        func digits(_ s: Scalars) -> Scalars { s.prefix(while: { ("0"..."9").contains($0) }) }
        // A run of digits as a number, or nil when it is too long to be finite.
        func number(_ run: Scalars) -> Double? {
            guard let value = Double(string(run)), value.isFinite else { return nil }
            return value
        }
        func vulgar(_ s: Scalars) -> Double? {
            guard let first = s.first, let (n, d) = vulgarFractions[first] else { return nil }
            return n / d
        }
        // "/" or U+2044 and a nonzero whole denominator, consumed only if all there.
        func takeDenominator(_ s: inout Scalars) -> Double? {
            guard let first = s.first, slashes.contains(first) else { return nil }
            let run = digits(s.dropFirst())
            guard !run.isEmpty, let d = number(run), d != 0 else { return nil }
            s = s.dropFirst(1 + run.count)
            return d
        }

        var s = text
        var value: Double
        if let lead = vulgar(s) {
            s = s.dropFirst()
            value = lead
        } else {
            let run = s.prefix(while: { ("0"..."9").contains($0) || $0 == "." })
            guard !run.isEmpty else { return nil }
            s = s.dropFirst(run.count)
            if run.contains(".") {
                // One point at most, and at least one digit: "1.2.3" and "."
                // are not numbers.
                guard run.filter({ $0 == "." }).count == 1, run.count > 1,
                      let decimal = number(run) else { return nil }
                value = decimal
            } else {
                guard let whole = number(run) else { return nil }
                value = whole
                if let denominator = takeDenominator(&s) {
                    value /= denominator
                } else if let fraction = vulgar(s) {
                    s = s.dropFirst()
                    value += fraction
                } else if s.first == " " {
                    // "1 1/2" or "1 ½" — a whole number, spaces, then a fraction.
                    var after = s.drop(while: { $0 == " " })
                    if let fraction = vulgar(after) {
                        s = after.dropFirst()
                        value += fraction
                    } else {
                        let numerator = digits(after)
                        if !numerator.isEmpty, let n = number(numerator) {
                            after = after.dropFirst(numerator.count)
                            if let denominator = takeDenominator(&after) {
                                s = after
                                value += n / denominator
                            }
                        }
                    }
                }
            }
        }

        guard value.isFinite, endsCleanly(s) else { return nil }
        text = s.drop(while: { $0 == " " })
        return value
    }

    /// Whether a quantity may end where `rest` begins. Not when the next
    /// character after any spaces is a number character or a slash, or is one
    /// of `joiners` followed, after any spaces, by a number character: "1 2
    /// eggs", "1,5 kg", "1,000 g", "1-2 cups", "1/2/3", "2² cups". Each of
    /// those is a number this parser cannot read, and stopping short of it
    /// would be a confident wrong quantity. A dash before a letter is fine:
    /// "1/2-inch piece ginger".
    private static func endsCleanly(_ rest: Scalars) -> Bool {
        let next = rest.drop(while: { $0 == " " })
        guard let c = next.first else { return true }
        if isNumberCharacter(c) || slashes.contains(c) { return false }
        if joiners.contains(c), let after = next.dropFirst().drop(while: { $0 == " " }).first,
           isNumberCharacter(after) { return false }
        return true
    }
}
