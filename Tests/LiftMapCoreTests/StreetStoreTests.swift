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

    func testATileForAnAreaWithNoRowIsRefused() throws {
        let store = try makeStore()
        let tile = TileID(z: 3, x: 1, y: 2)
        XCTAssertThrowsError(try store.put(Data([1]), for: tile, area: UUID())) {
            XCTAssertEqual($0 as? StreetStoreError, .unknownArea)
        }
        let id = try store.beginArea(plan(), name: "Gone")
        try store.deleteArea(id)
        XCTAssertThrowsError(try store.put(Data([1]), for: tile, area: id)) {
            XCTAssertEqual($0 as? StreetStoreError, .unknownArea)
        }
        XCTAssertEqual(try count(store, "SELECT COUNT(*) FROM area_tiles"), 0)
        XCTAssertEqual(try count(store, "SELECT COUNT(*) FROM tiles"), 0)
    }

    func testFinishingAndDeletingAnAreaEachSaySoOnce() throws {
        let store = try makeStore()
        let id = try store.beginArea(plan(), name: "A")
        var posts = 0
        let observer = NotificationCenter.default.addObserver(forName: StreetStore.didChange, object: store,
                                                              queue: nil) { _ in posts += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        try store.put(Data([1]), for: TileID(z: 3, x: 1, y: 2), area: id)
        XCTAssertEqual(posts, 0, "a tile is not a finished area")
        try store.finishArea(id)
        XCTAssertEqual(posts, 1)
        try store.deleteArea(id)
        XCTAssertEqual(posts, 2)
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

    /// MapLibre opens the store read-only, in this process, with no busy
    /// timeout. Apple's SQLite answers a write made while it holds a read with
    /// SQLITE_IOERR_LOCK, not BUSY; the write must wait, not fail.
    func testAWriteWaitsForAReadOnlyReaderInsteadOfFailing() throws {
        try writeWhileReading(readonly: true)
    }

    /// The BUSY case (any other reader), which `busyMode` waits out.
    func testAWriteWaitsForAReadWriteReaderInsteadOfFailing() throws {
        try writeWhileReading(readonly: false)
    }

    private func writeWhileReading(readonly: Bool) throws {
        let store = try makeStore()
        let id = try store.beginArea(plan(), name: "A")
        var config = Configuration()
        config.readonly = readonly
        let reader = try DatabaseQueue(path: store.fileURL.path, configuration: config)
        let reading = DispatchSemaphore(value: 0)
        let done = expectation(description: "reader finished")
        DispatchQueue.global().async {
            try? reader.inDatabase { db in
                try db.execute(sql: "BEGIN")
                _ = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tiles")   // holds a shared lock
                reading.signal()
                Thread.sleep(forTimeInterval: 0.2)
                try db.execute(sql: "COMMIT")
            }
            done.fulfill()
        }
        reading.wait()
        let started = Date()
        XCTAssertNoThrow(try store.put(Data([1]), for: TileID(z: 3, x: 1, y: 2), area: id))
        XCTAssertGreaterThan(Date().timeIntervalSince(started), 0.05, "the write should have waited for the reader")
        wait(for: [done], timeout: 5)
        XCTAssertTrue(try store.hasTile(TileID(z: 3, x: 1, y: 2), area: id))
    }

    func testAStoreWrittenBeforeTheIndexGainsItOnOpen() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("streets-\(UUID().uuidString).mbtiles")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let old = try DatabaseQueue(path: url.path)
        try old.write { db in
            try db.execute(sql: """
                CREATE TABLE metadata (name TEXT PRIMARY KEY, value TEXT);
                CREATE TABLE tiles (zoom_level INT, tile_column INT, tile_row INT, tile_data BLOB,
                    PRIMARY KEY (zoom_level, tile_column, tile_row));
                CREATE TABLE areas (id TEXT PRIMARY KEY, name TEXT, south REAL, west REAL, north REAL, east REAL,
                    detail_km INT, started_at REAL, finished_at REAL, bytes INT);
                CREATE TABLE area_tiles (area_id TEXT, z INT, x INT, y INT, PRIMARY KEY (area_id, z, x, y));
                """)
        }
        try old.close()
        let indexSQL = "SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' AND name = 'area_tiles_zxy'"
        XCTAssertEqual(try DatabaseQueue(path: url.path).read { try Int.fetchOne($0, sql: indexSQL) }, 0)
        let store = try StreetStore(fileURL: url)
        XCTAssertEqual(try count(store, indexSQL), 1)
    }
}
