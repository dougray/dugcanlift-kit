import Foundation

/// Decodes a coach's plan link (`PLAN-FORMAT.md` v1) into a typed payload.
///
/// Mirrors `lift-ios`'s `CoachShare.swift` encode side in reverse — base64url,
/// then raw DEFLATE (`COMPRESSION_ZLIB` used as a raw/no-wrap codec, matching
/// `CompressionStream('deflate-raw')` and Android's `Inflater(nowrap = true)`,
/// via `CompactEncoding`) — but is written independently rather than by
/// exposing the encoder's private helpers, so a fixture built one way and
/// decoded the other way actually exercises interop, not just round-tripping
/// through the same code.
public enum PlanLinkCodec {

    /// - Parameter fragment: everything after the `#` in a plan link, without
    ///   the leading `#` itself.
    /// - Parameter expectedLifterID: this device's own `CoachShare.Settings.lifterID`.
    public static func decode(fragment: String, expectedLifterID: String) throws -> PlanPayload {
        guard fragment.count >= 2 else { throw PlanLinkError.malformedFragment }

        let version = fragment[fragment.startIndex]
        let codec = fragment[fragment.index(after: fragment.startIndex)]
        // "Decoders must ignore any characters after the payload" — but the
        // payload itself is base64url, so the first non-base64url character
        // (if any) marks where it ends.
        let rest = fragment.dropFirst(2)
        let payloadString = String(rest.prefix { isBase64URLCharacter($0) })

        guard version == "1" else {
            throw PlanLinkError.unsupportedVersion(String(version))
        }

        guard let payloadData = CompactEncoding.base64URLDecode(payloadString) else {
            throw PlanLinkError.corruptPayload
        }

        let jsonData: Data
        switch codec {
        case "z":
            guard let inflated = CompactEncoding.inflateRaw(payloadData) else {
                throw PlanLinkError.corruptPayload
            }
            jsonData = inflated
        case "u":
            jsonData = payloadData
        default:
            throw PlanLinkError.unsupportedCodec(String(codec))
        }

        let payload: PlanPayload
        do {
            payload = try JSONDecoder().decode(PlanPayload.self, from: jsonData)
        } catch {
            throw PlanLinkError.corruptPayload
        }

        guard payload.v == 1 else { throw PlanLinkError.unsupportedVersion(String(payload.v)) }
        // `t` exists specifically to "distinguish this from a log arriving at
        // the same door" (PLAN-FORMAT.md) — a coach log link
        // (CoachShare.swift's `/coach/#1z...`) decodes to valid JSON shaped
        // enough like a plan payload that this must be checked explicitly,
        // not assumed from the URL alone.
        guard payload.t == "plan" else { throw PlanLinkError.corruptPayload }
        guard payload.l == expectedLifterID else { throw PlanLinkError.notAddressedToThisDevice }

        return payload
    }

    private static func isBase64URLCharacter(_ c: Character) -> Bool {
        c.isASCII && (c.isLetter || c.isNumber || c == "-" || c == "_")
    }
}

public enum PlanLinkError: Error, Equatable {
    case malformedFragment
    case unsupportedVersion(String)
    case unsupportedCodec(String)
    case corruptPayload
    case notAddressedToThisDevice
}

public struct PlanPayload: Codable, Equatable {
    public let v: Int
    public let t: String
    public let l: String
    public let n: String
    public let r: [PlanRecipe]?
    public let m: [PlanMeal]?
    public let w: [PlanWorkout]?
    public let k: [PlanSession]?

    public init(v: Int, t: String, l: String, n: String,
                r: [PlanRecipe]?, m: [PlanMeal]?, w: [PlanWorkout]?, k: [PlanSession]?) {
        self.v = v
        self.t = t
        self.l = l
        self.n = n
        self.r = r
        self.m = m
        self.w = w
        self.k = k
    }
}

public struct PlanRecipe: Codable, Equatable {
    public let n: String
    public let s: Double
    public let u: [Double]?
    public let i: [String]?
    public let t: [String]?
    /// `[saturatedFatG, sugarG, sodiumMg]` per serving, trailing nulls trimmed;
    /// omitted when none is known. A key of its own rather than more positions
    /// in `u`, which decoders read by position. It can arrive without `u`.
    /// Build it with `ShareNutrients.itemRow(perServing:)`.
    public let ux: WireNutrientDetails?

    private enum CodingKeys: String, CodingKey {
        case n, s, u, ux, i, t
    }

    public init(n: String, s: Double, u: [Double]?, i: [String]?, t: [String]?,
                ux: WireNutrientDetails? = nil) {
        self.n = n
        self.s = s
        self.u = u
        self.i = i
        self.t = t
        self.ux = ux
    }

    /// Hand-written only so `ux` can fail on its own: a malformed `ux` costs the
    /// recipe its saturated fat, sugar and sodium, never the recipe. An all-null
    /// `ux` reads as nil. Everything else decodes exactly as the synthesized init
    /// did. Encoding is synthesized, and omits `ux` when nil.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        n = try container.decode(String.self, forKey: .n)
        s = try container.decode(Double.self, forKey: .s)
        u = try container.decodeIfPresent([Double].self, forKey: .u)
        i = try container.decodeIfPresent([String].self, forKey: .i)
        t = try container.decodeIfPresent([String].self, forKey: .t)
        let details = (try? container.decodeIfPresent(WireNutrientDetails.self, forKey: .ux)) ?? nil
        ux = (details?.isEmpty ?? true) ? nil : details
    }
}

public struct PlanMeal: Codable, Equatable {
    public let d: String
    public let s: Int
    public let x: Int
    public let q: Double

    public init(d: String, s: Int, x: Int, q: Double) {
        self.d = d
        self.s = s
        self.x = x
        self.q = q
    }
}

public struct PlanWorkout: Codable, Equatable {
    public let n: String
    public let e: [PlanWorkoutExercise]

    public init(n: String, e: [PlanWorkoutExercise]) {
        self.n = n
        self.e = e
    }
}

public struct PlanWorkoutExercise: Codable, Equatable {
    public let n: String
    public let q: String?
    public let c: String?
    public let s: [[Double?]]

    public init(n: String, q: String?, c: String?, s: [[Double?]]) {
        self.n = n
        self.q = q
        self.c = c
        self.s = s
    }
}

public struct PlanSession: Codable, Equatable {
    public let d: String
    public let x: Int

    public init(d: String, x: Int) {
        self.d = d
        self.x = x
    }
}
