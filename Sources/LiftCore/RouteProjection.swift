import CoreGraphics
import Foundation

/// LIFT's projection, ported line for line from Coach web's `coach/route.js`
/// `project()`: longitude scaled by cos(average latitude), one scale for both
/// axes so a route is never stretched, centred, north up, 10% padding.
///
/// Used by `RouteCanvas`, which draws a route with no map behind it, so that
/// no tile server learns where anyone runs. `RouteProjectionTests` checks every
/// point against a fixture `route.js` itself wrote; change the two together or
/// not at all.
public enum RouteProjection {

    /// `MIN_SPAN_DEGREES` in route.js: a route that has barely moved still
    /// gets a scale, rather than a division by zero.
    public static let minimumSpanDegrees = 0.0001

    public static func project(_ points: [OutdoorShareCoordinate], width: Double, height: Double) -> [CGPoint] {
        guard !points.isEmpty else { return [] }
        let avgLat = points.reduce(0) { $0 + $1.latitude } / Double(points.count)
        let lonScale = cos(avgLat * .pi / 180)
        let xs = points.map { $0.longitude * lonScale }
        let ys = points.map { $0.latitude }
        let minX = xs.min()!, maxX = xs.max()!
        let minY = ys.min()!, maxY = ys.max()!
        let padding = min(width, height) * 0.1
        let w = width - padding * 2, h = height - padding * 2
        let scale = max(max(maxX - minX, minimumSpanDegrees) / w,
                        max(maxY - minY, minimumSpanDegrees) / h)
        let offsetX = (w - (maxX - minX) / scale) / 2
        let offsetY = (h - (maxY - minY) / scale) / 2
        return points.indices.map { i in
            CGPoint(x: padding + offsetX + (xs[i] - minX) / scale,
                    y: padding + offsetY + (maxY - ys[i]) / scale)
        }
    }
}
