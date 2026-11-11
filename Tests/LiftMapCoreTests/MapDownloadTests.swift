import XCTest
@testable import LiftMapCore

/// Serves a TileJSON and tiles without a network. Registered on an ephemeral
/// configuration the test passes to `MapDownload`.
final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data, String?))?
    nonisolated(unsafe) static var seen: [URLRequest] = []
    private static let lock = NSLock()

    static func reset(_ h: @escaping (URLRequest) -> (Int, Data)) { reset3 { let r = h($0); return (r.0, r.1, nil) } }
    static func resetRedirecting(_ h: @escaping (URLRequest) -> (Int, Data, String?)) { reset3(h) }
    private static func reset3(_ h: @escaping (URLRequest) -> (Int, Data, String?)) {
        lock.lock(); defer { lock.unlock() }
        handler = h; seen = []
    }
    static var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return seen }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.seen.append(request)
        let h = Self.handler
        Self.lock.unlock()
        let (status, body, location) = h?(request) ?? (500, Data(), nil)
        let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                   headerFields: location.map { ["Location": $0] })!
        if let location, let to = URL(string: location) {
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: to), redirectResponse: resp)
            // A refused redirect delivers the 3xx itself, as the real loader does.
        }
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class MapDownloadTests: XCTestCase {
    private func makeStore() throws -> StreetStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dl-\(UUID().uuidString).mbtiles")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return try StreetStore(fileURL: url)
    }

    private func session() -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: c)
    }

    private let plan = StreetAreaPlan(latitude: 39.7392, longitude: -104.9903, detailKm: 10)

    private func tileJSON(_ template: String) -> Data {
        Data(#"{"tiles":["\#(template)"]}"#.utf8)
    }

    private static let good = "https://tiles.openfreemap.org/planet/v1/{z}/{x}/{y}.pbf"

    func testTheTemplateMustBeOpenFreeMaps() async throws {
        StubProtocol.reset { _ in (200, self.tileJSON("https://evil.example/{z}/{x}/{y}.pbf")) }
        let dl = MapDownload(store: try makeStore(), session: session())
        do {
            _ = try await dl.download(plan, name: "X") { _, _ in }
            XCTFail("expected refusedHost")
        } catch MapDownloadError.refusedHost {
        }
        XCTAssertEqual(StubProtocol.requests.count, 1, "no tile may be fetched")
    }

    func testAnUnfinishedDownloadIsNotAnArea() async throws {
        let store = try makeStore()
        let bad = plan.tiles[4]
        let badPath = "/planet/v1/\(bad.z)/\(bad.x)/\(bad.y).pbf"
        StubProtocol.reset { req in
            if req.url!.path == "/planet" { return (200, self.tileJSON(Self.good)) }
            if req.url!.path == badPath { return (500, Data()) }
            return (200, Data([1, 2, 3]))
        }
        let dl = MapDownload(store: store, session: session())
        do {
            _ = try await dl.download(plan, name: "X") { _, _ in }
            XCTFail("expected a failure")
        } catch MapDownloadError.http(let s) {
            XCTAssertEqual(s, 500)
        }
        XCTAssertEqual(try store.areas().count, 0)

        // The failed run left exactly one unfinished area, which resume picks up.
        let unfinished = try store.unfinishedAreas()
        XCTAssertEqual(unfinished.count, 1)
        let id = try XCTUnwrap(unfinished.first).id
        var stored: [TileID] = []
        for t in plan.tiles where try store.hasTile(t, area: id) { stored.append(t) }
        StubProtocol.reset { req in
            req.url!.path == "/planet" ? (200, self.tileJSON(Self.good)) : (200, Data([1, 2, 3]))
        }
        let area = try await dl.resume(id, plan: plan) { _, _ in }
        XCTAssertEqual(try store.areas().map(\.id), [area.id])
        let tilePaths = StubProtocol.requests.map { $0.url!.path }.filter { $0 != "/planet" }
        XCTAssertEqual(tilePaths.count, plan.tiles.count - stored.count)
        for t in stored { XCTAssertFalse(tilePaths.contains("/planet/v1/\(t.z)/\(t.x)/\(t.y).pbf")) }
    }

    func testARedirectOffTheHostIsRefused() async throws {
        let evil = "https://evil.example/x"
        StubProtocol.resetRedirecting { req in
            if req.url!.host == "evil.example" { return (200, Data("{}".utf8), nil) }
            return (302, Data(), evil)
        }
        let dl = MapDownload(store: try makeStore(), session: session())
        do { _ = try await dl.tileTemplate(); XCTFail("expected http(302)") }
        catch MapDownloadError.http(let s) { XCTAssertEqual(s, 302) }
        XCTAssertFalse(StubProtocol.requests.contains { $0.url?.host == "evil.example" })

        StubProtocol.resetRedirecting { req in
            if req.url!.host == "evil.example" { return (200, Data([1]), nil) }
            if req.url!.path == "/planet" { return (200, self.tileJSON(Self.good), nil) }
            return (302, Data(), "http://tiles.openfreemap.org/downgrade")
        }
        do { _ = try await dl.download(plan, name: "X") { _, _ in }; XCTFail("expected http(302)") }
        catch MapDownloadError.http(let s) { XCTAssertEqual(s, 302) }
        XCTAssertFalse(StubProtocol.requests.contains { $0.url?.host == "evil.example" || $0.url?.scheme == "http" })
    }

    func testAMissingTileIsStoredEmptyAndTheAreaFinishes() async throws {
        let store = try makeStore()
        StubProtocol.reset { req in
            if req.url!.path == "/planet" { return (200, self.tileJSON(Self.good)) }
            return (req.url!.path.hasSuffix("/0/0/0.pbf") ? 404 : 204, Data())
        }
        let dl = MapDownload(store: store, session: session())
        let area = try await dl.download(plan, name: "X") { _, _ in }
        XCTAssertTrue(try store.hasTile(plan.tiles[0], area: area.id))
    }

    func testEveryRequestGoesToOneHost() async throws {
        StubProtocol.reset { req in
            req.url!.path == "/planet" ? (200, self.tileJSON(Self.good)) : (200, Data([7]))
        }
        let dl = MapDownload(store: try makeStore(), session: session())
        _ = try await dl.download(plan, name: "X") { _, _ in }
        let reqs = StubProtocol.requests
        XCTAssertEqual(reqs.count, plan.tiles.count + 1)
        for r in reqs {
            XCTAssertEqual(r.url?.host, "tiles.openfreemap.org")
            XCTAssertEqual(r.url?.scheme, "https")
        }
    }

    func testNoCookiesAndAPlainUserAgent() async throws {
        StubProtocol.reset { req in
            req.url!.path == "/planet" ? (200, self.tileJSON(Self.good)) : (200, Data([7]))
        }
        let dl = MapDownload(store: try makeStore(), session: session())
        _ = try await dl.download(plan, name: "X") { _, _ in }
        for r in StubProtocol.requests {
            XCTAssertNil(r.value(forHTTPHeaderField: "Cookie"))
            XCTAssertEqual(r.value(forHTTPHeaderField: "User-Agent"), "LIFT-maps/1")
        }
    }

    func testProgressReachesTotal() async throws {
        StubProtocol.reset { req in
            req.url!.path == "/planet" ? (200, self.tileJSON(Self.good)) : (200, Data([7]))
        }
        let last = LockedBox<(Int, Int)>((0, 0))
        let dl = MapDownload(store: try makeStore(), session: session())
        _ = try await dl.download(plan, name: "X") { d, t in last.set((d, t)) }
        XCTAssertEqual(last.get().0, plan.tiles.count)
        XCTAssertEqual(last.get().1, plan.tiles.count)
    }
}

final class LockedBox<T>: @unchecked Sendable {
    private var v: T
    private let l = NSLock()
    init(_ v: T) { self.v = v }
    func set(_ n: T) { l.lock(); v = n; l.unlock() }
    func get() -> T { l.lock(); defer { l.unlock() }; return v }
}
