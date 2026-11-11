import Foundation
#if canImport(MapLibre) && os(iOS)
import MapLibre
#endif

/// Makes sure MapLibre itself can never reach a server. Every style this kit
/// writes names only local files (`mbtiles://` and `file://`), so a map has
/// nothing to fetch; this is the second lock, in case MapLibre ever asks
/// anyway (its default style, an unexpected source). Every request through
/// MapLibre's own session fails at once as "not connected", so nothing leaves
/// the device. The street-map download is not MapLibre's and has its own
/// session (`MapDownload`), so it is unaffected.
///
/// Apps call `install()` once at launch, before any map is made; `RouteMap`
/// calls it too, so a map is never made without it. Calling it again does
/// nothing.
public enum MapNetworkGuard {
    public static func install() {
        _ = installed
    }

    private static let installed: Void = {
        #if canImport(MapLibre) && os(iOS)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RefuseEveryRequest.self]
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.waitsForConnectivity = false
        MLNNetworkConfiguration.sharedManager.sessionConfiguration = configuration
        #endif
    }()
}

/// Answers every request with "not connected to the internet", without
/// opening a connection.
final class RefuseEveryRequest: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}
