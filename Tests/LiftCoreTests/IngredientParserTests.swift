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

    func testDisplayTextSurvivesAnOversizedQuantity() {
        // 1e20 equals its rounded self, so the old private formatter reached
        // `Int(1e20)` and trapped while the recipe list rendered.
        let huge = IngredientParser.parse("99999999999999999999 g oats", sortOrder: 0)
        XCTAssertEqual(huge.displayText, "1e+20 g oats")
        // Too many digits for a Double at all: show the person's own line.
        let line = String(repeating: "9", count: 400) + " g oats"
        XCTAssertEqual(IngredientParser.parse(line, sortOrder: 0).displayText, line)
    }

    /// The same cases and strings as `FormatTest` in dugcanlift-kit-android,
    /// so the two platforms print a quantity the same way.
    func testTrimmedMatchesAndroidTrimZeros() {
        let cases: [(Double, String)] = [
            (4, "4"), (2.5, "2.5"), (1.0 / 3, "0.333333"), (1.5, "1.5"),
            (0.1 + 0.2, "0.3"), (1e20, "1e+20"), (-2, "-2"), (1234567.5, "1.23457e+06"),
        ]
        for (value, expected) in cases {
            XCTAssertEqual(CookFormat.trimmed(value), expected, "\(value)")
        }
        XCTAssertEqual(IngredientParser.parse("1/3 cup flour", sortOrder: 0).displayText, "0.333333 cup flour")
    }

    // MARK: - Spelled-out units

    /// The case table for spelled-out units. The same lines and answers are in
    /// `IngredientParserTest` (dugcanlift-kit-android), `coach/parser.test.mjs`
    /// (dugcanlift-coach) and `lift/ingredient-parser.test.mjs`
    /// (dugcanlift-site): all four parsers must give the same answer.
    private static let spelledCases: [(line: String, qty: Double, unit: String, item: String)] = [
        ("1.5 pounds ground beef", 1.5, "lb", "ground beef"),
        ("2 Tablespoons olive oil", 2, "tbsp", "olive oil"),
        ("500 grams flour", 500, "g", "flour"),
        ("1 kilo potatoes", 1, "kg", "potatoes"),
        ("8 ounces cream cheese, softened", 8, "oz", "cream cheese, softened"),
        ("1 litre stock", 1, "l", "stock"),
        ("250 millilitres milk", 250, "ml", "milk"),
        ("3 Teaspoons. sea salt", 3, "tsp", "sea salt"),
        // The known cost of the rule, pinned on purpose: "pound cake" is read
        // as a pound of cake, exactly as "1 lb cake mix" already is.
        ("1 pound cake mix", 1, "lb", "cake mix"),
        ("1 lb cake mix", 1, "lb", "cake mix"),
        // Lines that parsed before are unchanged.
        ("2 eggs", 2, IngredientParser.countUnit, "eggs"),
        ("2 lbs chicken", 2, "lbs", "chicken"),
        ("1 1/2 cups flour", 1.5, "cups", "flour"),
    ]

    func testSpelledOutUnitsAreStoredAsTheirAbbreviation() throws {
        for c in Self.spelledCases {
            let parsed = IngredientParser.parse(c.line, sortOrder: 0)
            XCTAssertEqual(try XCTUnwrap(parsed.qty, c.line), c.qty, accuracy: 0.000001, c.line)
            XCTAssertEqual(parsed.unit, c.unit, c.line)
            XCTAssertEqual(parsed.item, c.item, c.line)
            XCTAssertEqual(parsed.rawText, c.line, c.line)
        }
    }

    func testSpelledOutWeightsAreCostedAndVolumesAreNot() throws {
        func grams(_ line: String) -> Double? {
            IngredientParser.grams(for: IngredientParser.parse(line, sortOrder: 0))
        }
        XCTAssertEqual(try XCTUnwrap(grams("1.5 pounds ground beef")), 680.388, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(grams("500 grams flour")), 500, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(grams("1 kilo potatoes")), 1000, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(grams("8 ounces cream cheese, softened")), 226.796, accuracy: 0.0001)
        XCTAssertEqual(IngredientParser.parse("500 grams flour", sortOrder: 0).grams, 500)
        XCTAssertNil(IngredientParser.parse("1.5 pounds ground beef", sortOrder: 0).grams,
                     "the stored grams field is for g only, as it is for lb")
        XCTAssertNil(grams("2 Tablespoons olive oil"), "a volume is never costed, spelled out or not")
        XCTAssertNil(grams("1 litre stock"))
        XCTAssertNil(grams("250 millilitres milk"))
    }

    func testEverySpelledOutWordMapsToItsAbbreviationInAnyCase() {
        let table: [(String, String)] = [
            ("gram", "g"), ("grams", "g"), ("gramme", "g"), ("grammes", "g"),
            ("kilogram", "kg"), ("kilograms", "kg"), ("kilogramme", "kg"), ("kilogrammes", "kg"),
            ("kilo", "kg"), ("kilos", "kg"),
            ("milligram", "mg"), ("milligrams", "mg"), ("milligramme", "mg"), ("milligrammes", "mg"),
            ("ounce", "oz"), ("ounces", "oz"),
            ("pound", "lb"), ("pounds", "lb"),
            ("teaspoon", "tsp"), ("teaspoons", "tsp"),
            ("tablespoon", "tbsp"), ("tablespoons", "tbsp"),
            ("milliliter", "ml"), ("milliliters", "ml"), ("millilitre", "ml"), ("millilitres", "ml"),
            ("liter", "l"), ("liters", "l"), ("litre", "l"), ("litres", "l"),
        ]
        for (word, abbreviation) in table {
            for spelling in [word, word.uppercased(), word.prefix(1).uppercased() + word.dropFirst()] {
                let line = "2 \(spelling), rice"
                let parsed = IngredientParser.parse(line, sortOrder: 0)
                XCTAssertEqual(parsed.unit, abbreviation, line)
                XCTAssertEqual(parsed.item, "rice", line)
            }
        }
    }

    func testAUnitWithNothingAfterItIsStillNotAnIngredient() {
        // "3 Teaspoons." alone names no ingredient, so it stays the raw line,
        // exactly as "3 tsp." does.
        for line in ["3 Teaspoons.", "3 tsp."] {
            let parsed = IngredientParser.parse(line, sortOrder: 0)
            XCTAssertNil(parsed.qty, line)
            XCTAssertNil(parsed.unit, line)
            XCTAssertNil(parsed.item, line)
        }
    }

    func testOutOfScopeUnitsAreStillCounts() {
        // fl oz, t/T, c., pt, qt and stick are not units here: each would need
        // a rule this change does not make, or a density.
        for line in ["2 t sugar", "2 T butter", "1 c. milk", "1 pt cream", "1 qt stock", "1 stick butter", "2 fl oz rum"] {
            XCTAssertEqual(IngredientParser.parse(line, sortOrder: 0).unit, IngredientParser.countUnit, line)
        }
    }

    func testAWordThatOnlyLooksLikeATableKeyIsNotAUnit() {
        // The web parsers keep the table in a plain object, whose prototype's
        // names must not read as units. Pinned here too so all four agree.
        for line in ["2 constructor bolts", "1 toString cake", "3 __proto__ things"] {
            XCTAssertEqual(IngredientParser.parse(line, sortOrder: 0).unit, IngredientParser.countUnit, line)
        }
    }

    // MARK: - Whitespace

    /// Every whitespace character in the line becomes a plain space before
    /// parsing: U+0009-U+000D, U+0020, U+00A0, U+1680, U+2000-U+200A, U+2028,
    /// U+2029, U+202F, U+205F, U+3000, U+FEFF. The same cases are in the other
    /// three parsers' suites.
    private static let whitespaceCases: [(line: String, qty: Double, unit: String, item: String)] = [
        ("1.5\u{00A0}pounds ground beef", 1.5, "lb", "ground beef"), // NBSP between number and unit
        ("2 cups\u{00A0}rice", 2, "cups", "rice"), // NBSP between unit and item
        ("1 lb\u{00A0}ground\u{00A0}beef", 1, "lb", "ground beef"), // the item comes out with plain spaces
        ("2\tcups rice", 2, "cups", "rice"), // tab between number and unit
        ("\t2 cups rice", 2, "cups", "rice"), // a leading tab
        ("250\u{202F}g flour", 250, "g", "flour"), // U+202F narrow no-break space
        ("1\u{00A0}1/2 cups flour", 1.5, "cups", "flour"), // "1 1/2" with an NBSP
        ("\u{FEFF}400 g chicken thigh", 400, "g", "chicken thigh"), // a byte-order mark
    ]

    private static let whitespaceSet: [UInt32] = [
        0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0xA0, 0x1680,
        0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200A,
        0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF,
    ]

    func testWhitespaceOfEveryKindSplitsWordsLikeASpace() {
        for c in Self.whitespaceCases {
            let parsed = IngredientParser.parse(c.line, sortOrder: 0)
            XCTAssertEqual(parsed.qty, c.qty, c.line.debugDescription)
            XCTAssertEqual(parsed.unit, c.unit, c.line.debugDescription)
            XCTAssertEqual(parsed.item, c.item, c.line.debugDescription)
        }
    }

    func testEveryCharacterInTheSetIsASpaceWhereverItFalls() throws {
        for code in Self.whitespaceSet {
            let ws = String(Character(try XCTUnwrap(Unicode.Scalar(code))))
            let hex = String(code, radix: 16)
            let parsed = IngredientParser.parse("\(ws)2\(ws)1/2\(ws)cups\(ws)basmati\(ws)rice\(ws)", sortOrder: 0)
            XCTAssertEqual(parsed.qty, 2.5, hex)
            XCTAssertEqual(parsed.unit, "cups", hex)
            XCTAssertEqual(parsed.item, "basmati rice", hex)
        }
    }

    func testACharacterOutsideTheSetIsNotASpace() {
        // U+200B zero-width space, U+001C file separator and U+0085 next line
        // are not in the set, so "cups" never becomes a unit through them.
        for ws in ["\u{200B}", "\u{001C}", "\u{0085}"] {
            let parsed = IngredientParser.parse("2\(ws)cups rice", sortOrder: 0)
            let hex = String(ws.unicodeScalars.first!.value, radix: 16)
            XCTAssertEqual(parsed.unit, IngredientParser.countUnit, hex)
            XCTAssertEqual(parsed.item, "\(ws)cups rice", hex)
        }
    }

    func testRawTextKeepsTheLineByteForByte() {
        let lines = Self.whitespaceCases.map(\.line) + ["\u{3000}salt\u{00A0}to taste\t"]
        for line in lines {
            XCTAssertEqual(Array(IngredientParser.parse(line, sortOrder: 0).rawText.utf8), Array(line.utf8),
                           line.debugDescription)
        }
    }
}
