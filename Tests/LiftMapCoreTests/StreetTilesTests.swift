import XCTest
import LiftCore
@testable import LiftMapCore

final class StreetTilesTests: XCTestCase {
    func testTileMaths() {
        XCTAssertEqual(StreetTiles.x(-104.9903, 14), 3413)
        XCTAssertEqual(StreetTiles.y(39.7392, 14), 6218)
        XCTAssertEqual(StreetTiles.x(-104.9903, 10), 213)
        XCTAssertEqual(StreetTiles.y(39.7392, 10), 388)
        let world = MapBounds(south: -85.0511, west: -180, north: 85.0511, east: 180)
        for z in 0 ... 4 { XCTAssertEqual(StreetTiles.count(world, zoom: z), 1 << (2 * z)) }
        XCTAssertEqual(StreetTiles.tiles(in: world, zoom: 3).count, 64)

        let b = StreetTiles.bounds(latitude: 39.7392, longitude: -104.9903, radiusKm: 50)
        XCTAssertEqual(b.north - 39.7392, 50 / 111.32, accuracy: 1e-9)
        XCTAssertGreaterThan(b.east + 104.9903, b.north - 39.7392)
        XCTAssertEqual(StreetTiles.count(b, zoom: 11), 64)
        XCTAssertEqual(StreetTiles.count(b, zoom: 14), 2916)
        XCTAssertEqual(StreetTiles.tiles(in: b, zoom: 14).count, 2916)

        let edge = StreetTiles.bounds(latitude: 84.9, longitude: 179.9, radiusKm: 400)
        XCTAssertLessThanOrEqual(edge.north, 85.0511)
        XCTAssertLessThanOrEqual(edge.east, 180)
    }

    func testTMSRow() {
        XCTAssertEqual(TileID(z: 14, x: 3413, y: 6218).tmsRow, 10165)
    }

    func testPlanSizes() {
        let small = StreetAreaPlan(latitude: 39.7392, longitude: -104.9903, detailKm: 10)
        let big = StreetAreaPlan(latitude: 39.7392, longitude: -104.9903, detailKm: 50)
        XCTAssertLessThan(small.estimatedBytes, big.estimatedBytes)
        XCTAssertEqual(small.tiles.count, Set(small.tiles).count)
        XCTAssertEqual(big.tiles.count, Set(big.tiles).count)
        XCTAssertEqual(big.estimatedBytes, big.tiles.reduce(0) { $0 + StreetTiles.typicalBytes(zoom: $1.z) })
        XCTAssertEqual(StreetAreaPlan.detailChoices, [10, 25, 50])
        XCTAssertEqual(StreetAreaPlan.wideKm, 100)
    }

    /// Whole-plan numbers for Denver, the same in the Kotlin and JS ports'
    /// suites: a port that plans a different set of tiles fails here and there.
    func testDenverPlansAreTheSharedNumbers() {
        let expected: [(km: Int, tiles: Int, bytes: Int)] = [
            (10, 273, 36_530_000),
            (25, 1_125, 156_730_000),
            (50, 4_069, 568_090_000),
        ]
        for e in expected {
            let plan = StreetAreaPlan(latitude: 39.7392, longitude: -104.9903, detailKm: e.km)
            XCTAssertEqual(plan.tiles.count, e.tiles, "\(e.km) km tiles")
            XCTAssertEqual(plan.estimatedBytes, e.bytes, "\(e.km) km bytes")
        }
    }

    /// The estimate is read from the kit's measured sample, not guessed: Denver's
    /// 10 km plan came to about 30 MB in a real download, and the estimate must
    /// not be low by more than a quarter of that (nor absurdly high).
    func testDenverTenKmEstimateIsNotLowAgainstTheMeasuredDownload() throws {
        let measured = 30_000_000
        let plan = StreetAreaPlan(latitude: 39.7392, longitude: -104.9903, detailKm: 10)
        XCTAssertGreaterThanOrEqual(plan.estimatedBytes, measured * 3 / 4, "the estimate is low by more than 25%")
        XCTAssertLessThanOrEqual(plan.estimatedBytes, measured * 3 / 2, "the estimate is more than 50% high")
    }

    /// typicalBytes is the mean of the sample's urban and mid-city per-zoom means,
    /// rounded to the nearest 5,000; the rural rows are evidence and not used.
    func testTypicalBytesIsTheMeasuredUrbanAndMidCityMean() throws {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) {
            let parent = dir.deletingLastPathComponent()
            XCTAssertNotEqual(parent, dir, "no Package.swift above the test file")
            if parent == dir { return }
            dir = parent
        }
        let data = try Data(contentsOf: dir.appendingPathComponent("map/tile-size-sample.json"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let samples = try XCTUnwrap(root["samples"] as? [[String: Any]])
        func mean(_ area: String, _ z: Int) throws -> Double {
            let row = try XCTUnwrap(samples.first { ($0["area"] as? String) == area && ($0["zoom"] as? Int) == z })
            return try XCTUnwrap(row["meanBytes"] as? Double)
        }
        XCTAssertEqual(samples.count, 45)
        for z in 0 ... 14 {
            let target = (try mean("urban", z) + mean("mid", z)) / 2
            XCTAssertLessThanOrEqual(abs(Double(StreetTiles.typicalBytes(zoom: z)) - target), 2_500, "zoom \(z)")
            XCTAssertEqual(StreetTiles.typicalBytes(zoom: z) % 5_000, 0, "zoom \(z)")
        }
    }

    func testForRouteGrowsByTwoKm() {
        let route = MapBounds(south: 39.70, west: -105.00, north: 39.71, east: -104.99)
        let plan = StreetAreaPlan.forRoute(route)
        XCTAssertEqual(plan.detail.north - route.north, 2 / 111.32, accuracy: 1e-9)
        XCTAssertEqual(route.south - plan.detail.south, 2 / 111.32, accuracy: 1e-9)
        XCTAssertGreaterThan(route.west - plan.detail.west, 2 / 111.32)
        XCTAssertEqual(plan.detailKm, 0)
        XCTAssertEqual(plan.tiles.count, Set(plan.tiles).count)
        XCTAssertTrue(plan.tiles.contains { $0.z == 14 })
    }

    func testAroundAndIntersects() {
        XCTAssertNil(MapBounds.around([]))
        let one = MapBounds.around([OutdoorShareCoordinate(latitude: 1, longitude: 2)])
        XCTAssertEqual(one, MapBounds(south: 1, west: 2, north: 1, east: 2))
        let b = MapBounds.around([OutdoorShareCoordinate(latitude: 1, longitude: 2),
                                  OutdoorShareCoordinate(latitude: 3, longitude: -4)])
        XCTAssertEqual(b, MapBounds(south: 1, west: -4, north: 3, east: 2))
        let touching = MapBounds(south: 3, west: 2, north: 5, east: 6)
        XCTAssertTrue(b!.intersects(touching))
        XCTAssertFalse(b!.intersects(MapBounds(south: 4, west: 0, north: 5, east: 1)))
    }
}
