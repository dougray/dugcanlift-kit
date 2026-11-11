import XCTest
import LiftCore
@testable import LiftMapCore

/// Maps step back while the store is written: MapLibre reads the file in this
/// process with no busy timeout, so it must never read while we write.
final class WriteGateTests: XCTestCase {
    private func makeStore() throws -> StreetStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gate-\(UUID().uuidString).mbtiles")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return try StreetStore(fileURL: url)
    }

    private func session() -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: c)
    }

    private let plan = StreetAreaPlan(latitude: 39.7392, longitude: -104.9903, detailKm: 10)
    private static let good = "https://tiles.openfreemap.org/planet/v1/{z}/{x}/{y}.pbf"
    private var tileJSON: Data { Data(#"{"tiles":["\#(Self.good)"]}"#.utf8) }

    /// Records `isWriting` at every gate notification.
    private func record(_ store: StreetStore) -> (() -> [Bool], NSObjectProtocol) {
        let lock = NSLock()
        var seen: [Bool] = []
        let token = NotificationCenter.default.addObserver(forName: StreetStore.writingDidChange, object: store,
                                                           queue: nil) { _ in
            let now = store.isWriting
            lock.lock(); seen.append(now); lock.unlock()
        }
        addTeardownBlock { NotificationCenter.default.removeObserver(token) }
        return ({ lock.lock(); defer { lock.unlock() }; return seen }, token)
    }

    func testTheGateNests() throws {
        let store = try makeStore()
        XCTAssertFalse(store.isWriting)
        XCTAssertTrue(store.beginWriting())
        XCTAssertFalse(store.beginWriting(), "already closed")
        store.endWriting()
        XCTAssertTrue(store.isWriting, "one hold is left")
        store.endWriting()
        XCTAssertFalse(store.isWriting)
        store.endWriting()   // an end with no begin is ignored
        XCTAssertFalse(store.isWriting)
        XCTAssertTrue(store.beginWriting(), "an extra end must not leave the count below zero")
        store.endWriting()
    }

    func testItSaysSoOnlyWhenTheGateClosesAndOpens() throws {
        let store = try makeStore()
        let (seen, _) = record(store)
        store.beginWriting()
        store.beginWriting()
        store.endWriting()
        store.endWriting()
        store.endWriting()
        XCTAssertEqual(seen(), [true, false])
    }

    func testDeletingAnAreaHoldsTheGate() throws {
        let store = try makeStore()
        let id = try store.beginArea(plan, name: "A")
        let (seen, _) = record(store)
        try store.deleteArea(id)
        XCTAssertEqual(seen(), [true, false])
        XCTAssertFalse(store.isWriting)
    }

    func testADownloadHoldsTheGateThroughout() async throws {
        let store = try makeStore()
        StubProtocol.reset { req in req.url!.path == "/planet" ? (200, self.tileJSON) : (200, Data([1])) }
        let (seen, _) = record(store)
        let lock = NSLock()
        var openDuringProgress = false
        _ = try await MapDownload(store: store, session: session()).download(plan, name: "A") { _, _ in
            if !store.isWriting { lock.lock(); openDuringProgress = true; lock.unlock() }
        }
        XCTAssertFalse(lock.withLock { openDuringProgress }, "the gate opened mid-download")
        XCTAssertEqual(seen(), [true, false], "one session, not one per tile")
        XCTAssertFalse(store.isWriting)
    }

    func testAFailedDownloadReleasesTheGate() async throws {
        let store = try makeStore()
        StubProtocol.reset { _ in (500, Data()) }
        do {
            _ = try await MapDownload(store: store, session: session()).download(plan, name: "A") { _, _ in }
            XCTFail("expected a failure")
        } catch {}
        XCTAssertFalse(store.isWriting)
    }

    func testACancelledDownloadReleasesTheGate() async throws {
        let store = try makeStore()
        StubProtocol.reset { req in
            if req.url!.path == "/planet" { return (200, self.tileJSON) }
            Thread.sleep(forTimeInterval: 0.05)
            return (200, Data([1]))
        }
        let task = Task { try await MapDownload(store: store, session: session()).download(plan, name: "A") { _, _ in } }
        let deadline = Date().addingTimeInterval(5)
        while !store.isWriting && Date() < deadline { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertTrue(store.isWriting)
        try await Task.sleep(nanoseconds: 400_000_000)   // past the settle, into the tiles
        task.cancel()
        _ = await task.result
        XCTAssertFalse(store.isWriting)
    }

    func testTheRouteIsALineWhileTheStoreIsWritten() {
        let points = [OutdoorShareCoordinate(latitude: 39.74, longitude: -104.99),
                      OutdoorShareCoordinate(latitude: 39.75, longitude: -104.98)]
        XCTAssertEqual(RouteMapDecision.decide(points: points, writing: true, covered: { _ in true }), .line)
        XCTAssertEqual(RouteMapDecision.decide(points: points, writing: false, covered: { _ in true }), .map)
        XCTAssertEqual(RouteMapDecision.decide(points: points, writing: false, covered: { _ in false }), .line)
    }
}
