import SwiftUI
import LiftCore
import LiftMapCore
#if canImport(MapLibre) && os(iOS)
import Combine
import CoreLocation
import MapLibre
#endif

/// A route over the streets the person downloaded, or the plain line when no
/// downloaded area covers it -- `RouteCanvas`, unchanged, so a run outside
/// every area looks exactly as it did before maps existed. Partial cover is
/// cover: tiles outside the download are simply empty background.
///
/// Drawn only from this device's files: the style names the MBTiles store, the
/// bundled glyphs and nothing else, and `MapNetworkGuard` refuses anything
/// MapLibre asks for anyway. Viewing a map makes no request.
///
/// The route stays the strongest thing on screen: a 5 pt accent line with
/// round caps, the start dot in the secondary accent (10 pt) and the end dot in
/// the accent (12 pt), as `RouteCanvas` draws them. The camera fits the whole
/// route (`RouteFitPadding`: 24 pt, 50 pt below for the attribution) and fits again as it grows. No location
/// dot, no compass, no logo; gestures only when `interactive`.
public struct RouteMap: View {
    /// OpenStreetMap's licence asks for the first half; OpenFreeMap is credited beside it.
    public static let attribution = "© OpenStreetMap contributors · OpenFreeMap"

    let points: [OutdoorShareCoordinate]
    let aspectRatio: CGFloat?
    let interactive: Bool
    let store: StreetStore?

    @Environment(\.colorScheme) private var colorScheme
    #if canImport(MapLibre) && os(iOS)
    /// Bumped whenever the store's finished areas change, so a download that
    /// finishes, or an area deleted in Settings, decides this map again.
    @State private var revision = 0
    @State private var memo = StyleMemo()
    #endif

    public init(points: [OutdoorShareCoordinate], aspectRatio: CGFloat? = nil,
                interactive: Bool = false, store: StreetStore? = StreetStore.shared) {
        self.points = points
        self.aspectRatio = aspectRatio
        self.interactive = interactive
        self.store = store
    }

    public var body: some View {
        #if canImport(MapLibre) && os(iOS)
        Group {
            if let store, let style = mapStyle(store) {
                framed(map(style: style, store: store))
            } else {
                RouteCanvas(points: points, aspectRatio: aspectRatio)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: StreetStore.didChange, object: store)
            .receive(on: DispatchQueue.main)) { _ in revision += 1 }
        // The gate closing takes the map down (MapLibre lets go of the file);
        // opening it decides again and builds a fresh map, like a new revision.
        .onReceive(NotificationCenter.default.publisher(for: StreetStore.writingDidChange, object: store)
            .receive(on: DispatchQueue.main)) { _ in revision += 1 }
        #else
        RouteCanvas(points: points, aspectRatio: aspectRatio)
        #endif
    }

    #if canImport(MapLibre) && os(iOS)
    /// The style to draw with, or nil for the plain line: no area covers the
    /// route, or (a build defect) the bundled style is missing -- never a blank square.
    /// Decided again only when the route's bounds, the store's areas or the
    /// appearance change, not on every GPS fix.
    private func mapStyle(_ store: StreetStore) -> Data? {
        let dark = colorScheme == .dark
        let writing = store.isWriting
        let key = StyleMemo.Key(bounds: points.count >= 2 ? MapBounds.around(points) : nil,
                                revision: revision, writing: writing, dark: dark, storeURL: store.fileURL)
        return memo.style(for: key) {
            let decision = RouteMapDecision.decide(points: points, writing: writing) {
                (try? store.covers($0)) ?? false
            }
            guard decision == .map else { return nil }
            return try? MapStyle.json(dark: dark, storeURL: store.fileURL)
        }
    }

    private func map(style: Data, store: StreetStore) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Theme.background
            StreetMapView(points: points, style: style, dark: colorScheme == .dark, revision: revision,
                          interactive: interactive, store: store,
                          refused: { DispatchQueue.main.async { revision += 1 } })
            Text(Self.attribution)
                .font(Theme.detail)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.background.opacity(0.8), in: RoundedRectangle(cornerRadius: 4))
                .padding(6)
                .allowsHitTesting(false)
        }
    }

    /// The same frame `RouteCanvas` gives itself, so a card does not change
    /// shape when streets arrive.
    @ViewBuilder
    private func framed(_ content: some View) -> some View {
        Group {
            if let aspectRatio {
                content.aspectRatio(aspectRatio, contentMode: .fit)
            } else {
                content
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RouteCanvas.accessibilityName)
    }
    #endif
}

#if canImport(MapLibre) && os(iOS)

/// The last decision and style, kept across body evaluations. A class, so
/// remembering does not count as a state change during a view update.
final class StyleMemo {
    struct Key: Equatable {
        var bounds: MapBounds?
        var revision: Int
        var writing: Bool
        var dark: Bool
        var storeURL: URL
    }

    private var key: Key?
    private var style: Data?

    func style(for key: Key, compute: () -> Data?) -> Data? {
        if key != self.key {
            self.key = key
            style = compute()
        }
        return style
    }
}

/// An `MLNMapView` that says when its size changes, so the route can be fitted
/// once there is room to fit it in.
final class RouteMapUIView: MLNMapView {
    var onResize: ((RouteMapUIView) -> Void)?
    private var lastSize: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != lastSize {
            lastSize = bounds.size
            onResize?(self)
        }
    }
}

struct StreetMapView: UIViewRepresentable {
    let points: [OutdoorShareCoordinate]
    let style: Data
    let dark: Bool
    /// The store's revision: a new one reloads the style, so tiles a new
    /// download added are read rather than remembered as empty.
    let revision: Int
    let interactive: Bool
    /// Asked before this map reads the file and told when it is gone, so a
    /// writer can wait for maps to step back (`StreetStore.awaitMapsClosed`).
    let store: StreetStore
    /// Called when the store refused this map because a write began after
    /// RouteMap decided to draw it: RouteMap decides again (the line, while
    /// the write lasts; the map again when the gate opens).
    let refused: () -> Void

    /// A style with nothing in it: no source, no file, no request. What a
    /// refused map shows until it is replaced.
    static let emptyStyle = #"{"version":8,"sources":{},"layers":[]}"#

    static let lineWidth: CGFloat = 5
    static let startRadius: CGFloat = 5   // a 10 pt dot
    static let endRadius: CGFloat = 6     // a 12 pt dot

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MLNMapView {
        MapNetworkGuard.install()
        let coordinator = context.coordinator
        coordinator.points = points
        coordinator.dark = dark
        coordinator.revision = revision
        // Made with a style from the start: a map view made without one loads
        // MapLibre's default style, which is a server's. The streets' style
        // goes in as a file (if the file cannot be written, as text), and only
        // when the store lets this map read; refused, it starts empty.
        let view: RouteMapUIView
        if coordinator.acquire(store) {
            coordinator.loaded = true
            if let file = coordinator.writeStyle(style) {
                view = RouteMapUIView(frame: .zero, styleURL: file)
            } else {
                view = RouteMapUIView(frame: .zero, styleJSON: String(decoding: style, as: UTF8.self))
            }
        } else {
            view = RouteMapUIView(frame: .zero, styleJSON: Self.emptyStyle)
            refused()
        }
        view.delegate = coordinator
        view.showsUserLocation = false
        view.logoView.isHidden = true
        view.compassView.isHidden = true
        view.attributionButton.isHidden = true
        view.isRotateEnabled = false
        view.isPitchEnabled = false
        view.isScrollEnabled = interactive
        view.isZoomEnabled = interactive
        view.backgroundColor = .clear
        view.onResize = { [weak coordinator] view in coordinator?.fit(view) }
        return view
    }

    func updateUIView(_ view: MLNMapView, context: Context) {
        let coordinator = context.coordinator
        view.isScrollEnabled = interactive
        view.isZoomEnabled = interactive
        if !coordinator.loaded {
            // Refused when made: ask again, and load the streets only if granted.
            guard coordinator.acquire(store) else { return }
            coordinator.loaded = true
            coordinator.dark = dark
            coordinator.revision = revision
            coordinator.points = points
            if let file = coordinator.writeStyle(style) {
                view.styleURL = file
            } else {
                view.styleJSON = String(decoding: style, as: UTF8.self)
            }
            return
        }
        if dark != coordinator.dark || revision != coordinator.revision {
            coordinator.dark = dark
            coordinator.revision = revision
            // Layers go back on, in the new colors, when the new style loads.
            // Never `styleURL = nil`: that is MapLibre's default style, a server's.
            if let file = coordinator.writeStyle(style) {
                view.styleURL = file
            } else {
                view.styleJSON = String(decoding: style, as: UTF8.self)
            }
        }
        if points != coordinator.points {
            coordinator.points = points
            coordinator.showRoute(on: view)
            coordinator.fit(view)
        }
    }

    static func dismantleUIView(_ view: MLNMapView, coordinator: Coordinator) {
        coordinator.closed()
        coordinator.removeStyleFile()
    }

    @MainActor
    final class Coordinator: NSObject, MLNMapViewDelegate {
        var points: [OutdoorShareCoordinate] = []
        var dark = false
        var revision = 0
        /// True once the streets' style is loaded; a refused map has none.
        var loaded = false
        private var styleFile: URL?
        /// This map's claim on the file; a refused one is not held and is
        /// never given back.
        private var lease: MapLease?

        /// True when this map may read the file: already granted, or granted now.
        func acquire(_ store: StreetStore) -> Bool {
            if lease == nil { lease = MapLease(store: store) }
            return lease!.acquire()
        }

        func closed() {
            lease?.release()
            lease = nil
        }


        static let routeSource = "lift-route"
        static let startSource = "lift-route-start"
        static let endSource = "lift-route-end"

        /// Writes the style to a temporary file of its own and returns its URL;
        /// the file it replaces is removed.
        func writeStyle(_ style: Data) -> URL? {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("LiftMap", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent("route-style-\(UUID().uuidString).json")
            guard (try? style.write(to: file, options: .atomic)) != nil else { return nil }
            removeStyleFile()
            styleFile = file
            return file
        }

        func removeStyleFile() {
            if let styleFile { try? FileManager.default.removeItem(at: styleFile) }
            styleFile = nil
        }

        /// Puts the route on top of every street layer, or updates it in place.
        func showRoute(on view: MLNMapView) {
            guard let style = view.style, points.count >= 2 else { return }
            var coordinates = points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            let line = MLNPolylineFeature(coordinates: &coordinates, count: UInt(coordinates.count))
            let start = MLNPointFeature()
            start.coordinate = coordinates[0]
            let end = MLNPointFeature()
            end.coordinate = coordinates[coordinates.count - 1]

            if let source = style.source(withIdentifier: Self.routeSource) as? MLNShapeSource,
               let startSource = style.source(withIdentifier: Self.startSource) as? MLNShapeSource,
               let endSource = style.source(withIdentifier: Self.endSource) as? MLNShapeSource {
                source.shape = line
                startSource.shape = start
                endSource.shape = end
                return
            }

            let traits = view.traitCollection.modifyingTraits { $0.userInterfaceStyle = dark ? .dark : .light }
            let accent = UIColor(Theme.accent).resolvedColor(with: traits)
            let secondary = UIColor(Theme.accentSecondary).resolvedColor(with: traits)

            let routeSource = MLNShapeSource(identifier: Self.routeSource, shape: line, options: nil)
            style.addSource(routeSource)
            let lineLayer = MLNLineStyleLayer(identifier: "lift-route-line", source: routeSource)
            lineLayer.lineColor = NSExpression(forConstantValue: accent)
            lineLayer.lineWidth = NSExpression(forConstantValue: StreetMapView.lineWidth)
            lineLayer.lineCap = NSExpression(forConstantValue: "round")
            lineLayer.lineJoin = NSExpression(forConstantValue: "round")
            style.addLayer(lineLayer)

            let startSource = MLNShapeSource(identifier: Self.startSource, shape: start, options: nil)
            style.addSource(startSource)
            let startDot = MLNCircleStyleLayer(identifier: "lift-route-start-dot", source: startSource)
            startDot.circleColor = NSExpression(forConstantValue: secondary)
            startDot.circleRadius = NSExpression(forConstantValue: StreetMapView.startRadius)
            style.addLayer(startDot)

            let endSource = MLNShapeSource(identifier: Self.endSource, shape: end, options: nil)
            style.addSource(endSource)
            let endDot = MLNCircleStyleLayer(identifier: "lift-route-end-dot", source: endSource)
            endDot.circleColor = NSExpression(forConstantValue: accent)
            endDot.circleRadius = NSExpression(forConstantValue: StreetMapView.endRadius)
            style.addLayer(endDot)
        }

        /// Fits the whole route inside `RouteFitPadding.standard`, once the view has a size.
        func fit(_ view: MLNMapView) {
            let pad = RouteFitPadding.standard
            guard view.bounds.width > CGFloat(pad.left + pad.right) + 1,
                  view.bounds.height > CGFloat(pad.top + pad.bottom) + 1,
                  points.count >= 2, var b = MapBounds.around(points) else { return }
            // A route that has barely moved would zoom past every street; show
            // at least a block or two around it.
            let minimumSpan = 0.002
            if b.north - b.south < minimumSpan {
                let mid = (b.north + b.south) / 2
                b.south = mid - minimumSpan / 2
                b.north = mid + minimumSpan / 2
            }
            if b.east - b.west < minimumSpan {
                let mid = (b.east + b.west) / 2
                b.west = mid - minimumSpan / 2
                b.east = mid + minimumSpan / 2
            }
            let bounds = MLNCoordinateBounds(sw: CLLocationCoordinate2D(latitude: b.south, longitude: b.west),
                                             ne: CLLocationCoordinate2D(latitude: b.north, longitude: b.east))
            view.setVisibleCoordinateBounds(bounds, edgePadding: UIEdgeInsets(top: CGFloat(pad.top), left: CGFloat(pad.left),
                                                                      bottom: CGFloat(pad.bottom), right: CGFloat(pad.right)),
                                            animated: false, completionHandler: nil)
        }

        nonisolated func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            MainActor.assumeIsolated {
                guard loaded else { return }   // the empty style of a refused map
                showRoute(on: mapView)
                fit(mapView)
            }
        }
    }
}
#endif
