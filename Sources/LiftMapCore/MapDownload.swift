import Foundation

public enum MapDownloadError: Error, Equatable {
    case badTemplate
    case refusedHost
    case http(Int)
}

extension URLSession {
    /// No cookies, no cache, a plain User-Agent: nothing here identifies the person or the app.
    public static let ephemeralNoCookies: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieAcceptPolicy = .never
        c.httpShouldSetCookies = false
        c.urlCache = nil
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.httpAdditionalHeaders = ["User-Agent": "LIFT-maps/1"]
        return URLSession(configuration: c)
    }()
}

/// Refuses any redirect that leaves the host or the https scheme; the 3xx then
/// comes back as the response and reads as `http(status)`. A redirect to
/// another https path on the same host is followed. The web module
/// (`map/web/map.js`) refuses every redirect, so a same-host redirect that
/// OpenFreeMap might add one day would break only the web download.
private final class StayOnHost: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(MapDownload.allowed(request.url) == nil ? nil : request)
    }
}

/// The one request this package may make, and only when the person starts a
/// street-map download: the TileJSON and the tiles, from `host`, nothing else.
public actor MapDownload {
    public static let host = "tiles.openfreemap.org"
    static let maxInFlight = 4

    private let store: StreetStore
    private let session: URLSession

    public init(store: StreetStore, session: URLSession = .ephemeralNoCookies) {
        self.store = store
        self.session = session
    }

    static func allowed(_ url: URL?) -> URL? {
        guard let url, url.scheme == "https", url.host == host else { return nil }
        return url
    }

    private func fetch(_ url: URL) async throws -> (Int, Data) {
        guard let url = Self.allowed(url) else { throw MapDownloadError.refusedHost }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("LIFT-maps/1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request, delegate: StayOnHost())
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (status, data)
    }

    /// The versioned tile URL template from OpenFreeMap's TileJSON.
    public func tileTemplate() async throws -> String {
        let (status, data) = try await fetch(URL(string: "https://\(Self.host)/planet")!)
        guard (200 ..< 300).contains(status) else { throw MapDownloadError.http(status) }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tiles = json["tiles"] as? [String], let first = tiles.first,
              first.contains("{z}"), first.contains("{x}"), first.contains("{y}") else {
            throw MapDownloadError.badTemplate
        }
        let probe = first.replacingOccurrences(of: "{z}", with: "0")
            .replacingOccurrences(of: "{x}", with: "0").replacingOccurrences(of: "{y}", with: "0")
        guard Self.allowed(URL(string: probe)) != nil else { throw MapDownloadError.refusedHost }
        return first
    }

    public func download(_ plan: StreetAreaPlan, name: String,
                         progress: @Sendable (Int, Int) -> Void) async throws -> StreetArea {
        let id = try store.beginArea(plan, name: name)
        return try await run(id, plan: plan, progress: progress)
    }

    public func resume(_ areaID: UUID, plan: StreetAreaPlan,
                       progress: @Sendable (Int, Int) -> Void) async throws -> StreetArea {
        try await run(areaID, plan: plan, progress: progress)
    }

    private func run(_ id: UUID, plan: StreetAreaPlan,
                     progress: @Sendable (Int, Int) -> Void) async throws -> StreetArea {
        let template = try await tileTemplate()
        let total = plan.tiles.count
        var done = 0
        var pending: [TileID] = []
        for tile in plan.tiles {
            if try store.hasTile(tile, area: id) { done += 1 } else { pending.append(tile) }
        }
        progress(done, total)

        try await withThrowingTaskGroup(of: Void.self) { group in
            var next = 0
            func launch() {
                let tile = pending[next]
                next += 1
                group.addTask { [self] in try await self.fetchTile(tile, template: template, area: id) }
            }
            while next < pending.count && next < Self.maxInFlight { launch() }
            while try await group.next() != nil {
                done += 1
                progress(done, total)
                if next < pending.count { launch() }
            }
        }

        try store.finishArea(id)
        guard let area = try store.areas().first(where: { $0.id == id }) else { throw MapDownloadError.badTemplate }
        return area
    }

    private func fetchTile(_ tile: TileID, template: String, area: UUID) async throws {
        let text = template.replacingOccurrences(of: "{z}", with: String(tile.z))
            .replacingOccurrences(of: "{x}", with: String(tile.x))
            .replacingOccurrences(of: "{y}", with: String(tile.y))
        guard let url = URL(string: text) else { throw MapDownloadError.badTemplate }
        let (status, data) = try await fetch(url)
        switch status {
        case 200 ..< 300: try store.put(data, for: tile, area: area)
        case 404, 204: try store.put(Data(), for: tile, area: area)   // the sea: nothing there
        default: throw MapDownloadError.http(status)
        }
    }
}
