import Foundation
import SwiftUI
import LiftCore
import LiftMapCore

/// The Maps section of a settings `List` or `Form`: the areas downloaded, each
/// with **Update** and **Delete** in its context menu, any download that did
/// not finish with **Try again**, and the ways to download a new area. Nothing
/// downloads without the person tapping through `StreetsSheet`, and nothing
/// ever updates on its own.
///
/// **Update** downloads the same area again as a new area and deletes the old
/// one only once the new one has finished, so a failed update leaves the
/// streets the person had.
///
/// LIFT passes `location` (one fix, with the permission it already has; nil
/// hides the row) and `lastRunStart`. Coach passes `{ nil }` and nil, and
/// offers its route download on the route card instead; `routeArea`, when
/// given, adds that offer here too.
public struct MapsSection: View {
    static let footer = "Streets are drawn from areas you download. Nothing is sent while you look at a map."
    /// The radius a new area starts at; the sheet offers the others.
    static let startingKm = StreetAreaPlan.detailChoices[0]

    let store: StreetStore
    let location: () async -> (Double, Double)?
    let lastRunStart: (Double, Double)?
    let routeArea: MapBounds?

    @State private var areas: [StreetArea] = []
    @State private var unfinished: [StreetArea] = []
    @State private var here: (Double, Double)?
    @State private var sheet: SheetRequest?
    @State private var deleting: StreetArea?

    public init(store: StreetStore, location: @escaping () async -> (Double, Double)?,
                lastRunStart: (Double, Double)?, routeArea: MapBounds? = nil) {
        self.store = store
        self.location = location
        self.lastRunStart = lastRunStart
        self.routeArea = routeArea
    }

    struct SheetRequest: Identifiable {
        let id = UUID()
        let plan: StreetAreaPlan
        let name: String
        let mode: StreetsSheet.Mode
        /// The area an update replaces, deleted once the new one finishes.
        let replacing: UUID?
    }

    public var body: some View {
        Section {
            ForEach(areas) { area in
                VStack(alignment: .leading, spacing: 2) {
                    Text(area.name)
                    Text(Self.detailLine(area))
                        .font(Theme.detail)
                        .foregroundStyle(Theme.textSecondary)
                }
                .accessibilityElement(children: .combine)
                .contextMenu {
                    Button("Update") {
                        sheet = SheetRequest(plan: Self.replan(area), name: area.name, mode: .update,
                                             replacing: area.id)
                    }
                    Button("Delete", role: .destructive) { deleting = area }
                }
            }
            ForEach(unfinished) { area in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(area.name)
                        Text("Not finished")
                            .font(Theme.detail)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Button("Try again") { retry(area) }
                        .buttonStyle(.borderless)
                }
                .contextMenu {
                    Button("Try again") { retry(area) }
                    Button("Delete", role: .destructive) { deleting = area }
                }
            }
            if areas.isEmpty && unfinished.isEmpty {
                Text("No streets downloaded.")
                    .foregroundStyle(Theme.textSecondary)
            }
            if let here {
                Button("Download streets around here") { offer(around: here) }
            }
            if let lastRunStart {
                Button("Download streets around your last run") { offer(around: lastRunStart) }
            }
            if let routeArea {
                Button("Download streets for this route") {
                    sheet = SheetRequest(plan: .forRoute(routeArea), name: "Streets for this route",
                                         mode: .new, replacing: nil)
                }
            }
        } header: {
            // The presentations hang off the header, one view, rather than the
            // Section, whose modifiers a List hands to every row.
            Text("Maps")
                .task {
                    reload()
                    here = await location()
                }
                .sheet(item: $sheet) { request in
                    StreetsSheet(plan: request.plan, name: request.name, store: store, mode: request.mode) { area in
                        if area != nil, let old = request.replacing { try? store.deleteArea(old) }
                        sheet = nil
                        reload()
                    }
                }
                .alert(deleting.map { "Delete \($0.name)?" } ?? "",
                       isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                    Button("Delete", role: .destructive) {
                        if let area = deleting { try? store.deleteArea(area.id) }
                        deleting = nil
                        reload()
                    }
                    Button("Cancel", role: .cancel) { deleting = nil }
                } message: {
                    Text("You can download it again later.")
                }
        } footer: {
            Text(Self.footer)
        }
    }

    private func reload() {
        areas = (try? store.areas()) ?? []
        unfinished = (try? store.unfinishedAreas()) ?? []
    }

    private func offer(around point: (Double, Double)) {
        sheet = SheetRequest(plan: StreetAreaPlan(latitude: point.0, longitude: point.1, detailKm: Self.startingKm),
                             name: Self.name(around: point), mode: .new, replacing: nil)
    }

    private func retry(_ area: StreetArea) {
        sheet = SheetRequest(plan: Self.replan(area), name: area.name, mode: .resume(area.id), replacing: nil)
    }

    /// "Streets around 39.74, -104.99", as Nomad Pocket names its areas. No
    /// place name: finding one would be a request.
    static func name(around point: (Double, Double)) -> String {
        "Streets around " + String(format: "%.2f, %.2f", point.0, point.1)
    }

    /// "24.8 MB · Nov 10, 2026".
    static func detailLine(_ area: StreetArea) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(area.bytes), countStyle: .file)
            + " · " + area.downloadedAt.formatted(date: .abbreviated, time: .omitted)
    }

    /// The plan an area was downloaded with, for an update or a retry. A radius
    /// area is the same radius around the centre of its detail box. A route
    /// area (`detailKm` 0) stored the route's box already grown 2 km, so it is
    /// shrunk back by those 2 km first, and `forRoute` grows it to the same box.
    static func replan(_ area: StreetArea) -> StreetAreaPlan {
        let d = area.detail
        let lat = (d.south + d.north) / 2
        let lon = (d.west + d.east) / 2
        if area.detailKm > 0 {
            return StreetAreaPlan(latitude: lat, longitude: lon, detailKm: area.detailKm)
        }
        let dLat = 2 / 111.32
        let dLon = 2 / (111.32 * max(0.01, cos(lat * .pi / 180)))
        let route = MapBounds(south: min(lat, d.south + dLat), west: min(lon, d.west + dLon),
                              north: max(lat, d.north - dLat), east: max(lon, d.east - dLon))
        return .forRoute(route)
    }
}
