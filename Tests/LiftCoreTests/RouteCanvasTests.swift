import XCTest
import SwiftUI
@testable import LiftCore

/// The words are LIFT Android's (`RoutePolylineCanvas`), pinned so the three
/// LIFT builds say the same thing while a route has fewer than two points.
final class RouteCanvasTests: XCTestCase {
    func testTheWordsMatchAndroid() {
        XCTAssertEqual(RouteCanvas.waitingText, "Waiting for GPS…")
        XCTAssertEqual(RouteCanvas.accessibilityName, "Route")
    }

    func testItBuildsWithAndWithoutARoute() {
        _ = RouteCanvas(points: []).body
        _ = RouteCanvas(points: [OutdoorShareCoordinate(latitude: 0, longitude: 0),
                                 OutdoorShareCoordinate(latitude: 0.01, longitude: 0.01)],
                        aspectRatio: 1).body
    }
}
