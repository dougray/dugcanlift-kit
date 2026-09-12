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

    public init(v: Int, c: WireClient, g: WireGoal?, r: String, t: String, z: Int,
                x: [String], fd: [String]?, d: [WireDay]) {
        self.v = v
        self.c = c
        self.g = g
        self.r = r
        self.t = t
        self.z = z
        self.x = x
        self.fd = fd
        self.d = d
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

    public init(k: Int, n: String?, fo: String?, bw: Double?, st: Int?,
                w: [WireWorkoutEntry]?, ft: [Double]?, f: [[Double]]?) {
        self.k = k
        self.n = n
        self.fo = fo
        self.bw = bw
        self.st = st
        self.w = w
        self.ft = ft
        self.f = f
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
