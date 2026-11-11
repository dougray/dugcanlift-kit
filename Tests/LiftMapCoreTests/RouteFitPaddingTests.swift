import XCTest
@testable import LiftMapCore

final class RouteFitPaddingTests: XCTestCase {
    func testTheBottomLeavesRoomForTheAttribution() {
        let p = RouteFitPadding.standard
        XCTAssertGreaterThan(p.bottom, p.top)
        XCTAssertGreaterThan(p.bottom, p.left)
        XCTAssertGreaterThan(p.bottom, p.right)
    }

    func testThePaddingIs24AroundAnd50Below() {
        XCTAssertEqual(RouteFitPadding.standard, RouteFitPadding(top: 24, left: 24, bottom: 50, right: 24))
    }
}
