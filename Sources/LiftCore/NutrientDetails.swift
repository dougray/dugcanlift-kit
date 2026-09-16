import Foundation

// MARK: - Saturated fat, sugar and sodium on the wire
//
// SHARE-FORMAT.md "Saturated fat, sugar and sodium" and PLAN-FORMAT.md `ux`.
// Tracked and shown, never targeted: there is no goal for any of them. They
// travel in keys of their own (`fx`, `fe`, `ux`) rather than as extra
// positions in `ft`, `f` or `u`, because decoders already in use read those
// tuples by position and length.
//
// Names and rules match LIFT Android's kit (`NutrientDetails`,
// `ShareNutrientTotals`, `ShareNutrients`), so a sender on either platform
// produces the same numbers.

/// `[saturatedFatG, sugarG, sodiumMg]`, **per serving** — one `fe` entry on an
/// itemized share-link day, or a plan recipe's `ux`.
///
/// Encodes with trailing nulls trimmed (`[null, 12]` is sugar only) but never a
/// leading one, or sugar would slide into the saturated-fat slot. Decoding reads
/// a short tuple's missing slots as nil and ignores any slot past the third, so
/// a later addition does not break this reader.
///
/// An instance with all three nil is legal in memory; `ShareNutrients.itemRow`
/// is how a sender gets one that is rounded and nil when empty.
public struct WireNutrientDetails: Codable, Equatable, Hashable, Sendable {
    public var saturatedFatG: Double?
    public var sugarG: Double?
    public var sodiumMg: Double?

    public init(saturatedFatG: Double? = nil, sugarG: Double? = nil, sodiumMg: Double? = nil) {
        self.saturatedFatG = saturatedFatG
        self.sugarG = sugarG
        self.sodiumMg = sodiumMg
    }

    /// The three values `facts` carries, unrounded. Pass per-serving facts.
    public init(_ facts: NutritionFacts) {
        self.init(saturatedFatG: facts.saturatedFatG, sugarG: facts.sugarG, sodiumMg: facts.sodiumMg)
    }

    /// True when none of the three is known.
    public var isEmpty: Bool { saturatedFatG == nil && sugarG == nil && sodiumMg == nil }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var values: [Double?] = []
        while values.count < 3, !container.isAtEnd {
            if try container.decodeNil() {
                values.append(nil)
            } else {
                values.append(try container.decode(Double.self))
            }
        }
        while values.count < 3 { values.append(nil) }
        saturatedFatG = values[0]
        sugarG = values[1]
        sodiumMg = values[2]
    }

    public func encode(to encoder: Encoder) throws {
        var values = [saturatedFatG, sugarG, sodiumMg]
        while let last = values.last, last == nil { values.removeLast() }
        var container = encoder.unkeyedContainer()
        for value in values {
            if let value { try container.encode(value) } else { try container.encodeNil() }
        }
    }
}

/// A share-link day's `fx`:
/// `[saturatedFatG, sugarG, sodiumMg, foods, withSaturatedFat, withSugar, withSodium]`.
///
/// Each total covers only the foods that recorded it, multiplied by servings as
/// `ft` is. `foods` is every food logged that day and the `with*` counts say how
/// many of them each total covers — so *2,310 mg from 2 of 6 foods* reads as a
/// floor, not a day. A total with no food behind it is nil, never 0. Build one
/// with `ShareNutrients.dayTotals(_:)`.
public struct WireNutrientTotals: Codable, Equatable, Hashable, Sendable {
    public var saturatedFatG: Double?
    public var sugarG: Double?
    public var sodiumMg: Double?
    public var foods: Int
    public var withSaturatedFat: Int
    public var withSugar: Int
    public var withSodium: Int

    public init(saturatedFatG: Double?, sugarG: Double?, sodiumMg: Double?,
                foods: Int, withSaturatedFat: Int, withSugar: Int, withSodium: Int) {
        self.saturatedFatG = saturatedFatG
        self.sugarG = sugarG
        self.sodiumMg = sodiumMg
        self.foods = foods
        self.withSaturatedFat = withSaturatedFat
        self.withSugar = withSugar
        self.withSodium = withSodium
    }

    /// Strict: all seven positions must be present, the three totals a number or
    /// null, the four counts whole numbers. `WireDay` turns a failure here into a
    /// nil `fx`, never a lost day.
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        saturatedFatG = try container.decodeIfPresent(Double.self)
        sugarG = try container.decodeIfPresent(Double.self)
        sodiumMg = try container.decodeIfPresent(Double.self)
        foods = try container.decode(Int.self)
        withSaturatedFat = try container.decode(Int.self)
        withSugar = try container.decode(Int.self)
        withSodium = try container.decode(Int.self)
    }

    /// Writes an explicit `null` for a missing total: the positions are the meaning.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        for value in [saturatedFatG, sugarG, sodiumMg] {
            if let value { try container.encode(value) } else { try container.encodeNil() }
        }
        try container.encode(foods)
        try container.encode(withSaturatedFat)
        try container.encode(withSugar)
        try container.encode(withSodium)
    }
}

/// Sender-side builders for `fx`, `fe` and `ux`, shared so LIFT iOS and Coach
/// iOS round exactly as LIFT Android and web do.
public enum ShareNutrients {

    /// `fx` for a day. `items` is **every** food logged that day, including those
    /// that recorded none of the three (they still count toward `foods`), each as
    /// its servings and its **per-serving** details.
    ///
    /// A sender whose stored nutrition is already multiplied out (LIFT iOS's
    /// `FoodEntry.nutrition`, sent with `servings: 1`) passes servings 1 and the
    /// stored values — the product is the same.
    ///
    /// Totals are summed unrounded and rounded once. nil when no food recorded
    /// any of the three: the day then carries no `fx` at all. A non-finite value
    /// counts as unrecorded.
    public static func dayTotals(_ items: [(servings: Double, details: WireNutrientDetails?)]) -> WireNutrientTotals? {
        var saturatedFat = 0.0, sugar = 0.0, sodium = 0.0
        var withSaturatedFat = 0, withSugar = 0, withSodium = 0
        for item in items {
            guard let details = item.details.map(finite) else { continue }
            if let value = details.saturatedFatG { saturatedFat += value * item.servings; withSaturatedFat += 1 }
            if let value = details.sugarG { sugar += value * item.servings; withSugar += 1 }
            if let value = details.sodiumMg { sodium += value * item.servings; withSodium += 1 }
        }
        guard withSaturatedFat + withSugar + withSodium > 0 else { return nil }
        return WireNutrientTotals(
            saturatedFatG: withSaturatedFat > 0 ? roundGrams(saturatedFat) : nil,
            sugarG: withSugar > 0 ? roundGrams(sugar) : nil,
            sodiumMg: withSodium > 0 ? roundMilligrams(sodium) : nil,
            foods: items.count,
            withSaturatedFat: withSaturatedFat,
            withSugar: withSugar,
            withSodium: withSodium)
    }

    /// One `fe` entry, or a plan recipe's `ux`: per serving, rounded, nil when
    /// none of the three is known. Encoding trims trailing nulls.
    ///
    /// A day's `fe` is `foods.map { itemRow(...) }`, aligned with `f`; leave the
    /// whole `fe` off when every entry is nil.
    public static func itemRow(_ details: WireNutrientDetails?) -> WireNutrientDetails? {
        guard let details = details.map(finite), !details.isEmpty else { return nil }
        return WireNutrientDetails(saturatedFatG: details.saturatedFatG.map(roundGrams),
                                   sugarG: details.sugarG.map(roundGrams),
                                   sodiumMg: details.sodiumMg.map(roundMilligrams))
    }

    /// `itemRow` from per-serving facts — the usual call for `ux`
    /// (`Recipe.nutritionPerServing`) and for a food logged per serving.
    public static func itemRow(perServing facts: NutritionFacts?) -> WireNutrientDetails? {
        itemRow(facts.map(WireNutrientDetails.init))
    }

    /// `fe` for an itemized day: one entry per food, in `f`'s order. nil when no
    /// entry is known, so the key is omitted rather than sent as all nulls.
    public static func items(_ details: [WireNutrientDetails?]) -> [WireNutrientDetails?]? {
        let rows = details.map(itemRow)
        return rows.contains { $0 != nil } ? rows : nil
    }

    /// Grams to one decimal, half-up: `floor(value * 10 + 0.5) / 10`, which is
    /// what `Math.round` does in Java and JavaScript. Swift's `.rounded()` rounds
    /// negative halves away from zero, so it is not used.
    public static func roundGrams(_ value: Double) -> Double {
        (value * 10 + 0.5).rounded(.down) / 10
    }

    /// Whole milligrams, half-up: `floor(value + 0.5)`.
    public static func roundMilligrams(_ value: Double) -> Double {
        (value + 0.5).rounded(.down)
    }

    private static func finite(_ details: WireNutrientDetails) -> WireNutrientDetails {
        WireNutrientDetails(saturatedFatG: details.saturatedFatG.flatMap { $0.isFinite ? $0 : nil },
                            sugarG: details.sugarG.flatMap { $0.isFinite ? $0 : nil },
                            sodiumMg: details.sodiumMg.flatMap { $0.isFinite ? $0 : nil })
    }
}

public extension NutritionFacts {
    /// These facts with saturated fat, sugar and sodium taken from `details`
    /// wherever `details` knows them; a value `details` leaves nil is kept. The
    /// receiving half of `fe` and `ux`: pass the same basis (per serving) on
    /// both sides.
    func merging(_ details: WireNutrientDetails?) -> NutritionFacts {
        guard let details else { return self }
        var result = self
        if let value = details.saturatedFatG { result.saturatedFatG = value }
        if let value = details.sugarG { result.sugarG = value }
        if let value = details.sodiumMg { result.sodiumMg = value }
        return result
    }
}

/// Reads one element of an array whose elements may each be malformed, without
/// failing the array. A failed `decode` in an unkeyed container does not advance
/// its index, so `try?` on the element alone would loop on the same bad value;
/// decoding this wrapper always succeeds and always advances.
struct LenientNutrientDetails: Decodable {
    let value: WireNutrientDetails?

    init(from decoder: Decoder) throws {
        let decoded = try? WireNutrientDetails(from: decoder)
        value = (decoded?.isEmpty ?? true) ? nil : decoded
    }
}
