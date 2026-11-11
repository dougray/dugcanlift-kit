import XCTest
import CryptoKit
import LiftCore
@testable import LiftMapCore

final class MapStyleTests: XCTestCase {
    func testStyleURLPercentEncodesTheStorePath() {
        let url = URL(fileURLWithPath: "/tmp/Application Support/LiftMap/streets.mbtiles")
        XCTAssertEqual(MapStyle.mbtilesURL(for: url),
                       "mbtiles:///tmp/Application%20Support/LiftMap/streets.mbtiles")
    }

    func testFilledStyleNamesNoServer() throws {
        let store = URL(fileURLWithPath: "/tmp/Application Support/x.mbtiles")
        for dark in [false, true] {
            let data = try MapStyle.json(dark: dark, storeURL: store)
            let text = String(decoding: data, as: UTF8.self)
            XCTAssertFalse(text.contains("http"))
            XCTAssertFalse(text.contains("{{"))
            XCTAssertTrue(text.contains("mbtiles:///tmp/Application%20Support/x.mbtiles"))
            XCTAssertTrue(text.contains("file://"))
            XCTAssertTrue(text.contains("/{fontstack}/{range}.pbf"))
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data))
        }
    }

    func testGlyphsURLKeepsItsTokens() {
        XCTAssertTrue(MapStyle.glyphsURL.hasPrefix("file://"))
        XCTAssertTrue(MapStyle.glyphsURL.hasSuffix("/fonts/{fontstack}/{range}.pbf"))
    }

    func testTheBundledStylesAreTheSharedFiles() throws {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) {
            let parent = dir.deletingLastPathComponent()
            XCTAssertNotEqual(parent, dir, "no Package.swift above the test file")
            if parent == dir { return }
            dir = parent
        }
        let sums = try String(contentsOf: dir.appendingPathComponent("map/map-files.sha256"), encoding: .utf8)
        let bundled = MapStyle.resourceRoot
        var checked = 0
        for line in sums.split(separator: "\n") where !line.isEmpty {
            let parts = line.components(separatedBy: "  ")
            XCTAssertEqual(parts.count, 2, "bad line \(line)")
            let path = parts[1]
            guard path.hasPrefix("fonts/") || path.hasPrefix("style-") else { continue }
            let data = try Data(contentsOf: bundled.appendingPathComponent(path))
            let hex = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(hex, parts[0], "\(path) differs from the kit's shared copy")
            checked += 1
        }
        XCTAssertGreaterThanOrEqual(checked, 8)
    }

    /// MapLibre never finishes laying out a tile whose glyph range is missing,
    /// so every range ships, in the kit's shared copy and in the bundle: an
    /// empty file where Noto Sans has nothing is no glyphs, not a blank tile.
    func testEveryGlyphRangeShipsInBothPlaces() throws {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) {
            let parent = dir.deletingLastPathComponent()
            XCTAssertNotEqual(parent, dir, "no Package.swift above the test file")
            if parent == dir { return }
            dir = parent
        }
        let places = [dir.appendingPathComponent("map/fonts/Noto Sans Regular"),
                      MapStyle.resourceRoot.appendingPathComponent("fonts/Noto Sans Regular")]
        for place in places {
            var missing: [String] = []
            for start in stride(from: 0, through: 65280, by: 256) {
                let name = "\(start)-\(start + 255).pbf"
                if !FileManager.default.fileExists(atPath: place.appendingPathComponent(name).path) { missing.append(name) }
            }
            XCTAssertEqual(missing, [], place.path)
            let pbfs = try FileManager.default.contentsOfDirectory(atPath: place.path).filter { $0.hasSuffix(".pbf") }
            XCTAssertEqual(pbfs.count, 256, place.path)
        }
    }
}

final class RouteMapDecisionTests: XCTestCase {
    private let a = OutdoorShareCoordinate(latitude: 39.74, longitude: -104.99)
    private let b = OutdoorShareCoordinate(latitude: 39.75, longitude: -104.98)

    func testOnePointIsALine() {
        XCTAssertEqual(RouteMapDecision.decide(points: [a], covered: { _ in true }), .line)
        XCTAssertEqual(RouteMapDecision.decide(points: [], covered: { _ in true }), .line)
    }
    func testCoveredIsAMap() {
        XCTAssertEqual(RouteMapDecision.decide(points: [a, b], covered: { _ in true }), .map)
    }
    func testNotCoveredIsALine() {
        XCTAssertEqual(RouteMapDecision.decide(points: [a, b], covered: { _ in false }), .line)
    }
}
