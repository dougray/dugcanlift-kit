import XCTest
import CoreGraphics
@testable import LiftCore

/// `Fixtures/route-projection-expected.json` was written by Coach web's
/// `coach/route.js` (`scripts/make-route-projection-fixture.mjs`). Never
/// regenerate it from Swift.
final class RouteProjectionTests: XCTestCase {

    private func fixture() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "route-projection-expected.json",
                                                  withExtension: nil, subdirectory: "Fixtures"),
                                "missing fixture")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    func testMatchesRouteJSPointForPoint() throws {
        let f = try fixture()
        let points = OutdoorShare.decodePolyline(try XCTUnwrap(f["polyline"] as? String))
        XCTAssertEqual(points.count, 150)
        let cases = try XCTUnwrap(f["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 2)
        for c in cases {
            let width = try XCTUnwrap(c["width"] as? Double)
            let height = try XCTUnwrap(c["height"] as? Double)
            let expected = try XCTUnwrap(c["points"] as? [[Double]])
            let actual = RouteProjection.project(points, width: width, height: height)
            XCTAssertEqual(actual.count, expected.count)
            for (a, e) in zip(actual, expected) {
                XCTAssertEqual(Double(a.x), e[0], accuracy: 1e-9, "x at \(width)x\(height)")
                XCTAssertEqual(Double(a.y), e[1], accuracy: 1e-9, "y at \(width)x\(height)")
            }
        }
    }

    func testNoPointsProjectsToNothing() {
        XCTAssertEqual(RouteProjection.project([], width: 100, height: 100), [])
    }

    /// One point has no span; the minimum span keeps it from dividing by zero
    /// and centres it, as route.js does.
    func testASinglePointIsCentred() {
        let p = RouteProjection.project([OutdoorShareCoordinate(latitude: 29.4, longitude: -98.5)],
                                        width: 100, height: 60)
        XCTAssertEqual(p, [CGPoint(x: 50, y: 30)])
    }

    /// One scale for both axes: a route twice as wide as it is tall, at the
    /// equator where cos(latitude) is 1, stays twice as wide in a square.
    func testARouteIsNeverStretched() {
        let route = [OutdoorShareCoordinate(latitude: 0, longitude: 0),
                     OutdoorShareCoordinate(latitude: 0.01, longitude: 0.02)]
        let p = RouteProjection.project(route, width: 200, height: 200)
        let dx = abs(p[1].x - p[0].x), dy = abs(p[1].y - p[0].y)
        XCTAssertEqual(Double(dx / dy), 2, accuracy: 1e-6)
    }

    /// North up: the more northerly point is drawn higher (smaller y).
    func testNorthIsUp() {
        let route = [OutdoorShareCoordinate(latitude: 0, longitude: 0),
                     OutdoorShareCoordinate(latitude: 0.01, longitude: 0)]
        let p = RouteProjection.project(route, width: 100, height: 100)
        XCTAssertLessThan(p[1].y, p[0].y)
    }
}
