import Foundation

/// Macros for one logged portion, as consumed — not per 100 g.
///
/// SwiftData stores this inline as a Codable value, so there is no relationship
/// to traverse and no extra fetch when summing a day.
public struct NutritionFacts: Codable, Hashable, Sendable {
    public var calories: Double = 0
    public var proteinG: Double = 0
    public var carbsG: Double = 0
    public var fatG: Double = 0
    public var fiberG: Double?
    public var sugarG: Double?
    public var sodiumMg: Double?

    public init(calories: Double = 0,
                proteinG: Double = 0,
                carbsG: Double = 0,
                fatG: Double = 0,
                fiberG: Double? = nil,
                sugarG: Double? = nil,
                sodiumMg: Double? = nil) {
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.fiberG = fiberG
        self.sugarG = sugarG
        self.sodiumMg = sodiumMg
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
            sodiumMg: optionalSum(lhs.sodiumMg, rhs.sodiumMg)
        )
    }

    /// nil + nil stays nil, so "no fibre data" never silently becomes "0 g".
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
            sodiumMg: sodiumMg.map { $0 * factor }
        )
    }
}
