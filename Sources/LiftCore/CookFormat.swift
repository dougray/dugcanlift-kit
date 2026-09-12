import Foundation

/// The small formatters Cook screens share across LIFT and Coach.
///
/// Namespaced rather than free functions: made public in a package, a
/// file-scope `trimmed(_:)` would land in every file that imports LiftCore.
public enum CookFormat {

    /// "4" rather than "4.0"; "2.5" stays "2.5".
    public static func trimmed(_ value: Double) -> String {
        // `String(Int(value))` traps on NaN, on infinity, and past Int.max,
        // and this is reached from user-entered macro fields — a mistyped
        // 1e30 crashed the app before this guard.
        guard value.isFinite, value.magnitude < 1e15 else { return String(format: "%g", value) }
        return value == value.rounded() ? String(Int(value)) : String(format: "%g", value)
    }

    public static func servingsLabel(_ value: Double) -> String {
        value == 1 ? "1 serving" : "\(trimmed(value)) servings"
    }

    /// Counts print bare — "2", not "2 x banana". See `IngredientParser.countUnit`.
    public static func amountsLabel(_ amounts: [String: Double]) -> String {
        amounts
            .sorted { $0.key < $1.key }
            .map { unit, value in
                unit == IngredientParser.countUnit
                    ? trimmed(value)
                    : "\(trimmed(value)) \(unit)"
            }
            .joined(separator: " + ")
    }

    public static func dayLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f.string(from: date)
    }

    /// Day-key overload, for the screens that hold local `yyyy-MM-dd` keys
    /// rather than `Date`s. An unparseable key is shown as itself rather than
    /// silently relabelled as today.
    public static func dayLabel(dayKey: String) -> String {
        guard let date = DayKey.date(from: dayKey) else { return dayKey }
        return dayLabel(date)
    }
}
