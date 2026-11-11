import Foundation

/// The street styles, filled with this device's own files. No server is named.
public enum MapStyle {
    public struct MissingResource: Error { public let name: String }

    static var resourceRoot: URL {
        Bundle.module.resourceURL!.appendingPathComponent("Resources", isDirectory: true)
    }

    /// `mbtiles://` plus the percent-encoded path; MapLibre decodes it again.
    public static func mbtilesURL(for fileURL: URL) -> String {
        let path = fileURL.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileURL.path
        return "mbtiles://" + path
    }

    /// The bundled fonts directory as a file URL; `{fontstack}` and `{range}` stay literal.
    public static var glyphsURL: String {
        let dir = resourceRoot.appendingPathComponent("fonts", isDirectory: true).path
        let encoded = dir.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? dir
        return "file://" + encoded + "/{fontstack}/{range}.pbf"
    }

    public static func json(dark: Bool, storeURL: URL) throws -> Data {
        let name = dark ? "style-dark.json" : "style-light.json"
        let url = resourceRoot.appendingPathComponent(name)
        guard let template = try? String(contentsOf: url, encoding: .utf8) else {
            throw MissingResource(name: name)
        }
        let filled = template
            .replacingOccurrences(of: "{{TILES}}", with: mbtilesURL(for: storeURL))
            .replacingOccurrences(of: "{{GLYPHS}}", with: glyphsURL)
        return Data(filled.utf8)
    }
}
