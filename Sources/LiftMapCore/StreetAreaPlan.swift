import Foundation

/// What a street-map download covers: a wide, coarse layer (zoom 0-10) and a
/// detailed one (zoom 11-14), and the tiles and size that come to.
public struct StreetAreaPlan: Equatable, Sendable {
    public static let wideKm = 100
    public static let wideZooms = 0 ... 10
    public static let detailZooms = 11 ... 14
    public static let detailChoices = [10, 25, 50]

    public private(set) var latitude: Double
    public private(set) var longitude: Double
    /// The detail radius chosen; 0 for a route plan, which is not a radius.
    public private(set) var detailKm: Int
    public private(set) var wide: MapBounds
    public private(set) var detail: MapBounds
    public private(set) var tiles: [TileID]
    public private(set) var estimatedBytes: Int

    public init(latitude: Double, longitude: Double, detailKm: Int) {
        self.init(latitude: latitude, longitude: longitude, detailKm: detailKm,
                  wide: StreetTiles.bounds(latitude: latitude, longitude: longitude, radiusKm: Double(Self.wideKm)),
                  detail: StreetTiles.bounds(latitude: latitude, longitude: longitude, radiusKm: Double(detailKm)))
    }

    private init(latitude: Double, longitude: Double, detailKm: Int, wide: MapBounds, detail: MapBounds) {
        self.latitude = latitude
        self.longitude = longitude
        self.detailKm = detailKm
        self.wide = wide
        self.detail = detail
        var all: [TileID] = []
        for z in Self.wideZooms { all += StreetTiles.tiles(in: wide, zoom: z) }
        for z in Self.detailZooms { all += StreetTiles.tiles(in: detail, zoom: z) }
        self.tiles = all
        self.estimatedBytes = all.reduce(0) { $0 + StreetTiles.typicalBytes(zoom: $1.z) }
    }

    /// Coach: the route's bounds grown 2 km on every side, with the wide
    /// layer 100 km around its centre.
    public static func forRoute(_ bounds: MapBounds) -> StreetAreaPlan {
        let centerLat = (bounds.south + bounds.north) / 2
        let centerLon = (bounds.west + bounds.east) / 2
        let dLat = 2 / 111.32
        let dLon = 2 / (111.32 * max(0.01, cos(centerLat * .pi / 180)))
        let detail = MapBounds(south: max(-85.0511, bounds.south - dLat), west: max(-180, bounds.west - dLon),
                               north: min(85.0511, bounds.north + dLat), east: min(180, bounds.east + dLon))
        let wide = StreetTiles.bounds(latitude: centerLat, longitude: centerLon, radiusKm: Double(wideKm))
        return StreetAreaPlan(latitude: centerLat, longitude: centerLon, detailKm: 0, wide: wide, detail: detail)
    }
}
