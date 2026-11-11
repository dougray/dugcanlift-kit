import Foundation
import LiftCore

/// Whether a route is drawn over downloaded streets or as the plain line.
public enum RouteMapDecision: Equatable {
    case map, line

    /// While the store is being written (`StreetStore.isWriting`) it is the
    /// line, even over covered streets: MapLibre must not read the file then.
    public static func decide(points: [OutdoorShareCoordinate], writing: Bool,
                              covered: (MapBounds) -> Bool) -> RouteMapDecision {
        writing ? .line : decide(points: points, covered: covered)
    }

    public static func decide(points: [OutdoorShareCoordinate], covered: (MapBounds) -> Bool) -> RouteMapDecision {
        guard points.count >= 2, let bounds = MapBounds.around(points) else { return .line }
        return covered(bounds) ? .map : .line
    }
}
