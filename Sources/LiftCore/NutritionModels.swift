import Foundation
import SwiftData

public enum MealType: String, Codable, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack

    public var id: String { rawValue }

    public var displayName: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }

    /// Best guess at which meal a given time of day belongs to.
    ///
    /// Thresholds match `mealForHour` in the Android build exactly. If they
    /// drift, the same food re-logged at the same time lands in different
    /// meals on the two platforms, and a coach reading the log sees a
    /// difference that isn't real.
    public static func forHour(_ hour: Int) -> MealType {
        switch hour {
        case ..<11: .breakfast
        case ..<15: .lunch
        case ..<21: .dinner
        default:    .snack
        }
    }

    /// Used for ordering a day's entries in the log view.
    public var sortOrder: Int {
        switch self {
        case .breakfast: 0
        case .lunch:     1
        case .dinner:    2
        case .snack:     3
        }
    }
}

@Model
public final class FoodEntry {
    public var id: UUID = UUID()
    public var loggedAt: Date = Date.now
    public var dayKey: String = ""

    private var mealTypeRaw: String = MealType.snack.rawValue
    public var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .snack }
        set { mealTypeRaw = newValue.rawValue }
    }

    /// Namespaced foreign key, e.g. "usda:174608" or "off:3017620422003".
    public var foodRefID: String = ""

    // Snapshot fields — see the note in ExerciseEntry. Open Food Facts in
    // particular is crowd-edited and changes constantly; a meal logged in
    // January must still show what it showed in January.
    public var name: String = ""
    public var brand: String?

    public var quantity: Double = 1
    public var servingUnit: String = "serving"
    public var servingGrams: Double?

    /// The authoritative gram amount for this entry, when logged via the
    /// gram-based search-and-log flow. `nil` for legacy entries logged
    /// before this field existed, or entries where the best-effort
    /// migration (see the migration task) couldn't determine a gram
    /// equivalent — those keep displaying via `quantity`/`servingUnit`
    /// unchanged. Never guess a value here; `nil` means "unknown," not
    /// "zero."
    public var amountGrams: Double?

    /// Already scaled to `quantity`. Summing a day is a plain reduce.
    public var nutrition: NutritionFacts = NutritionFacts.zero

    public var healthKitUUID: UUID?

    public init(foodRefID: String, name: String, brand: String? = nil,
         quantity: Double, servingUnit: String, servingGrams: Double? = nil,
         amountGrams: Double? = nil,
         nutrition: NutritionFacts, mealType: MealType, loggedAt: Date = .now) {
        self.id = UUID()
        self.foodRefID = foodRefID
        self.name = name
        self.brand = brand
        self.quantity = quantity
        self.servingUnit = servingUnit
        self.servingGrams = servingGrams
        self.amountGrams = amountGrams
        self.nutrition = nutrition
        self.mealTypeRaw = mealType.rawValue
        self.loggedAt = loggedAt
        self.dayKey = DayKey.make(from: loggedAt)
    }

    public var displayName: String {
        guard let brand, !brand.isEmpty else { return name }
        return "\(brand) \(name)"
    }
}

public extension Array where Element == FoodEntry {
    var totalNutrition: NutritionFacts {
        reduce(.zero) { $0 + $1.nutrition }
    }

    func grouped() -> [(meal: MealType, entries: [FoodEntry])] {
        Dictionary(grouping: self, by: \.mealType)
            .sorted { $0.key.sortOrder < $1.key.sortOrder }
            .map { (meal: $0.key, entries: $0.value.sorted { $0.loggedAt < $1.loggedAt }) }
    }
}

/// Fetch descriptors used by both the app and the widget.
public enum LiftQueries {
    public static func foodEntries(on dayKey: String) -> FetchDescriptor<FoodEntry> {
        FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.dayKey == dayKey },
            sortBy: [SortDescriptor(\.loggedAt)]
        )
    }

}
