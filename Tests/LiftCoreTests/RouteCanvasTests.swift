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

    @MainActor
    func testItRendersARouteAndHandlesZeroSize() {
        // Render a 2-point route at 200×200 and verify it produces an image
        var renderer = ImageRenderer(content: RouteCanvas(points: [
            OutdoorShareCoordinate(latitude: 0, longitude: 0),
            OutdoorShareCoordinate(latitude: 0.01, longitude: 0.01)
        ]).frame(width: 200, height: 200))
        XCTAssertNotNil(renderer.cgImage)

        // Render the same route at 0×0: rendering completes without crashing
        renderer = ImageRenderer(content: RouteCanvas(points: [
            OutdoorShareCoordinate(latitude: 0, longitude: 0),
            OutdoorShareCoordinate(latitude: 0.01, longitude: 0.01)
        ]).frame(width: 0, height: 0))
        _ = renderer.cgImage  // Nil is acceptable at zero size

        // Render an empty route at 200×200 and verify it produces an image (shows waiting text)
        renderer = ImageRenderer(content: RouteCanvas(points: []).frame(width: 200, height: 200))
        XCTAssertNotNil(renderer.cgImage)
    }

    func testAccessibilityTextChoiceByPointCount() {
        XCTAssertEqual(RouteCanvas.accessibilityText(pointCount: 0), RouteCanvas.waitingText)
        XCTAssertEqual(RouteCanvas.accessibilityText(pointCount: 1), RouteCanvas.waitingText)
        XCTAssertEqual(RouteCanvas.accessibilityText(pointCount: 2), RouteCanvas.accessibilityName)
        XCTAssertEqual(RouteCanvas.accessibilityText(pointCount: 150), RouteCanvas.accessibilityName)
    }
}
