import Foundation

/// One run, walk or hike, as the share encoder needs to see it — nothing more.
///
/// Deliberately not a SwiftData model and not LIFT's own `OutdoorActivity`:
/// LiftCore must stay linkable by a widget, and a sender maps its own storage
/// into this at send time. Android's backup `outdoor[]` shape is what the
/// field names follow, so the shared fixture maps across without translation.
public struct OutdoorShareActivity: Equatable, Sendable {
    /// 0 run, 1 walk, 2 hike — the wire's numbering. Anything else is skipped
    /// by every function in `OutdoorShare`, since no reader could label it.
    public var type: Int
    public var startedAtEpochMs: Int64
    /// Nil while still recording. An unfinished activity is never sent.
    public var endedAtEpochMs: Int64?
    public var distanceMeters: Double
    public var climbMeters: Double
    public var route: [OutdoorShareCoordinate]

    public init(type: Int, startedAtEpochMs: Int64, endedAtEpochMs: Int64?,
                distanceMeters: Double, climbMeters: Double,
                route: [OutdoorShareCoordinate] = []) {
        self.type = type
        self.startedAtEpochMs = startedAtEpochMs
        self.endedAtEpochMs = endedAtEpochMs
        self.distanceMeters = distanceMeters
        self.climbMeters = climbMeters
        self.route = route
    }
}

/// A route point, in degrees. Altitude, time and accuracy never leave the
/// device in a share, so they are not carried here.
public struct OutdoorShareCoordinate: Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Builds the outdoor parts of a share link — a day's `o`, the all-time `ob`
/// and the opt-in `lr` — and reads a route's polyline back.
///
/// A port of LIFT web's `lift/outdoor.js` (`shareDay`, `shareBests`,
/// `shareLastRoute` and their helpers), matched operation for operation
/// rather than re-derived, because three platforms must produce the same
/// string for the same run. `outdoor-share-expected.json`, written by that
/// JavaScript, is the test; agreement with this file alone proves nothing.
public enum OutdoorShare {

    /// Earth radius for haversine, as `SHARE-FORMAT.md` fixes it. A different
    /// radius moves the 200 m trim boundary, and with it the polyline.
    public static let earthRadiusMeters = 6_371_000.0
    /// Distance hidden at each end of a shared route. A route usually starts
    /// and ends at someone's front door.
    public static let trimMeters = 200.0
    /// Enough to draw a route recognisably and keep the link a few KB.
    public static let maxSharedPoints = 150
    /// Shorter than this and a pace is mostly GPS noise.
    public static let minimumPaceDistanceMeters = 1000.0

    private static let knownTypes = 0...2

    // MARK: - The three wire parts

    /// A day's `o`: every finished activity of a known type, in start order.
    /// The caller decides which activities belong to the day.
    public static func day(_ activities: [OutdoorShareActivity]) -> [WireOutdoorActivity] {
        activities.enumerated()
            .filter { $0.element.endedAtEpochMs != nil && knownTypes.contains($0.element.type) }
            // Index as the tiebreak: JavaScript's sort is stable and Swift's
            // is not promised to be, and two starts in the same millisecond
            // must come out in the same order on both.
            .sorted { ($0.element.startedAtEpochMs, $0.offset) < ($1.element.startedAtEpochMs, $1.offset) }
            .map { _, a in
                WireOutdoorActivity(type: a.type,
                                    durationSec: roundHalfUp(durationSeconds(a) ?? 0),
                                    distanceMeters: roundHalfUp(a.distanceMeters),
                                    climbMeters: roundHalfUp(a.climbMeters))
            }
    }

    /// `ob`, or nil when nothing is finished — an empty array is never sent.
    /// Pass every activity the client has, not just the window's.
    public static func bests(_ activities: [OutdoorShareActivity]) -> [WireOutdoorBest]? {
        let finished = activities.filter { $0.endedAtEpochMs != nil }
        let out = knownTypes.compactMap { type -> WireOutdoorBest? in
            let ofType = finished.filter { $0.type == type }
            guard !ofType.isEmpty else { return nil }
            // Only positive values count. No distance recorded is no
            // farthest, not a farthest of 0.
            let farthest = ofType.map(\.distanceMeters).filter { $0 > 0 }.max()
            let longestMs = ofType.compactMap(durationMs).filter { $0 > 0 }.max()
            let fastest = ofType
                .filter { $0.distanceMeters >= minimumPaceDistanceMeters }
                .compactMap(paceSecondsPerMeter)
                .filter { $0 > 0 }
                .min()
            return WireOutdoorBest(
                type: type,
                count: ofType.count,
                farthestMeters: farthest.map(roundHalfUp),
                longestSec: longestMs.map { roundHalfUp(Double($0) / 1000) },
                fastestSecPerKm: fastest.map { roundHalfUp($0 * 1000) }
            )
        }
        return out.isEmpty ? nil : out
    }

    /// `lr`, or nil when there is no finished route or nothing survives the
    /// trim. Deliberately no fallback to an older route: a client who sees
    /// "last route" expects that run, not one from last month. Send it only
    /// when the client has opted in; this function does not know the setting.
    public static func lastRoute(_ activities: [OutdoorShareActivity]) -> WireLastRoute? {
        // Newest start wins; the first of equal starts wins, as it does after
        // JavaScript's stable descending sort.
        var newest: OutdoorShareActivity?
        for a in activities where a.endedAtEpochMs != nil && a.route.count > 1 && knownTypes.contains(a.type) {
            if newest == nil || a.startedAtEpochMs > newest!.startedAtEpochMs { newest = a }
        }
        guard let last = newest else { return nil }
        let kept = trimAndThin(last.route)
        guard kept.count >= 2 else { return nil }
        return WireLastRoute(
            type: last.type,
            // Floor, not round: an epoch second is a truncation everywhere else.
            startedAtEpochSec: Int((Double(last.startedAtEpochMs) / 1000).rounded(.down)),
            durationSec: roundHalfUp(durationSeconds(last) ?? 0),
            distanceMeters: roundHalfUp(last.distanceMeters),
            climbMeters: roundHalfUp(last.climbMeters),
            polyline: encodePolyline(kept)
        )
    }

    // MARK: - Route geometry

    /// Great-circle distance, written in the same operation order as the
    /// JavaScript so the running sums near the trim boundary agree.
    public static func haversineMeters(_ from: OutdoorShareCoordinate, _ to: OutdoorShareCoordinate) -> Double {
        let p1 = from.latitude * .pi / 180, p2 = to.latitude * .pi / 180
        let dp = (to.latitude - from.latitude) * .pi / 180
        let dl = (to.longitude - from.longitude) * .pi / 180
        let a = sin(dp / 2) * sin(dp / 2)
            + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return earthRadiusMeters * 2 * atan2(a.squareRoot(), (1 - a).squareRoot())
    }

    /// Drops every point within 200 m of path distance from either end, then
    /// thins what is left to at most 150 evenly spaced points. Empty for a
    /// route of fewer than two points.
    public static func trimAndThin(_ route: [OutdoorShareCoordinate]) -> [OutdoorShareCoordinate] {
        let n = route.count
        guard n >= 2 else { return [] }
        var along = [0.0]
        along.reserveCapacity(n)
        for i in 1..<n {
            along.append(along[i - 1] + haversineMeters(route[i - 1], route[i]))
        }
        let total = along[n - 1]
        let kept = route.indices
            .filter { along[$0] >= trimMeters && total - along[$0] >= trimMeters }
            .map { route[$0] }
        guard kept.count > maxSharedPoints else { return kept }
        return (0..<maxSharedPoints).map { i in
            let index = (Double(i * (kept.count - 1)) / Double(maxSharedPoints - 1) + 0.5).rounded(.down)
            return kept[Int(index)]
        }
    }

    /// Google's encoded polyline at precision 5. Each coordinate is rounded as
    /// `floor(value * 100000 + 0.5)`, which the format spells out because
    /// `Double.rounded()` sends -0.5 away from zero and JavaScript's
    /// `Math.round` sends it up — the same point would encode differently.
    public static func encodePolyline(_ points: [OutdoorShareCoordinate]) -> String {
        var out = [UInt8]()
        var previousLat = 0, previousLon = 0

        func chunk(_ value: Int) {
            var v = value < 0 ? ~(value << 1) : value << 1
            while v >= 0x20 {
                out.append(UInt8((0x20 | (v & 0x1f)) + 63))
                v >>= 5
            }
            out.append(UInt8(v + 63))
        }

        for point in points {
            let lat = Int((point.latitude * 100_000 + 0.5).rounded(.down))
            let lon = Int((point.longitude * 100_000 + 0.5).rounded(.down))
            chunk(lat - previousLat)
            chunk(lon - previousLon)
            previousLat = lat
            previousLon = lon
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// The reverse, for drawing a received route. A truncated string yields
    /// the points before the damage rather than failing — a partial line is
    /// still worth showing, and this matches the JavaScript decoder.
    public static func decodePolyline(_ text: String) -> [OutdoorShareCoordinate] {
        let codes = Array(text.utf16)
        var points = [OutdoorShareCoordinate]()
        var index = 0, lat = 0, lon = 0

        func next() -> Int? {
            var result = 0, shift = 0, b = 0
            repeat {
                guard index < codes.count, shift < 64 else { return nil }
                b = Int(codes[index]) - 63
                index += 1
                result |= (b & 0x1f) << shift
                shift += 5
            } while b >= 0x20
            return (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
        }

        while index < codes.count {
            guard let dLat = next(), let dLon = next() else { break }
            lat += dLat
            lon += dLon
            points.append(OutdoorShareCoordinate(latitude: Double(lat) / 100_000,
                                                 longitude: Double(lon) / 100_000))
        }
        return points
    }

    // MARK: - Arithmetic, as JavaScript does it

    /// `Math.round`: nearest, halves toward positive infinity. Written out
    /// rather than `floor(x + 0.5)`, which gets 0.49999999999999994 wrong.
    /// Non-finite input is treated as 0, as the JavaScript's `|| 0` does for
    /// a missing distance.
    static func roundHalfUp(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        let floor = value.rounded(.down)
        return Int(value - floor >= 0.5 ? floor + 1 : floor)
    }

    private static func durationMs(_ a: OutdoorShareActivity) -> Int64? {
        a.endedAtEpochMs.map { $0 - a.startedAtEpochMs }
    }

    private static func durationSeconds(_ a: OutdoorShareActivity) -> Double? {
        durationMs(a).map { Double($0) / 1000 }
    }

    private static func paceSecondsPerMeter(_ a: OutdoorShareActivity) -> Double? {
        guard let seconds = durationSeconds(a), a.distanceMeters > 0 else { return nil }
        return seconds / a.distanceMeters
    }
}
