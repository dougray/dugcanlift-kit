import Foundation
import LiftCore

/// Whether a route is drawn over downloaded streets or as the plain line.
public enum RouteMapDecision: Equatable {
    case map, line

    public static func decide(points: [OutdoorShareCoordinate], covered: (MapBounds) -> Bool) -> RouteMapDecision {
        guard points.count >= 2, let bounds = MapBounds.around(points) else { return .line }
        return covered(bounds) ? .map : .line
    }
}
