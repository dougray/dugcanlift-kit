import XCTest
@testable import LiftCore

final class PlanLinkTests: XCTestCase {

    func testBase64URLHasNoPaddingOrURLUnsafeCharacters() {
        // 0xFB 0xFF is "+/8=" in standard base64 — one of each character this
        // has to rewrite, plus padding to strip.
        XCTAssertEqual(Data([0xFB, 0xFF]).base64EncodedString(), "+/8=")
        XCTAssertEqual(CompactEncoding.base64URL(Data([0xFB, 0xFF])), "-_8")
    }

    func testDeflateRoundTripsThroughInflate() throws {
        let original = String(repeating: "Beef Chilli", count: 40).data(using: .utf8)!
        let deflated = try XCTUnwrap(CompactEncoding.deflateRaw(original))
        XCTAssertLessThan(deflated.count, original.count)
        XCTAssertEqual(CompactEncoding.inflateRaw(deflated), original)
    }

    func testBase64URLDecodeReversesBase64URL() throws {
        let bytes = Data([0xFB, 0xFF, 0x00, 0x10])
        let text = CompactEncoding.base64URL(bytes)
        XCTAssertEqual(CompactEncoding.base64URLDecode(text), bytes)
    }

    func testPlanPayloadIsEncodableSoCoachCanProduceLinks() throws {
        // LIFT only ever decoded these. Coach v2 encodes them, and both sides
        // must go through ONE set of type definitions — a field added to one
        // copy and forgotten on the other is how this project's share-link
        // encoders diverged before.
        //
        // Note: the task brief's own draft of this test used `s:` as the
        // argument label for the sessions array. The wire field (and every
        // existing lift-ios call site, including its own PlanImporterTests)
        // uses `k`, not `s` — `s` looks like a slip in the brief itself, and
        // changing the real field name would be exactly the kind of
        // uncoordinated divergence this task exists to prevent. Kept `k`.
        let payload = PlanPayload(v: 1, t: "plan", l: "a1b2c3d4", n: "Doug",
                                  r: [], m: [], w: [], k: [])
        let data = try JSONEncoder().encode(payload)
        let back = try JSONDecoder().decode(PlanPayload.self, from: data)
        XCTAssertEqual(back, payload)
    }

    // A fragment built WITHOUT the code under test, the way lift-ios's own
    // PlanLinkCodecTests does it -- a fixture that shares the implementation
    // it is testing can hide a real bug.
    private func fragment(json: String, compressed: Bool = false) -> String {
        let data = Data(json.utf8)
        let payload = compressed ? (CompactEncoding.deflateRaw(data) ?? data) : data
        let base64 = payload.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "1\(compressed ? "z" : "u")\(base64)"
    }

    private let planJSON = #"{"v":1,"t":"plan","l":"a1b2c3d4","n":"Doug","r":[],"m":[],"w":[],"k":[]}"#

    func testDecodeRejectsAPlanAddressedToADifferentLifter() {
        // The `l` field addresses one athlete. Importing someone else's plan
        // would overwrite this user's week with a stranger's.
        //
        // The earlier version of this test passed "1zAAAA", which is deflate
        // garbage -- it threw `corruptPayload` before the lifter check was
        // ever reached, so it asserted nothing about addressing.
        XCTAssertThrowsError(
            try PlanLinkCodec.decode(fragment: fragment(json: planJSON),
                                     expectedLifterID: "somebody-else")
        ) { error in
            XCTAssertEqual(error as? PlanLinkError, .notAddressedToThisDevice)
        }
    }

    func testDecodeAcceptsAPlanAddressedToThisLifter() throws {
        let payload = try PlanLinkCodec.decode(fragment: fragment(json: planJSON),
                                               expectedLifterID: "a1b2c3d4")
        XCTAssertEqual(payload.t, "plan")
        XCTAssertEqual(payload.n, "Doug")
    }

    func testDecodeReadsACompressedFragmentToo() throws {
        let payload = try PlanLinkCodec.decode(fragment: fragment(json: planJSON, compressed: true),
                                               expectedLifterID: "a1b2c3d4")
        XCTAssertEqual(payload.l, "a1b2c3d4")
    }

    func testDecodeRejectsAnUnsupportedVersion() {
        let body = fragment(json: planJSON).dropFirst(2)
        XCTAssertThrowsError(
            try PlanLinkCodec.decode(fragment: "9u" + body, expectedLifterID: "a1b2c3d4"))
    }
}
