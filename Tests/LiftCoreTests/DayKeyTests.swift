import XCTest
@testable import LiftCore

final class DayKeyTests: XCTestCase {

    private let chicago = TimeZone(identifier: "America/Chicago")!

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

    func testAMalformedKeyIsNilRatherThanACrash() {
        XCTAssertNil(DayKey.date(from: "not a date"))
        XCTAssertNil(DayKey.adding(days: 1, to: "2026-13-45"))
        XCTAssertNil(DayKey.daysBetween("nonsense", "2026-09-01"))
    }
}
