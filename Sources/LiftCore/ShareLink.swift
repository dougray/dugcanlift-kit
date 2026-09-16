import Foundation

public struct ShareLinkPayload: Codable {
    public let v: Int
    public let c: WireClient
    public let g: WireGoal?
    public let r: String
    public let t: String
    public let z: Int
    public let x: [String]
    public let fd: [String]?
    public let d: [WireDay]
    /// Outdoor personal bests, all-time rather than the window. Absent from
    /// every payload written before outdoor tracking, and from any client
    /// with nothing finished.
    public let ob: [WireOutdoorBest]?
    /// The client's newest route, sent only when they opted in. Absent is
    /// meaningful — it clears the coach's stored one — so it is never
    /// defaulted to anything.
    public let lr: WireLastRoute?

    // Foundation's `JSONEncoder` does not keep declaration order (LIFT web
    // writes these two last), so nothing here promises one. Every reader of
    // this format looks keys up by name.
    private enum CodingKeys: String, CodingKey {
        case v, c, g, r, t, z, x, fd, d, ob, lr
    }

    public init(v: Int, c: WireClient, g: WireGoal?, r: String, t: String, z: Int,
                x: [String], fd: [String]?, d: [WireDay],
                ob: [WireOutdoorBest]? = nil, lr: WireLastRoute? = nil) {
        self.v = v
        self.c = c
        self.g = g
        self.r = r
        self.t = t
        self.z = z
        self.x = x
        self.fd = fd
        self.d = d
        self.ob = ob
        self.lr = lr
    }

    /// Hand-written only so the outdoor keys can fail on their own. A coach
    /// opening a link wants the training and food log; a sender's bug in a
    /// route tuple must cost the route, not the whole payload. Everything that
    /// predates outdoor decodes exactly as the synthesized init did, strictly.
    /// Encoding is still synthesized, and omits `ob`/`lr` when nil.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        v = try container.decode(Int.self, forKey: .v)
        c = try container.decode(WireClient.self, forKey: .c)
        g = try container.decodeIfPresent(WireGoal.self, forKey: .g)
        r = try container.decode(String.self, forKey: .r)
        t = try container.decode(String.self, forKey: .t)
        z = try container.decode(Int.self, forKey: .z)
        x = try container.decode([String].self, forKey: .x)
        fd = try container.decodeIfPresent([String].self, forKey: .fd)
        d = try container.decode([WireDay].self, forKey: .d)
        ob = (try? container.decodeIfPresent([WireOutdoorBest].self, forKey: .ob)) ?? nil
        lr = (try? container.decodeIfPresent(WireLastRoute.self, forKey: .lr)) ?? nil
    }
}

public struct WireClient: Codable {
    public let i: String
    public let n: String
    public let s: String?
    public let a: Int?
    public let h: Double?
    public let u: String
    public let p: String?

    public init(i: String, n: String, s: String?, a: Int?, h: Double?, u: String, p: String?) {
        self.i = i
        self.n = n
        self.s = s
        self.a = a
        self.h = h
        self.u = u
        self.p = p
    }
}

public struct WireGoal: Codable {
    public let c: Int
    public let p: Int
    public let f: Int
    public let cb: Int
    public let fb: Int

    public init(c: Int, p: Int, f: Int, cb: Int, fb: Int) {
        self.c = c
        self.p = p
        self.f = f
        self.cb = cb
        self.fb = fb
    }
}

public struct WireDay: Codable {
    public let k: Int
    public let n: String?
    public let fo: String?
    public let bw: Double?
    public let st: Int?
    public let w: [WireWorkoutEntry]?
    public let ft: [Double]?
    public let f: [[Double]]?
    /// Finished runs, walks and hikes that started this day, in start order.
    /// A day holding only these is still a day.
    public let o: [WireOutdoorActivity]?

    // Listed in the order LIFT web writes a day's keys where the older keys
    // allow it. `JSONEncoder` may still emit them in any order; key order
    // carries no meaning in this format.
    private enum CodingKeys: String, CodingKey {
        case k, n, fo, bw, st, w, ft, f, o
    }

    public init(k: Int, n: String?, fo: String?, bw: Double?, st: Int?,
                w: [WireWorkoutEntry]?, ft: [Double]?, f: [[Double]]?,
                o: [WireOutdoorActivity]? = nil) {
        self.k = k
        self.n = n
        self.fo = fo
        self.bw = bw
        self.st = st
        self.w = w
        self.ft = ft
        self.f = f
        self.o = o
    }

    /// Hand-written for the same reason as `ShareLinkPayload`'s: a malformed
    /// `o` drops the day's outdoor activities, never the day's training and
    /// food. Every other key decodes as strictly as before.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        k = try container.decode(Int.self, forKey: .k)
        n = try container.decodeIfPresent(String.self, forKey: .n)
        fo = try container.decodeIfPresent(String.self, forKey: .fo)
        bw = try container.decodeIfPresent(Double.self, forKey: .bw)
        st = try container.decodeIfPresent(Int.self, forKey: .st)
        w = try container.decodeIfPresent([WireWorkoutEntry].self, forKey: .w)
        ft = try container.decodeIfPresent([Double].self, forKey: .ft)
        f = try container.decodeIfPresent([[Double]].self, forKey: .f)
        o = (try? container.decodeIfPresent([WireOutdoorActivity].self, forKey: .o)) ?? nil
    }
}

// MARK: - Outdoor (SHARE-FORMAT.md, "Outdoor")

/// `[type, durationSec, distanceMeters, climbMeters]` — one finished activity
/// on a day. Type is 0 run, 1 walk, 2 hike. A tuple rather than an object for
/// the reason `WireWorkoutEntry` is one: it is what every sender writes, and
/// synthesized Codable would write an object no other implementation reads.
///
/// Decoding reads the first four elements and ignores any after them, so a
/// future sender appending a field does not break this reader.
public struct WireOutdoorActivity: Codable, Equatable {
    public let type: Int
    public let durationSec: Int
    /// 0 when nothing was measured — this tuple has no null.
    public let distanceMeters: Int
    public let climbMeters: Int

    public init(type: Int, durationSec: Int, distanceMeters: Int, climbMeters: Int) {
        self.type = type
        self.durationSec = durationSec
        self.distanceMeters = distanceMeters
        self.climbMeters = climbMeters
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        type = try container.decode(Int.self)
        durationSec = try container.decode(Int.self)
        distanceMeters = try container.decode(Int.self)
        climbMeters = try container.decode(Int.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(type)
        try container.encode(durationSec)
        try container.encode(distanceMeters)
        try container.encode(climbMeters)
    }
}

/// `[type, count, farthestMeters, longestSec, fastestSecPerKm]` — one type's
/// all-time bests. The last three are null when there is nothing to show, and
/// blank must stay blank: a best of 0 would read as a real, terrible record.
public struct WireOutdoorBest: Codable, Equatable {
    public let type: Int
    public let count: Int
    public let farthestMeters: Int?
    public let longestSec: Int?
    /// Only from activities of at least 1 km; shorter is mostly GPS noise.
    public let fastestSecPerKm: Int?

    public init(type: Int, count: Int, farthestMeters: Int?, longestSec: Int?, fastestSecPerKm: Int?) {
        self.type = type
        self.count = count
        self.farthestMeters = farthestMeters
        self.longestSec = longestSec
        self.fastestSecPerKm = fastestSecPerKm
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        type = try container.decode(Int.self)
        count = try container.decode(Int.self)
        farthestMeters = try container.decodeIfPresent(Int.self)
        longestSec = try container.decodeIfPresent(Int.self)
        fastestSecPerKm = try container.decodeIfPresent(Int.self)
    }

    /// Writes an explicit `null` for a missing best rather than shortening
    /// the tuple: the positions are the meaning.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(type)
        try container.encode(count)
        for value in [farthestMeters, longestSec, fastestSecPerKm] {
            if let value { try container.encode(value) } else { try container.encodeNil() }
        }
    }
}

/// `[type, startedAtEpochSec, durationSec, distanceMeters, climbMeters,
/// "polyline"]` — the newest finished route. The four numbers describe the
/// whole activity; only the polyline is trimmed, so a client's front door is
/// not in it. `OutdoorShare.decodePolyline` reads it back.
public struct WireLastRoute: Codable, Equatable {
    public let type: Int
    public let startedAtEpochSec: Int
    public let durationSec: Int
    public let distanceMeters: Int
    public let climbMeters: Int
    public let polyline: String

    public init(type: Int, startedAtEpochSec: Int, durationSec: Int,
                distanceMeters: Int, climbMeters: Int, polyline: String) {
        self.type = type
        self.startedAtEpochSec = startedAtEpochSec
        self.durationSec = durationSec
        self.distanceMeters = distanceMeters
        self.climbMeters = climbMeters
        self.polyline = polyline
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        type = try container.decode(Int.self)
        startedAtEpochSec = try container.decode(Int.self)
        durationSec = try container.decode(Int.self)
        distanceMeters = try container.decode(Int.self)
        climbMeters = try container.decode(Int.self)
        polyline = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(type)
        try container.encode(startedAtEpochSec)
        try container.encode(durationSec)
        try container.encode(distanceMeters)
        try container.encode(climbMeters)
        try container.encode(polyline)
    }
}

/// A `[exerciseDictIndex, setsArray]` pair. This 2-element array mixes an
/// Int with a nested array, which Codable's automatic array-of-one-type
/// synthesis can't handle — read and write it manually against an unkeyed
/// container on both sides, so encoding stays the same tuple shape the wire
/// format (and `CoachShare.swift`'s encoder) actually produces, rather than
/// a synthesised keyed object.
public struct WireWorkoutEntry: Codable {
    public let exerciseIndex: Int
    public let sets: [[Double?]]

    // Explicit memberwise init: defining `init(from:)` below suppresses
    // Swift's auto-synthesized memberwise init, and callers construct this
    // type directly (not just by decoding), so it needs one written out.
    public init(exerciseIndex: Int, sets: [[Double?]]) {
        self.exerciseIndex = exerciseIndex
        self.sets = sets
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        exerciseIndex = try container.decode(Int.self)
        sets = try container.decode([[Double?]].self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(exerciseIndex)
        try container.encode(sets)
    }
}

/// Decodes a client's training-log link (`SHARE-FORMAT.md` v1) into a typed
/// payload. Mirrors `PlanLink.swift`'s decode pipeline (base64url, then raw
/// DEFLATE via `CompactEncoding`, itself a no-wrap `COMPRESSION_ZLIB` codec)
/// but is written independently — a fixture the real `CoachShare.swift`
/// encoder produced, decoded here, exercises interop, not just
/// round-tripping through shared code.
public enum ShareLinkCodec {

    public static func decode(fragment: String) throws -> ShareLinkPayload {
        guard fragment.count >= 2 else { throw ShareLinkError.malformedFragment }

        let version = fragment[fragment.startIndex]
        let codec = fragment[fragment.index(after: fragment.startIndex)]
        let rest = fragment.dropFirst(2)
        let payloadString = String(rest.prefix { isBase64URLCharacter($0) })

        guard version == "1" else {
            throw ShareLinkError.unsupportedVersion(String(version))
        }

        guard let payloadData = CompactEncoding.base64URLDecode(payloadString) else {
            throw ShareLinkError.corruptPayload
        }

        let jsonData: Data
        switch codec {
        case "z":
            guard let inflated = CompactEncoding.inflateRaw(payloadData) else {
                throw ShareLinkError.corruptPayload
            }
            jsonData = inflated
        case "u":
            jsonData = payloadData
        default:
            throw ShareLinkError.unsupportedCodec(String(codec))
        }

        let payload: ShareLinkPayload
        do {
            payload = try JSONDecoder().decode(ShareLinkPayload.self, from: jsonData)
        } catch {
            throw ShareLinkError.corruptPayload
        }

        guard payload.v == 1 else { throw ShareLinkError.unsupportedVersion(String(payload.v)) }

        return payload
    }

    /// Accepts a full link or a bare fragment — the "Paste a link" field may
    /// receive either, depending on what the trainer copied.
    public static func decode(link: String) throws -> ShareLinkPayload {
        guard let hashIndex = link.firstIndex(of: "#") else {
            return try decode(fragment: link)
        }
        return try decode(fragment: String(link[link.index(after: hashIndex)...]))
    }

    private static func isBase64URLCharacter(_ c: Character) -> Bool {
        c.isASCII && (c.isLetter || c.isNumber || c == "-" || c == "_")
    }
}

public enum ShareLinkError: Error, Equatable {
    case malformedFragment
    case unsupportedVersion(String)
    case unsupportedCodec(String)
    case corruptPayload
}
