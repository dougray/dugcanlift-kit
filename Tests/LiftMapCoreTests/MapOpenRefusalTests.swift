import XCTest
@testable import LiftMapCore

/// A map may not start reading the file once a write has begun: `mapOpened`
/// is decided under the same lock as the gate, and refuses while it is held.
final class MapOpenRefusalTests: XCTestCase {
    private func makeStore() throws -> StreetStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ref-\(UUID().uuidString).mbtiles")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return try StreetStore(fileURL: url)
    }

    private let plan = StreetAreaPlan(latitude: 39.7392, longitude: -104.9903, detailKm: 10)

    func testAMapOpensWhenNothingIsWritten() throws {
        let store = try makeStore()
        XCTAssertTrue(store.mapOpened())
        XCTAssertEqual(store.mapsOpen, 1)
        store.mapClosed()
        XCTAssertEqual(store.mapsOpen, 0)
    }

    func testAMapIsRefusedWhileAWriteIsInProgress() throws {
        let store = try makeStore()
        store.beginWriting()
        XCTAssertFalse(store.mapOpened())
        XCTAssertEqual(store.mapsOpen, 0, "a refused map is not counted")
        store.endWriting()
        XCTAssertTrue(store.mapOpened(), "accepted again once the gate opens")
        store.mapClosed()
    }

    func testARefusalHoldsAcrossStoresOnTheSameFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ref-\(UUID().uuidString).mbtiles")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let writer = try StreetStore(fileURL: url)
        let reader = try StreetStore(fileURL: url)
        writer.beginWriting()
        XCTAssertFalse(reader.mapOpened())
        writer.endWriting()
    }

    /// The race: the map decided to draw before the gate rose, and asks to
    /// open after the writer has already checked that no map was open.
    func testALateMapIsRefusedForTheWholeWrite() async throws {
        let store = try makeStore()
        let id = try store.beginArea(plan, name: "A")
        try await store.whileWriting {
            // Past awaitMapsClosed: no map was open.
            XCTAssertFalse(store.mapOpened(), "the late map must not start reading")
            XCTAssertEqual(store.mapsOpen, 0)
            try store.put(Data([1]), for: TileID(z: 3, x: 1, y: 2), area: id)
            XCTAssertEqual(store.mapsOpen, 0, "no map counted during the write")
        }
        XCTAssertTrue(store.mapOpened())
        store.mapClosed()
    }

    func testARefusedLeaseNeedsNoCloseAndLeavesTheCountAlone() throws {
        let store = try makeStore()
        XCTAssertTrue(store.mapOpened())          // another map, already open
        store.beginWriting()
        var lease = MapLease(store: store)
        XCTAssertFalse(lease.acquire())
        XCTAssertFalse(lease.isHeld)
        lease.release()                           // nothing to give back
        XCTAssertEqual(store.mapsOpen, 1, "the other map's count is untouched")
        store.endWriting()
        store.mapClosed()
        XCTAssertEqual(store.mapsOpen, 0)
    }

    func testALeaseRefusedOnceIsGrantedWhenTheGateOpensAndBalances() throws {
        let store = try makeStore()
        var lease = MapLease(store: store)
        store.beginWriting()
        XCTAssertFalse(lease.acquire())
        store.endWriting()
        XCTAssertTrue(lease.acquire())
        XCTAssertTrue(lease.acquire(), "acquiring a held lease counts nothing more")
        XCTAssertEqual(store.mapsOpen, 1)
        lease.release()
        lease.release()
        XCTAssertEqual(store.mapsOpen, 0)
    }
}
