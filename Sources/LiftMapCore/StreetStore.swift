import Foundation
import GRDB

/// One downloaded area, as the Maps screens list it.
public struct StreetArea: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var detail: MapBounds
    public var detailKm: Int
    public var downloadedAt: Date
    public var bytes: Int

    public init(id: UUID, name: String, detail: MapBounds, detailKm: Int, downloadedAt: Date, bytes: Int) {
        self.id = id
        self.name = name
        self.detail = detail
        self.detailKm = detailKm
        self.downloadedAt = downloadedAt
        self.bytes = bytes
    }
}

public enum StreetStoreError: Error, Equatable {
    /// A tile for an area that has no row: deleted, or never begun. Writing it
    /// would leave `area_tiles` rows no `deleteArea` ever sweeps.
    case unknownArea
}

/// Every downloaded area's vector tiles in ONE MBTiles file, which MapLibre
/// Native reads read-only through `mbtiles://`. `areas` and `area_tiles` are
/// ours; MapLibre ignores them. `area_tiles` holds XYZ, `tiles` holds TMS rows.
public final class StreetStore: Sendable {
    public let fileURL: URL
    private let queue: DatabaseQueue

    /// Posted, with the store as its object, whenever the set of finished
    /// areas changes (`finishArea`, `deleteArea`), on whichever thread made
    /// the change. A map drawn over this store decides again on it.
    public static let didChange = Notification.Name("LiftMapStreetsChanged")

    private func postChange() {
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    /// How long a write keeps trying while MapLibre is reading the file.
    static let lockWait: TimeInterval = 5

    /// A write transaction that waits out a reader. Two cases: a reader in
    /// another process makes SQLite answer BUSY, which `busyMode` waits out;
    /// MapLibre in this process opens the file read-only, and Apple's SQLite
    /// then answers SQLITE_IOERR_LOCK rather than BUSY while that reader holds
    /// its shared lock (measured on macOS 27's SQLite 3.54), which no busy
    /// handler sees. Both are retried until `lockWait` has passed. A failed
    /// attempt has rolled back, and every write here is safe to repeat.
    private func write<T>(_ updates: (Database) throws -> T) throws -> T {
        let deadline = Date().addingTimeInterval(Self.lockWait)
        while true {
            do {
                return try queue.write(updates)
            } catch let error as DatabaseError
                        where (error.resultCode == .SQLITE_BUSY || error.extendedResultCode == .SQLITE_IOERR_LOCK)
                        && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
    }

    public init(fileURL: URL) throws {
        self.fileURL = fileURL
        var config = Configuration()
        // MapLibre reads this file while a download writes it. In DELETE
        // journal mode a commit needs every reader gone, so a write waits for
        // a read to finish rather than failing at once with SQLITE_BUSY.
        config.busyMode = .timeout(5)
        config.prepareDatabase { db in
            // MapLibre opens the file read-only; a WAL would need write access to -shm.
            _ = try db.execute(sql: "PRAGMA journal_mode = DELETE")
        }
        queue = try DatabaseQueue(path: fileURL.path, configuration: config)
        try write { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS metadata (name TEXT PRIMARY KEY, value TEXT);
                CREATE TABLE IF NOT EXISTS tiles (
                    zoom_level INT, tile_column INT, tile_row INT, tile_data BLOB,
                    PRIMARY KEY (zoom_level, tile_column, tile_row));
                CREATE TABLE IF NOT EXISTS areas (
                    id TEXT PRIMARY KEY, name TEXT, south REAL, west REAL, north REAL, east REAL,
                    detail_km INT, started_at REAL, finished_at REAL, bytes INT);
                CREATE TABLE IF NOT EXISTS area_tiles (
                    area_id TEXT, z INT, x INT, y INT, PRIMARY KEY (area_id, z, x, y));
                -- deleteArea asks, per tile, whether any area still owns it;
                -- the primary key leads with area_id and cannot answer that.
                -- IF NOT EXISTS, so a store written before it gains it on open.
                CREATE INDEX IF NOT EXISTS area_tiles_zxy ON area_tiles (z, x, y);
                """)
            let meta: [(String, String)] = [
                ("name", "LIFT streets"), ("format", "pbf"), ("minzoom", "0"), ("maxzoom", "14"),
                ("attribution", "© OpenStreetMap contributors · OpenFreeMap"),
            ]
            for (k, v) in meta {
                try db.execute(sql: "INSERT OR REPLACE INTO metadata (name, value) VALUES (?, ?)", arguments: [k, v])
            }
        }
    }

    /// Application Support/LiftMap/streets.mbtiles, kept out of iCloud backup.
    public static func standard() throws -> StreetStore {
        let fm = FileManager.default
        let base = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("LiftMap", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var file = dir.appendingPathComponent("streets.mbtiles")
        let store = try StreetStore(fileURL: file)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? file.setResourceValues(values)
        return store
    }

    /// The app's one store, opened once; nil if it cannot be opened.
    public static let shared: StreetStore? = try? StreetStore.standard()

    public func beginArea(_ plan: StreetAreaPlan, name: String) throws -> UUID {
        let id = UUID()
        try write { db in
            try db.execute(sql: """
                INSERT INTO areas (id, name, south, west, north, east, detail_km, started_at, finished_at, bytes)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL, 0)
                """, arguments: [id.uuidString, name, plan.detail.south, plan.detail.west, plan.detail.north,
                                 plan.detail.east, plan.detailKm, Date().timeIntervalSince1970])
        }
        return id
    }

    /// Throws `StreetStoreError.unknownArea` for an area with no row.
    public func put(_ data: Data, for tile: TileID, area: UUID) throws {
        try write { db in
            guard try Int.fetchOne(db, sql: "SELECT 1 FROM areas WHERE id = ?", arguments: [area.uuidString]) != nil else {
                throw StreetStoreError.unknownArea
            }
            try db.execute(sql: """
                INSERT OR REPLACE INTO tiles (zoom_level, tile_column, tile_row, tile_data) VALUES (?, ?, ?, ?)
                """, arguments: [tile.z, tile.x, tile.tmsRow, data])
            try db.execute(sql: "INSERT OR IGNORE INTO area_tiles (area_id, z, x, y) VALUES (?, ?, ?, ?)",
                           arguments: [area.uuidString, tile.z, tile.x, tile.y])
        }
    }

    public func hasTile(_ tile: TileID, area: UUID) throws -> Bool {
        try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT 1 FROM area_tiles WHERE area_id = ? AND z = ? AND x = ? AND y = ?",
                             arguments: [area.uuidString, tile.z, tile.x, tile.y]) != nil
        }
    }

    public func finishArea(_ id: UUID) throws {
        try write { db in
            let bytes = try Int.fetchOne(db, sql: """
                SELECT COALESCE(SUM(LENGTH(t.tile_data)), 0) FROM area_tiles a
                JOIN tiles t ON t.zoom_level = a.z AND t.tile_column = a.x
                    AND t.tile_row = ((1 << a.z) - 1 - a.y)
                WHERE a.area_id = ?
                """, arguments: [id.uuidString]) ?? 0
            try db.execute(sql: "UPDATE areas SET finished_at = ?, bytes = ? WHERE id = ?",
                           arguments: [Date().timeIntervalSince1970, bytes, id.uuidString])
        }
        postChange()
    }

    /// Finished areas, newest first.
    public func areas() throws -> [StreetArea] { try list(finished: true) }

    /// Areas begun and not finished (an interrupted download), newest first;
    /// `downloadedAt` is when each began. `MapDownload.resume` takes one of these.
    public func unfinishedAreas() throws -> [StreetArea] { try list(finished: false) }

    private func list(finished: Bool) throws -> [StreetArea] {
        let sql = finished
            ? "SELECT * FROM areas WHERE finished_at IS NOT NULL ORDER BY finished_at DESC"
            : "SELECT * FROM areas WHERE finished_at IS NULL ORDER BY started_at DESC"
        return try queue.read { db in
            try Row.fetchAll(db, sql: sql).compactMap { row -> StreetArea? in
                guard let id = UUID(uuidString: row["id"]) else { return nil }
                let at: Double = finished ? row["finished_at"] : row["started_at"]
                return StreetArea(
                    id: id, name: row["name"],
                    detail: MapBounds(south: row["south"], west: row["west"], north: row["north"], east: row["east"]),
                    detailKm: row["detail_km"], downloadedAt: Date(timeIntervalSince1970: at),
                    bytes: row["bytes"])
            }
        }
    }

    public func deleteArea(_ id: UUID) throws {
        try write { db in
            try db.execute(sql: "DELETE FROM area_tiles WHERE area_id = ?", arguments: [id.uuidString])
            try db.execute(sql: """
                DELETE FROM tiles WHERE NOT EXISTS (
                    SELECT 1 FROM area_tiles a
                    WHERE a.z = zoom_level AND a.x = tile_column AND a.y = ((1 << zoom_level) - 1 - tile_row))
                """)
            try db.execute(sql: "DELETE FROM areas WHERE id = ?", arguments: [id.uuidString])
        }
        postChange()
    }

    public func covers(_ bounds: MapBounds) throws -> Bool {
        try areas().contains { $0.detail.intersects(bounds) }
    }
}
