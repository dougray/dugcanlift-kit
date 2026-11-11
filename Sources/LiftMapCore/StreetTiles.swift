import Foundation
import LiftCore

/// A latitude/longitude box, in degrees.
public struct MapBounds: Equatable, Codable, Sendable {
    public var south: Double
    public var west: Double
    public var north: Double
    public var east: Double

    public init(south: Double, west: Double, north: Double, east: Double) {
        self.south = south
        self.west = west
        self.north = north
        self.east = east
    }

    /// True when the boxes overlap; boxes that only touch at an edge do.
    public func intersects(_ other: MapBounds) -> Bool {
        south <= other.north && north >= other.south && west <= other.east && east >= other.west
    }

    /// The smallest box holding every point; nil for no points. One point
    /// gives a zero-area box.
    public static func around(_ points: [OutdoorShareCoordinate]) -> MapBounds? {
        guard let first = points.first else { return nil }
        var b = MapBounds(south: first.latitude, west: first.longitude,
                          north: first.latitude, east: first.longitude)
        for p in points.dropFirst() {
            b.south = min(b.south, p.latitude)
            b.north = max(b.north, p.latitude)
            b.west = min(b.west, p.longitude)
            b.east = max(b.east, p.longitude)
        }
        return b
    }
}

/// One slippy-map tile. `y` counts from the top (XYZ); MBTiles stores TMS rows.
public struct TileID: Hashable, Sendable {
    public var z: Int
    public var x: Int
    public var y: Int

    public init(z: Int, x: Int, y: Int) {
        self.z = z
        self.x = x
        self.y = y
    }

    public var tmsRow: Int { (1 << z) - 1 - y }
}

/// Slippy-map tile maths for sizing and listing a download. Pure.
public enum StreetTiles {
    /// A square reaching `radiusKm` north, south, east and west of the centre.
    public static func bounds(latitude: Double, longitude: Double, radiusKm: Double) -> MapBounds {
        let dLat = radiusKm / 111.32
        let dLon = radiusKm / (111.32 * max(0.01, cos(latitude * .pi / 180)))
        return MapBounds(south: max(-85.0511, latitude - dLat), west: max(-180, longitude - dLon),
                         north: min(85.0511, latitude + dLat), east: min(180, longitude + dLon))
    }

    public static func x(_ longitude: Double, _ z: Int) -> Int {
        let n = Double(1 << z)
        return min(Int(n) - 1, max(0, Int(floor((longitude + 180) / 360 * n))))
    }

    public static func y(_ latitude: Double, _ z: Int) -> Int {
        let n = Double(1 << z)
        let lat = max(-85.0511, min(85.0511, latitude)) * .pi / 180
        return min(Int(n) - 1, max(0, Int(floor((1 - asinh(tan(lat)) / .pi) / 2 * n))))
    }

    /// Number of tiles covering the bounds at one zoom.
    public static func count(_ b: MapBounds, zoom z: Int) -> Int {
        (x(b.east, z) - x(b.west, z) + 1) * (y(b.south, z) - y(b.north, z) + 1)
    }

    /// Every tile covering the bounds at one zoom.
    public static func tiles(in b: MapBounds, zoom z: Int) -> [TileID] {
        let x0 = x(b.west, z), x1 = x(b.east, z)
        let y0 = y(b.north, z), y1 = y(b.south, z)
        guard x0 <= x1, y0 <= y1 else { return [] }
        var out: [TileID] = []
        out.reserveCapacity((x1 - x0 + 1) * (y1 - y0 + 1))
        for tx in x0 ... x1 {
            for ty in y0 ... y1 { out.append(TileID(z: z, x: tx, y: ty)) }
        }
        return out
    }

    /// Typical OpenFreeMap tile size by zoom, from a sample around a city and
    /// its countryside; real areas vary by half either way.
    public static func typicalBytes(zoom z: Int) -> Int {
        switch z {
        case ...5: 250_000
        case 6 ... 8: 120_000
        case 9 ... 10: 30_000
        case 11 ... 12: 40_000
        case 13: 25_000
        default: 15_000
        }
    }
}
