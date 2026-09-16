import Foundation

/// Splits a pasted block of prose — a social caption, an email, a photo of a
/// card retyped — into a recipe's parts.
///
/// The counterpart to `RecipeJSONLD`, and deliberately much less ambitious.
/// JSON-LD is *labelled*: the publisher has already said which strings are
/// ingredients, so that reader can hand back a finished `ImportedRecipe` for
/// review. A caption is not labelled, so this only ever **proposes a split**,
/// and the screen that uses it is an editor rather than a review. Getting the
/// split wrong costs the reader an edit; it must never cost them a number.
///
/// That is the whole safety argument for this file. Nothing here invents a
/// quantity, a unit or a macro — `IngredientParser` still does the quantities,
/// on save, from whatever text the reader finally approved, and it still
/// refuses to guess. This decides only which lines to put in front of them.
///
/// ### Why this needs no parity copy
///
/// `IngredientParser`'s rules live in four places because a recipe written on
/// one client reaches the others through the wire format, and all four must
/// read a line the same way. This is an *input* path, not a wire format: what
/// it produces is indistinguishable from a hand-typed recipe the moment it is
/// saved. Android and web need no copy of it, and adding one would be four
/// times the surface for no shared contract.
public enum CaptionRecipe {

    // MARK: - Entry points

    /// Proposes a split of pasted text into name, ingredients and method.
    ///
    /// Never fails: text with no recognisable structure comes back
    /// `.unsorted` with every content line in `ingredientLines`, which is the
    /// honest answer and the one the editor can act on.
    public static func parse(_ text: String) -> ParsedCaption {
        let rows = text
            .split(whereSeparator: \.isNewline)
            .map { Row(String($0)) }
            .filter { !$0.isNoise }

        var ingredientsAt: Int?
        var methodAt: Int?
        for (index, row) in rows.enumerated() {
            switch row.heading {
            case .ingredients where ingredientsAt == nil: ingredientsAt = index
            case .method where methodAt == nil: methodAt = index
            default: break
            }
        }

        let servings = rows.compactMap { $0.statedServings }.first
        let name = title(of: rows)

        // Anything already spoken for by the header scan must not also be
        // offered as content -- the name line most of all, which is otherwise
        // the first "ingredient" of every unsorted paste.
        func content(_ slice: ArraySlice<Row>) -> [String] {
            slice.filter { $0.heading == nil && $0.statedServings == nil && $0.text != name }
                 .map(\.text)
        }

        let ingredientLines: [String]
        let steps: [String]
        let split: ParsedCaption.Split

        switch (ingredientsAt, methodAt) {
        case let (ingredients?, method?) where ingredients < method:
            ingredientLines = content(rows[(ingredients + 1) ..< method])
            steps = content(rows[(method + 1)...])
            split = .labelled

        case let (ingredients?, method?):
            // Method first. Rare, but some writers lead with the story and
            // list what to buy underneath, and the headers say so plainly.
            steps = content(rows[(method + 1) ..< ingredients])
            ingredientLines = content(rows[(ingredients + 1)...])
            split = .labelled

        case let (ingredients?, nil):
            ingredientLines = content(rows[(ingredients + 1)...])
            steps = []
            split = .inferred

        case let (nil, method?):
            // Everything above a method header is the shopping side of it.
            // That is an inference, so it is labelled as one.
            ingredientLines = content(rows[..<method])
            steps = content(rows[(method + 1)...])
            split = .inferred

        case (nil, nil):
            ingredientLines = content(rows[...])
            steps = []
            split = .unsorted
        }

        return ParsedCaption(
            name: name,
            ingredientLines: ingredientLines,
            steps: steps,
            servings: servings,
            split: split,
            sourceText: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Turns an edited text box back into lines.
    ///
    /// The save path, and the reason the editor can be two plain text boxes:
    /// the raw text is the contract and reparsing is how it stays one, the
    /// same rule `WebLibraryImporter` follows for an imported library rather
    /// than field-mapping what it was given.
    public static func lines(from text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { Row.strip(String($0)) }
            .filter { !$0.isEmpty }
    }

    // MARK: - The name

    /// The **first** line, and only that line, when it reads like a title.
    ///
    /// Scanning further down for "something titular" looks more generous and
    /// is strictly worse: in a caption that opens with a method heading it
    /// picks up the first instruction, and in an unstructured paste it picks
    /// up whichever line happens not to start with a number -- usually the
    /// method. A title being at the top is stated structure; a title being
    /// somewhere in the middle is a guess, and a wrong one takes a real line
    /// out of the recipe with it.
    private static func title(of rows: [Row]) -> String? {
        guard let first = rows.first,
              first.heading == nil,
              first.statedServings == nil,
              first.looksLikeTitle
        else { return nil }
        return first.text
    }
}

// MARK: - One line of the paste

private struct Row {
    let text: String
    let heading: Heading?
    let statedServings: Double?

    enum Heading { case ingredients, method }

    init(_ raw: String) {
        text = Self.strip(raw)
        let words = Self.significantWords(text)
        heading = Self.heading(words)
        statedServings = Self.servings(text, words)
    }

    /// Blank, or decoration with no words in it -- a row of emoji, a rule of
    /// dashes, a line of nothing but hashtags.
    var isNoise: Bool {
        if text.isEmpty { return true }
        let tokens = text.split(separator: " ")
        if !tokens.isEmpty && tokens.allSatisfy({ $0.hasPrefix("#") || $0.hasPrefix("@") }) {
            return true
        }
        return Self.significantWords(text).isEmpty
    }

    /// Short, wordy, and not opening with a quantity.
    ///
    /// The digit test is what keeps "2 chicken breasts" from being read as a
    /// dish called "2 chicken breasts" -- almost every ingredient line starts
    /// with its number, and almost no title does.
    var looksLikeTitle: Bool {
        guard let first = text.first, !first.isNumber else { return false }
        guard text.count <= 80 else { return false }
        return Self.significantWords(text).count <= 12
    }

    /// Removes bullets and leading list numbering, keeping the content.
    ///
    /// Formatting, not content, so taking it off is not a guess. The numbering
    /// strip requires whitespace after the separator, because "1.5 cups flour"
    /// otherwise loses its "1." and becomes five cups.
    static func strip(_ raw: String) -> String {
        var text = Substring(raw)

        func trimDecoration() {
            while let first = text.first,
                  first.isWhitespace || bullets.contains(first) || first.isDecorative {
                text = text.dropFirst()
            }
        }

        trimDecoration()

        let digits = text.prefix(while: \.isNumber)
        if !digits.isEmpty {
            let after = text.dropFirst(digits.count)
            if let separator = after.first, separator == "." || separator == ")",
               let following = after.dropFirst().first, following.isWhitespace {
                text = after.dropFirst()
                trimDecoration()
            }
        }

        return String(text).trimmingCharacters(in: .whitespaces)
    }

    private static let bullets: Set<Character> = [
        "-", "–", "—", "*", "•", "‣", "·", "▢", "☐", "□", "▪", "▫", "●", "○", "+", ">", "~"
    ]

    /// Letters only, lowercased, apostrophes dropped so "you'll" and "youll"
    /// are one word. Digits and punctuation are not words.
    static func significantWords(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && $0 != "'" && $0 != "\u{2019}" })
            .map { $0.replacingOccurrences(of: "'", with: "")
                     .replacingOccurrences(of: "\u{2019}", with: "") }
            .filter { !$0.isEmpty }
    }

    /// A heading is a short line that says nothing but its own name.
    ///
    /// Matched on the words alone, so "🛒 INGREDIENTS:" and "— Ingredients —"
    /// and "Ingredients 👇" are all the same heading.
    private static func heading(_ words: [String]) -> Heading? {
        guard !words.isEmpty, words.count <= 4 else { return nil }
        let phrase = words.joined(separator: " ")
        if ingredientHeadings.contains(phrase) { return .ingredients }
        if methodHeadings.contains(phrase) { return .method }
        return nil
    }

    private static let ingredientHeadings: Set<String> = [
        "ingredients", "ingredient", "the ingredients", "ingredients list",
        "ingredient list", "what you need", "what youll need", "what you will need",
        "youll need", "you will need", "you need", "shopping list", "grocery list",
        "what to buy", "for the recipe"
    ]

    private static let methodHeadings: Set<String> = [
        "method", "the method", "instructions", "instruction", "directions",
        "direction", "steps", "the steps", "how to", "how to make",
        "how to make it", "how to make this", "how i make it", "preparation",
        "lets make it", "lets go", "process", "to make"
    ]

    /// An explicitly stated yield, and nothing looser.
    ///
    /// The line must *open* with a yield word and carry a number. A bare "for
    /// 2" is not accepted, because "cook slowly with the ham bone for 2 hours"
    /// is a cooking time, and reading it as a yield halves every macro in the
    /// dish. A wrong serving count is silent and divides everything, so this
    /// is the strictest rule in the file.
    private static func servings(_ text: String, _ words: [String]) -> Double? {
        guard let opening = words.first, yieldWords.contains(opening) else { return nil }
        guard words.count <= 6 else { return nil }

        var rest = Substring(text)
        while !rest.isEmpty, !(rest.first?.isNumber ?? false) { rest = rest.dropFirst() }
        let digits = rest.prefix { $0.isNumber || $0 == "." }
        guard let value = Double(digits), value > 0, value <= 200 else { return nil }
        return value
    }

    private static let yieldWords: Set<String> = [
        "serves", "serving", "servings", "makes", "yield", "yields", "feeds", "portions"
    ]
}

private extension Character {
    /// Emoji and symbols used as decoration around a heading or a bullet.
    var isDecorative: Bool {
        guard !isLetter, !isNumber else { return false }
        return isSymbol || unicodeScalars.contains { $0.properties.isEmojiPresentation }
    }
}

// MARK: - The value it produces

/// A proposed split of pasted text, before the reader has approved any of it.
///
/// Not an `ImportedRecipe`, on purpose. That type means "this is what the
/// publisher said"; this one means "this is our best guess at what you
/// pasted", and `split` says how much of a guess it was. The editor turns one
/// into the other once the reader has looked.
public struct ParsedCaption: Equatable, Sendable {

    /// How much structure the text actually stated.
    public enum Split: Equatable, Sendable {
        /// Both headings found. The division is the writer's own.
        case labelled
        /// One heading found; the other side was taken from what was left.
        case inferred
        /// No headings. Every content line is in `ingredientLines`, and the
        /// method has to be cut out by hand.
        case unsorted
    }

    public var name: String?
    public var ingredientLines: [String]
    public var steps: [String]
    /// Only ever from an explicit "serves 4". nil is left as nil rather than
    /// defaulted to 1, so the editor can say the count is still unanswered.
    public var servings: Double?
    public var split: Split
    /// The paste verbatim, for `Recipe.sourceTranscript`. What a misread line
    /// is checked against afterwards.
    public var sourceText: String

    public init(name: String? = nil,
                ingredientLines: [String] = [],
                steps: [String] = [],
                servings: Double? = nil,
                split: Split = .unsorted,
                sourceText: String = "") {
        self.name = name
        self.ingredientLines = ingredientLines
        self.steps = steps
        self.servings = servings
        self.split = split
        self.sourceText = sourceText
    }

    /// True when there is nothing worth showing an editor.
    public var isEmpty: Bool { ingredientLines.isEmpty && steps.isEmpty }

    /// Hands the reader's approved version to the shared save path.
    ///
    /// Everything is passed in rather than read from `self`: by this point the
    /// reader has edited the boxes, and what they approved wins over what was
    /// parsed. `nutritionPerServing` is always nil — a caption states no
    /// macros this reads, so the costing pass fills the gap exactly as it does
    /// for a page that published none.
    public func imported(name: String,
                         ingredientLines: [String],
                         steps: [String],
                         servings: Double?) -> ImportedRecipe {
        ImportedRecipe(
            name: name,
            ingredientLines: ingredientLines,
            steps: steps,
            servings: servings,
            sourceTranscript: sourceText)
    }
}
