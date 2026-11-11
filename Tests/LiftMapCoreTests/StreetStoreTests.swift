import XCTest
import GRDB
import LiftCore
@testable import LiftMapCore

final class StreetStoreTests: XCTestCase {
    private func makeStore() throws -> StreetStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("streets-\(UUID().uuidString).mbtiles")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return try StreetStore(fileURL: url)
    }

    private func plan(_ lat: Double = 39.7392, _ lon: Double = -104.9903) -> StreetAreaPlan {
        StreetAreaPlan(latitude: lat, longitude: lon, detailKm: 10)
    }

    private func count(_ store: StreetStore, _ sql: String) throws -> Int {
        let q = try DatabaseQueue(path: store.fileURL.path)
        return try q.read { try Int.fetchOne($0, sql: sql) ?? 0 }
    }

    func testATileIsStoredInTMSRows() throws {
        let store = try makeStore()
        let id = try store.beginArea(plan(), name: "Denver")
        try store.put(Data([1, 2, 3]), for: TileID(z: 14, x: 3413, y: 6218), area: id)
        XCTAssertEqual(try count(store, "SELECT COUNT(*) FROM tiles WHERE zoom_level = 14 AND tile_column = 3413 AND tile_row = 10165"), 1)
    }

    func testAnUnfinishedAreaIsListedSeparately() throws {
        let store = try makeStore()
        let id = try store.beginArea(plan(), name: "A")
        XCTAssertEqual(try store.areas().count, 0)
        XCTAssertEqual(try store.unfinishedAreas().map(\.id), [id])
        try store.finishArea(id)
        XCTAssertEqual(try store.unfinishedAreas().count, 0)
    }

    func testDeletingOneAreaKeepsTilesAnotherStillOwns() throws {
        let store = try makeStore()
        let a = try store.beginArea(plan(), name: "A")
        let b = try store.beginArea(plan(), name: "B")
        let tile = TileID(z: 5, x: 6, y: 12)
        try store.put(Data([9]), for: tile, area: a)
        try store.put(Data([9]), for: tile, area: b)
        try store.deleteArea(a)
        XCTAssertEqual(try count(store, "SELECT COUNT(*) FROM tiles"), 1)
        try store.deleteArea(b)
        XCTAssertEqual(try count(store, "SELECT COUNT(*) FROM tiles"), 0)
    }

    func testAnUnfinishedDownloadIsNotAnArea() throws {
        let store = try makeStore()
        let id = try store.beginArea(plan(), name: "Half")
        try store.put(Data([1]), for: TileID(z: 3, x: 1, y: 2), area: id)
        XCTAssertTrue(try store.areas().isEmpty)
        try store.deleteArea(id)
        XCTAssertEqual(try count(store, "SELECT COUNT(*) FROM tiles"), 0)
        XCTAssertEqual(try count(store, "SELECT COUNT(*) FROM areas"), 0)
    }

    func testCoversIsAnyFinishedAreaTouchingTheBounds() throws {
        let store = try makeStore()
        let p = plan()
        let done = try store.beginArea(p, name: "Denver")
        try store.finishArea(done)
        let d = p.detail
        XCTAssertTrue(try store.covers(MapBounds(south: d.south + 0.01, west: d.west + 0.01, north: d.south + 0.02, east: d.west + 0.02)))
        XCTAssertTrue(try store.covers(MapBounds(south: d.north - 0.01, west: d.east - 0.01, north: d.north + 1, east: d.east + 1)))
        XCTAssertFalse(try store.covers(MapBounds(south: 10, west: 10, north: 11, east: 11)))
        let other = plan(51.5, -0.12)
        _ = try store.beginArea(other, name: "London")
        XCTAssertFalse(try store.covers(other.detail))
    }

    func testMetadataIsWhatMapLibreReads() throws {
        let store = try makeStore()
        let q = try DatabaseQueue(path: store.fileURL.path)
        try q.read { db in
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT value FROM metadata WHERE name = 'format'"), "pbf")
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT value FROM metadata WHERE name = 'maxzoom'"), "14")
            XCTAssertEqual(try String.fetchOne(db, sql: "PRAGMA journal_mode")?.lowercased(), "delete")
        }
    }

    func testResumingSkipsTilesAlreadyStored() throws {
        let store = try makeStore()
        let id = try store.beginArea(plan(), name: "Denver")
        let tile = TileID(z: 12, x: 853, y: 1554)
        XCTAssertFalse(try store.hasTile(tile, area: id))
        try store.put(Data([1, 2]), for: tile, area: id)
        XCTAssertTrue(try store.hasTile(tile, area: id))
        try store.finishArea(id)
        let area = try XCTUnwrap(store.areas().first)
        XCTAssertEqual(area.bytes, 2)
        XCTAssertEqual(area.name, "Denver")
    }
}
