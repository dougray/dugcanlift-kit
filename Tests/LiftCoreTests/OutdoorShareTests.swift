import XCTest
@testable import LiftCore

/// The fixtures in `Fixtures/outdoor-share-*` were written by LIFT web's
/// `lift/outdoor.js` and are copied in verbatim. Never regenerate them from
/// this package: the point is that a Swift sender produces the web's bytes,
/// and a fixture written by the code under test would agree with any bug.
final class OutdoorShareTests: XCTestCase {

    // MARK: - Fixture loading

    private func fixtureData(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: nil,
                                                  subdirectory: "Fixtures"),
                                "missing fixture \(name)")
        return try Data(contentsOf: url)
    }

    private func fixtureJSON(_ name: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: fixtureData(name)) as? [String: Any])
    }

    /// The backup-shaped input, mapped the way a sender would map its storage.
    private func fixtureActivities() throws -> [OutdoorShareActivity] {
        let outdoor = try XCTUnwrap(fixtureJSON("outdoor-share-input.json")["outdoor"] as? [[String: Any]])
        let types = ["RUN": 0, "WALK": 1, "HIKE": 2]
        return try outdoor.map { o in
            let points = (o["routePoints"] as? [[String: Any]]) ?? []
            return OutdoorShareActivity(
                type: try XCTUnwrap(types[o["activityType"] as? String ?? ""]),
                startedAtEpochMs: try XCTUnwrap((o["startedAtEpochMs"] as? NSNumber)?.int64Value),
                endedAtEpochMs: (o["endedAtEpochMs"] as? NSNumber)?.int64Value,
                distanceMeters: (o["distanceMeters"] as? NSNumber)?.doubleValue ?? 0,
                climbMeters: (o["elevationGainMeters"] as? NSNumber)?.doubleValue ?? 0,
                route: try points.map {
                    OutdoorShareCoordinate(latitude: try XCTUnwrap(($0["latitude"] as? NSNumber)?.doubleValue),
                                           longitude: try XCTUnwrap(($0["longitude"] as? NSNumber)?.doubleValue))
                }
            )
        }
    }

    /// Encodes with the package's own Codable and parses the result back as
    /// plain JSON, so a comparison with the fixture never goes through this
    /// package's decoder.
    private func asJSON<T: Encodable>(_ value: T) throws -> NSObject {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value),
                                                   options: .fragmentsAllowed) as? NSObject)
    }

    // MARK: - Matching LIFT web exactly

    func testTheFixtureProducesExactlyTheWebsDayTuples() throws {
        // Includes an unfinished hike, which must not appear.
        let expected = try XCTUnwrap(fixtureJSON("outdoor-share-expected.json")["o"] as? NSArray)
        XCTAssertEqual(try asJSON(OutdoorShare.day(fixtureActivities())), expected)
    }

    func testTheFixtureProducesExactlyTheWebsBests() throws {
        // The walk is 300 m: too short to set a pace, so its pace is null
        // rather than a zero or its real, noisy value.
        let expected = try XCTUnwrap(fixtureJSON("outdoor-share-expected.json")["ob"] as? NSArray)
        let bests = try XCTUnwrap(OutdoorShare.bests(fixtureActivities()))
        XCTAssertEqual(try asJSON(bests), expected)
    }

    func testTheFixtureProducesExactlyTheWebsLastRoute() throws {
        let fixture = try fixtureJSON("outdoor-share-expected.json")
        let expected = try XCTUnwrap(fixture["lr"] as? [Any])
        let route = try XCTUnwrap(OutdoorShare.lastRoute(fixtureActivities()))

        // The polyline is compared as a string on its own first: a one-unit
        // rounding difference anywhere in 150 points shows up here by name.
        XCTAssertEqual(route.polyline, expected[5] as? String)
        XCTAssertEqual(try asJSON(route), expected as NSArray)
    }

    func testTrimAndThinKeepsTheWebsPointCount() throws {
        let fixture = try fixtureJSON("outdoor-share-expected.json")
        let loop = try XCTUnwrap(fixtureActivities().first { $0.route.count == 400 })
        XCTAssertEqual(OutdoorShare.trimAndThin(loop.route).count,
                       (fixture["trimmedPointCount"] as? NSNumber)?.intValue)
    }

    // MARK: - Last route rules

    func testARouteWithNothingLeftAfterTrimmingSendsNoRouteRatherThanAnOlderOne() throws {
        let activities = try fixtureActivities()
        let walk = try XCTUnwrap(activities.first { $0.type == 1 })
        let olderRun = try XCTUnwrap(activities.first { $0.route.count == 60 })
        // The 300 m walk is the newest here; all of it is within 200 m of an end.
        XCTAssertNil(OutdoorShare.lastRoute([olderRun, walk]))
    }

    func testNothingFinishedSendsNoBests() {
        let recording = OutdoorShareActivity(type: 2, startedAtEpochMs: 1, endedAtEpochMs: nil,
                                             distanceMeters: 900, climbMeters: 0)
        XCTAssertNil(OutdoorShare.bests([recording]))
        XCTAssertNil(OutdoorShare.bests([]))
        XCTAssertEqual(OutdoorShare.day([recording]), [])
    }

    // MARK: - Polyline

    func testGooglesWorkedExampleEncodes() {
        let points = [(38.5, -120.2), (40.7, -120.95), (43.252, -126.453)]
            .map { OutdoorShareCoordinate(latitude: $0.0, longitude: $0.1) }
        XCTAssertEqual(OutdoorShare.encodePolyline(points), "_p~iF~ps|U_ulLnnqC_mqNvxq`@")
    }

    func testGooglesWorkedExampleDecodes() {
        let decoded = OutdoorShare.decodePolyline("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
        XCTAssertEqual(decoded.count, 3)
        let expected = [(38.5, -120.2), (40.7, -120.95), (43.252, -126.453)]
        for (point, (lat, lon)) in zip(decoded, expected) {
            XCTAssertEqual(point.latitude, lat, accuracy: 1e-9)
            XCTAssertEqual(point.longitude, lon, accuracy: 1e-9)
        }
    }

    func testANegativeHalfRoundsUpNotAwayFromZero() {
        // -0.5 units: floor(-0.5 + 0.5) = 0, which encodes as "?". Swift's
        // `rounded()` would give -1 and a different string from every other
        // sender.
        let point = OutdoorShareCoordinate(latitude: 0, longitude: -0.000005)
        XCTAssertEqual(OutdoorShare.encodePolyline([point]), "??")
    }

    func testATruncatedPolylineKeepsThePointsBeforeTheDamage() {
        // Cut mid-way through the third point's longitude.
        let decoded = OutdoorShare.decodePolyline("_p~iF~ps|U_ulLnnqC_mqNvx")
        XCTAssertEqual(decoded.count, 2)
    }

    func testRoundHalfUpMatchesJavaScriptMathRound() {
        XCTAssertEqual(OutdoorShare.roundHalfUp(2.5), 3)
        XCTAssertEqual(OutdoorShare.roundHalfUp(-2.5), -2)
        XCTAssertEqual(OutdoorShare.roundHalfUp(0.49999999999999994), 0)
        XCTAssertEqual(OutdoorShare.roundHalfUp(.nan), 0)
    }

    // MARK: - The whole link

    func testTheWebsLinkDecodesWithItsOutdoorParts() throws {
        let link = try XCTUnwrap(String(data: fixtureData("outdoor-share-link.txt"), encoding: .utf8))
        let payload = try ShareLinkCodec.decode(link: link)
        let expected = try fixtureJSON("outdoor-share-expected.json")

        // Days hold only outdoor activities, one each — still days.
        XCTAssertEqual(payload.d.map(\.k), [0, 2, 3])
        XCTAssertTrue(payload.d.allSatisfy { $0.w == nil && $0.ft == nil && $0.f == nil })
        let allO = payload.d.flatMap { $0.o ?? [] }
        XCTAssertEqual(try asJSON(allO), expected["o"] as? NSArray)
        XCTAssertEqual(try asJSON(XCTUnwrap(payload.ob)), expected["ob"] as? NSArray)
        XCTAssertEqual(try asJSON(XCTUnwrap(payload.lr)), expected["lr"] as? NSArray)
        XCTAssertEqual(payload.lr?.startedAtEpochSec, 1_789_259_200)
    }

    func testAPayloadWithoutOutdoorKeysRoundTripsUnchanged() throws {
        let json = #"{"v":1,"c":{"i":"abc","n":"Jordan","u":"lb","p":"ios"},"g":{"c":2400,"p":190,"f":70,"cb":0,"fb":0},"r":"2026-08-01","t":"2026-08-19","z":1755590400,"x":["Squat|Barbell"],"fd":["Oats"],"d":[{"k":0,"n":"legs","bw":209.4,"st":9140,"w":[[0,[[225,5,8],[null,5]]]],"ft":[2180,172,60,210,30]}]}"#
        let payload = try JSONDecoder().decode(ShareLinkPayload.self, from: Data(json.utf8))
        XCTAssertNil(payload.ob)
        XCTAssertNil(payload.lr)
        XCTAssertNil(payload.d[0].o)

        let encoded = try JSONEncoder().encode(payload)
        let text = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        // Nil must be omitted, not written as null: an old decoder that
        // meets "lr":null is fine, but an absent key is what the format says.
        XCTAssertFalse(text.contains(#""ob""#))
        XCTAssertFalse(text.contains(#""lr""#))
        XCTAssertFalse(text.contains(#""o""#))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: encoded) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: Data(json.utf8)) as? NSDictionary)
    }

    func testOutdoorPartsEncodeAsTheWireTuples() throws {
        // Compared as parsed JSON: `JSONEncoder` does not promise key order,
        // and no reader of this format depends on one.
        let day = WireDay(k: 0, n: nil, fo: nil, bw: nil, st: nil, w: nil, ft: [2000, 150, 60, 200, 25], f: nil,
                          o: [WireOutdoorActivity(type: 0, durationSec: 1720, distanceMeters: 5012, climbMeters: 38)])
        let payload = ShareLinkPayload(
            v: 1, c: WireClient(i: "a", n: "b", s: nil, a: nil, h: nil, u: "lb", p: nil), g: nil,
            r: "2026-08-01", t: "2026-08-19", z: 1, x: [], fd: nil, d: [day],
            ob: [WireOutdoorBest(type: 0, count: 1, farthestMeters: 5012, longestSec: nil, fastestSecPerKm: nil)],
            lr: WireLastRoute(type: 0, startedAtEpochSec: 1, durationSec: 2, distanceMeters: 3, climbMeters: 4, polyline: "??"))
        let encoded = try JSONEncoder().encode(payload)
        let expected = #"{"v":1,"c":{"i":"a","n":"b","u":"lb"},"r":"2026-08-01","t":"2026-08-19","z":1,"x":[],"d":[{"k":0,"ft":[2000,150,60,200,25],"o":[[0,1720,5012,38]]}],"ob":[[0,1,5012,null,null]],"lr":[0,1,2,3,4,"??"]}"#
        XCTAssertEqual(try JSONSerialization.jsonObject(with: encoded) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: Data(expected.utf8)) as? NSDictionary,
                       String(data: encoded, encoding: .utf8) ?? "")
    }

    func testAMalformedOutdoorPartCostsOnlyThatPart() throws {
        // A coach must still get the training and food log when a sender gets
        // a route or a best wrong.
        let json = #"{"v":1,"c":{"i":"abc","n":"Jordan","u":"lb"},"r":"2026-08-01","t":"2026-08-19","z":1,"x":[],"d":[{"k":0,"st":5000,"o":[[0,"long"]]},{"k":1,"o":[[1,240,300,0]]}],"ob":{"not":"a list"},"lr":[0,"yesterday",1720]}"#
        let payload = try JSONDecoder().decode(ShareLinkPayload.self, from: Data(json.utf8))
        XCTAssertNil(payload.lr)
        XCTAssertNil(payload.ob)
        XCTAssertEqual(payload.d.count, 2)
        XCTAssertEqual(payload.d[0].st, 5000)
        XCTAssertNil(payload.d[0].o)
        XCTAssertEqual(payload.d[1].o, [WireOutdoorActivity(type: 1, durationSec: 240, distanceMeters: 300, climbMeters: 0)])
    }

    func testAMalformedOlderKeyStillFailsThePayload() {
        // Leniency is for the outdoor keys only. A broken day or client is a
        // corrupt link, as it always was.
        let json = #"{"v":1,"c":{"i":"abc","n":"Jordan","u":"lb"},"r":"2026-08-01","t":"2026-08-19","z":1,"x":[],"d":[{"k":"zero"}]}"#
        XCTAssertThrowsError(try JSONDecoder().decode(ShareLinkPayload.self, from: Data(json.utf8)))
    }
}
