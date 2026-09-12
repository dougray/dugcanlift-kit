import Foundation

/// A date-only key, `"yyyy-MM-dd"`, in the **device's local time zone**.
///
/// Local, not UTC, because the wire formats transmit a calendar date with no
/// time component — so it means a date in the reader's own zone. A UTC key
/// files a 7:30pm US-Central workout under the next day, and HealthKit's
/// collection query already returns local calendar-day buckets, so a UTC
/// formatter mislabels every step count west of Greenwich.
///
/// Coach iOS previously used a UTC version to avoid a DST hazard. That hazard
/// does not exist for `Calendar` arithmetic, which walks Oct 30, 31, Nov 1,
/// 2, 3 correctly across the fall-back; only naive `+86400` arithmetic repeats
/// a day. **Day arithmetic here always goes through `Calendar`.**
public enum DayKey {

    private static func formatter(_ timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private static func calendar(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    public static func make(from date: Date, timeZone: TimeZone = .current) -> String {
        formatter(timeZone).string(from: date)
    }

    public static var today: String { make(from: .now) }

    public static func string(from date: Date, timeZone: TimeZone = .current) -> String {
        make(from: date, timeZone: timeZone)
    }

    public static func date(from key: String, timeZone: TimeZone = .current) -> Date? {
        formatter(timeZone).date(from: key)
    }

    /// Shifts a key by whole days. `Calendar`, never seconds: seconds-based
    /// arithmetic repeats a day across a DST fall-back.
    public static func adding(days: Int, to key: String,
                              timeZone: TimeZone = .current) -> String? {
        guard let base = date(from: key, timeZone: timeZone),
              let shifted = calendar(timeZone).date(byAdding: .day, value: days, to: base)
        else { return nil }
        return make(from: shifted, timeZone: timeZone)
    }

    /// Whole days between two keys, `to` minus `from`.
    ///
    /// Both endpoints are re-anchored to **noon** before diffing — the same
    /// trick `PlanImporter.swift` (lift-ios) uses and documents ("Landing at
    /// midday rather than midnight avoids a second hazard"). `date(from:)`
    /// lands at local midnight, which does not exist in time zones whose DST
    /// spring-forward happens exactly then (`America/Santiago`,
    /// `Asia/Beirut`, `America/Havana`, `America/Asuncion`, `Asia/Tehran`,
    /// Palestine): the formatter's lenient parse rounds up to 01:00 instead.
    /// `dateComponents([.day], from:to:)` compares hour-of-day too, so a
    /// `from`/`to` pair straddling only one rounded endpoint undercounts by a
    /// day. Noon is not a DST transition instant anywhere, so re-deriving
    /// both dates' year/month/day and rebuilding at hour 12 gives both
    /// endpoints a matching, real hour before the diff.
    public static func daysBetween(_ from: String, _ to: String,
                                   timeZone: TimeZone = .current) -> Int? {
        guard let fromNoon = noon(from, timeZone: timeZone),
              let toNoon = noon(to, timeZone: timeZone)
        else { return nil }
        return calendar(timeZone).dateComponents([.day], from: fromNoon, to: toNoon).day
    }

    /// Re-anchors a key at local noon. See `daysBetween`'s doc comment for why.
    private static func noon(_ key: String, timeZone: TimeZone) -> Date? {
        guard let midnight = date(from: key, timeZone: timeZone) else { return nil }
        let cal = calendar(timeZone)
        let parts = cal.dateComponents([.year, .month, .day], from: midnight)
        var noonParts = DateComponents()
        noonParts.year = parts.year
        noonParts.month = parts.month
        noonParts.day = parts.day
        noonParts.hour = 12
        return cal.date(from: noonParts)
    }
}
