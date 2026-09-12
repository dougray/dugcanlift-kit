import XCTest
@testable import LiftCore

final class DayKeyTests: XCTestCase {

    private let chicago = TimeZone(identifier: "America/Chicago")!
    private let santiago = TimeZone(identifier: "America/Santiago")!
    private let beirut = TimeZone(identifier: "Asia/Beirut")!

    func testAnEveningLogKeysToThatSameLocalDay() {
        // The whole reason this type is local rather than UTC. 7:30pm Central
        // on 2026-09-11 is still 2026-09-11, not the 12th.
        let evening = ISO8601DateFormatter().date(from: "2026-09-11T19:30:00-05:00")!
        XCTAssertEqual(DayKey.make(from: evening, timeZone: chicago), "2026-09-11")
    }

    func testAddingDaysDoesNotRepeatADayAcrossTheDSTFallBack() {
        // Calendar arithmetic is DST-safe; `now - days * 86400` is not, and
        // repeats 2026-11-01. That difference is why this type exists.
        var walked: [String] = []
        var key = "2026-10-30"
        for _ in 0..<4 {
            key = DayKey.adding(days: 1, to: key, timeZone: chicago)!
            walked.append(key)
        }
        XCTAssertEqual(walked, ["2026-10-31", "2026-11-01", "2026-11-02", "2026-11-03"])
    }

    func testParseThenFormatRoundTrips() {
        XCTAssertEqual(DayKey.string(from: DayKey.date(from: "2026-03-08")!), "2026-03-08")
    }

    func testDaysBetweenCountsWholeDays() {
        XCTAssertEqual(DayKey.daysBetween("2026-09-01", "2026-09-11"), 10)
        XCTAssertEqual(DayKey.daysBetween("2026-09-11", "2026-09-01"), -10)
        XCTAssertEqual(DayKey.daysBetween("2026-09-11", "2026-09-11"), 0)
    }

    func testDaysBetweenSpansTheDSTFallBackWithoutDrift() {
        XCTAssertEqual(DayKey.daysBetween("2026-10-30", "2026-11-03", timeZone: chicago), 4)
    }

    func testDaysBetweenSpansASpringForwardAtMidnightInSantiago() {
        // 2026-09-06 00:00 does not exist in America/Santiago (clocks jump
        // straight to 01:00), so `date(from:)` alone lands one hour into the
        // day. Without the noon anchor this undercounts by a whole day.
        XCTAssertEqual(DayKey.daysBetween("2026-09-06", "2026-09-07", timeZone: santiago), 1)
        XCTAssertEqual(DayKey.daysBetween("2026-09-06", "2026-09-13", timeZone: santiago), 7)
    }

    func testDaysBetweenSpansASpringForwardAtMidnightInBeirut() {
        // Same hazard, different zone: Asia/Beirut also jumps at midnight.
        XCTAssertEqual(DayKey.daysBetween("2026-03-29", "2026-03-30", timeZone: beirut), 1)
    }

    func testAddingADayAcrossASpringForwardAtMidnightDoesNotDrift() {
        // `adding` walks through `Calendar.date(byAdding:)`, which preserves
        // whatever hour `date(from:)` lands on rather than diffing two
        // independently-rounded endpoints — verified by execution to be
        // unaffected by the midnight-DST-gap hazard that broke `daysBetween`.
        // This test locks that in.
        XCTAssertEqual(DayKey.adding(days: 1, to: "2026-09-05", timeZone: santiago), "2026-09-06")
        XCTAssertEqual(DayKey.adding(days: 1, to: "2026-09-06", timeZone: santiago), "2026-09-07")
        XCTAssertEqual(DayKey.adding(days: -1, to: "2026-09-07", timeZone: santiago), "2026-09-06")
    }

    func testAMalformedKeyIsNilRatherThanACrash() {
        XCTAssertNil(DayKey.date(from: "not a date"))
        XCTAssertNil(DayKey.adding(days: 1, to: "2026-13-45"))
        XCTAssertNil(DayKey.daysBetween("nonsense", "2026-09-01"))
    }
}
