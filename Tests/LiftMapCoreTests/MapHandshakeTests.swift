import XCTest
@testable import LiftMapCore

/// A writer raises the gate, waits for maps drawing the file to close, then
/// writes; and every store open on one file shares the gate and the count.
final class MapHandshakeTests: XCTestCase {
    private func makeURL() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hs-\(UUID().uuidString).mbtiles")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private let plan = StreetAreaPlan(latitude: 39.7392, longitude: -104.9903, detailKm: 10)

    private final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func add(_ s: String) { lock.lock(); items.append(s); lock.unlock() }
        var all: [String] { lock.lock(); defer { lock.unlock() }; return items }
    }

    func testTwoStoresOnOneFileShareTheGate() throws {
        let url = makeURL()
        let a = try StreetStore(fileURL: url)
        let b = try StreetStore(fileURL: url)
        var toldB = 0
        let token = NotificationCenter.default.addObserver(forName: StreetStore.writingDidChange, object: b,
                                                           queue: nil) { _ in toldB += 1 }
        defer { NotificationCenter.default.removeObserver(token) }
        a.beginWriting()
        XCTAssertTrue(b.isWriting)
        XCTAssertFalse(b.beginWriting(), "the gate is already closed, by the other store")
        b.endWriting()
        XCTAssertTrue(a.isWriting)
        a.endWriting()
        XCTAssertFalse(b.isWriting)
        XCTAssertEqual(toldB, 2, "a store is told when another store on its file closes and opens the gate")
        b.mapOpened()
        XCTAssertEqual(a.mapsOpen, 1)
        a.mapClosed()
        XCTAssertEqual(b.mapsOpen, 0)
    }

    func testAnotherStoresDeleteIsHeardToo() throws {
        let url = makeURL()
        let a = try StreetStore(fileURL: url)
        let b = try StreetStore(fileURL: url)
        let id = try a.beginArea(plan, name: "A")
        var toldB = 0
        let token = NotificationCenter.default.addObserver(forName: StreetStore.didChange, object: b,
                                                           queue: nil) { _ in toldB += 1 }
        defer { NotificationCenter.default.removeObserver(token) }
        try a.deleteArea(id)
        XCTAssertEqual(toldB, 1)
    }

    func testMapsOpenAndCloseBalance() throws {
        let store = try StreetStore(fileURL: makeURL())
        store.mapOpened()
        store.mapOpened()
        store.mapClosed()
        XCTAssertEqual(store.mapsOpen, 1)
        store.mapClosed()
        store.mapClosed()   // an extra close is ignored
        XCTAssertEqual(store.mapsOpen, 0)
        store.mapOpened()
        XCTAssertEqual(store.mapsOpen, 1, "an extra close must not leave the count below zero")
        store.mapClosed()
    }

    func testWithNoMapOpenItReturnsAtOnce() async throws {
        let store = try StreetStore(fileURL: makeURL())
        let started = ContinuousClock.now
        await store.awaitMapsClosed()
        XCTAssertLessThan(ContinuousClock.now - started, .milliseconds(50))
    }

    func testItWaitsForTheLastMapToClose() async throws {
        let store = try StreetStore(fileURL: makeURL())
        store.mapOpened()
        let started = ContinuousClock.now
        Task.detached {
            try await Task.sleep(for: .milliseconds(150))
            store.mapClosed()
        }
        await store.awaitMapsClosed(timeout: .seconds(5))
        let waited = ContinuousClock.now - started
        XCTAssertEqual(store.mapsOpen, 0)
        XCTAssertGreaterThanOrEqual(waited, .milliseconds(140))
        XCTAssertLessThan(waited, .seconds(2))
    }

    func testItGivesUpAfterTheTimeout() async throws {
        let store = try StreetStore(fileURL: makeURL())
        store.mapOpened()
        defer { store.mapClosed() }
        let started = ContinuousClock.now
        await store.awaitMapsClosed(timeout: .milliseconds(150))
        let waited = ContinuousClock.now - started
        XCTAssertEqual(store.mapsOpen, 1, "the map is still open; the writer goes ahead anyway")
        XCTAssertGreaterThanOrEqual(waited, .milliseconds(140))
        XCTAssertLessThan(waited, .seconds(2))
    }

    func testCancellingTheWaitReturnsPromptly() async throws {
        let store = try StreetStore(fileURL: makeURL())
        store.mapOpened()
        defer { store.mapClosed() }
        let waiter = Task { await store.awaitMapsClosed(timeout: .seconds(30)) }
        try await Task.sleep(for: .milliseconds(50))
        let started = ContinuousClock.now
        waiter.cancel()
        await waiter.value
        XCTAssertLessThan(ContinuousClock.now - started, .milliseconds(500))
    }

    func testAWriterWritesNothingUntilTheMapCloses() async throws {
        let store = try StreetStore(fileURL: makeURL())
        let id = try store.beginArea(plan, name: "A")
        store.mapOpened()
        let log = Log()
        let writer = Task.detached {
            try await store.whileWriting {
                log.add("write")
                try store.put(Data([1]), for: TileID(z: 3, x: 1, y: 2), area: id)
            }
        }
        // The gate is raised first, before the wait.
        let deadline = ContinuousClock.now + .seconds(2)
        while !store.isWriting && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(store.isWriting)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(log.all, [], "no write while a map is open")
        XCTAssertFalse(try store.hasTile(TileID(z: 3, x: 1, y: 2), area: id))
        log.add("closed")
        store.mapClosed()
        try await writer.value
        XCTAssertEqual(log.all, ["closed", "write"])
        XCTAssertTrue(try store.hasTile(TileID(z: 3, x: 1, y: 2), area: id))
        XCTAssertFalse(store.isWriting)
    }
}
