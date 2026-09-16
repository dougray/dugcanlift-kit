import Foundation

/// Macros for one logged portion, as consumed — not per 100 g.
///
/// SwiftData stores this inline as a Codable value, so there is no relationship
/// to traverse and no extra fetch when summing a day.
///
/// **Every stored property here is a column in both apps' stores.** SwiftData
/// flattens a struct property into one column per field on the owning entity
/// (`ZCALORIES`, `ZSUGARG`, ... and `ZCALORIES1`, ... for a second property
/// of this type), so each field is part of the entity's schema checksum for
/// `FoodEntry`, `Recipe` and `PlannedMeal` alike. Adding one — as 1.9.0 did
/// with `saturatedFatG` — is a schema change for every app that stores these
/// models. See the README's 1.9.0 notes for what that cost each app.
///
/// Sugar, sodium and saturated fat are tracked, never targeted, and nil means
/// "the source did not say", which is not zero.
public struct NutritionFacts: Codable, Hashable, Sendable {
    public var calories: Double = 0
    public var proteinG: Double = 0
    public var carbsG: Double = 0
    public var fatG: Double = 0
    public var fiberG: Double?
    public var sugarG: Double?
    public var sodiumMg: Double?
    /// Added in 1.9.0. Last, and optional with no default other than nil, so a
    /// value encoded before it existed still decodes and a store written
    /// before it opens with nil here.
    public var saturatedFatG: Double?

    public init(calories: Double = 0,
                proteinG: Double = 0,
                carbsG: Double = 0,
                fatG: Double = 0,
                fiberG: Double? = nil,
                sugarG: Double? = nil,
                sodiumMg: Double? = nil,
                saturatedFatG: Double? = nil) {
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.fiberG = fiberG
        self.sugarG = sugarG
        self.sodiumMg = sodiumMg
        self.saturatedFatG = saturatedFatG
    }

    public static let zero = NutritionFacts()

    public static func + (lhs: NutritionFacts, rhs: NutritionFacts) -> NutritionFacts {
        NutritionFacts(
            calories: lhs.calories + rhs.calories,
            proteinG: lhs.proteinG + rhs.proteinG,
            carbsG:   lhs.carbsG + rhs.carbsG,
            fatG:     lhs.fatG + rhs.fatG,
            fiberG:   optionalSum(lhs.fiberG, rhs.fiberG),
            sugarG:   optionalSum(lhs.sugarG, rhs.sugarG),
            sodiumMg: optionalSum(lhs.sodiumMg, rhs.sodiumMg),
            saturatedFatG: optionalSum(lhs.saturatedFatG, rhs.saturatedFatG)
        )
    }

    /// nil + nil stays nil, so "no fibre data" never silently becomes "0 g".
    /// A known value plus nil is the known value: a sum over only the foods
    /// that recorded it. A day total built this way is a floor, which is why
    /// the share link's `fx` also carries how many foods each total covers.
    private static func optionalSum(_ a: Double?, _ b: Double?) -> Double? {
        guard a != nil || b != nil else { return nil }
        return (a ?? 0) + (b ?? 0)
    }

    public func scaled(by factor: Double) -> NutritionFacts {
        NutritionFacts(
            calories: calories * factor,
            proteinG: proteinG * factor,
            carbsG:   carbsG * factor,
            fatG:     fatG * factor,
            fiberG:   fiberG.map { $0 * factor },
            sugarG:   sugarG.map { $0 * factor },
            sodiumMg: sodiumMg.map { $0 * factor },
            saturatedFatG: saturatedFatG.map { $0 * factor }
        )
    }
}
