import XCTest
import LiftCore
import LiftMapCore
@testable import LiftMap

/// The view code is proven on the simulator in the app tasks; these pin the
/// rules in it that decide what is downloaded again.
final class MapsSectionTests: XCTestCase {

    private func area(from plan: StreetAreaPlan) -> StreetArea {
        StreetArea(id: UUID(), name: "x", detail: plan.detail, detailKm: plan.detailKm,
                   downloadedAt: Date(), bytes: 0)
    }

    func testUpdatingARadiusAreaAsksForTheSameTiles() {
        for km in StreetAreaPlan.detailChoices {
            let original = StreetAreaPlan(latitude: 39.7392, longitude: -104.9903, detailKm: km)
            let again = MapsSection.replan(area(from: original))
            XCTAssertEqual(again.detailKm, km)
            XCTAssertEqual(Set(again.tiles), Set(original.tiles), "\(km) km")
        }
    }

    func testUpdatingARouteAreaDoesNotGrowItAgain() {
        let route = MapBounds(south: 39.70, west: -105.02, north: 39.76, east: -104.95)
        let original = StreetAreaPlan.forRoute(route)
        let again = MapsSection.replan(area(from: original))
        XCTAssertEqual(again.detailKm, 0)
        XCTAssertEqual(again.detail.south, original.detail.south, accuracy: 1e-9)
        XCTAssertEqual(again.detail.north, original.detail.north, accuracy: 1e-9)
        XCTAssertEqual(again.detail.west, original.detail.west, accuracy: 1e-9)
        XCTAssertEqual(again.detail.east, original.detail.east, accuracy: 1e-9)
        XCTAssertEqual(Set(again.tiles), Set(original.tiles))
    }

    func testTheSizeIsSaidInWords() {
        XCTAssertTrue(StreetsSheet.sizeText(bytes: 40_000_000).hasPrefix("About "))
        XCTAssertTrue(StreetsSheet.sizeText(bytes: 40_000_000).contains("MB"))
    }

    func testAnAreaIsNamedByItsCentreAndNothingLookedUp() {
        XCTAssertEqual(MapsSection.name(around: (39.7392, -104.9903)), "Streets around 39.74, -104.99")
    }

    func testTheGuardCanBeInstalledTwice() {
        MapNetworkGuard.install()
        MapNetworkGuard.install()
    }
}
