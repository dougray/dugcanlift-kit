import XCTest
@testable import LiftCore

final class SmokeTests: XCTestCase {
    func testPackageBuildsAndLinks() {
        // Nothing has moved into the package yet. This exists so Task 1 has a
        // deliverable that fails before the manifest is right and passes after.
        XCTAssertTrue(true)
    }
}
