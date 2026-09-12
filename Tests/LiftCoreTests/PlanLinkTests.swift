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

    func testDecodeRejectsAFragmentForADifferentLifter() {
        // The `l` field addresses one client. Importing someone else's plan
        // would silently overwrite this user's week.
        XCTAssertThrowsError(
            try PlanLinkCodec.decode(fragment: "1zAAAA", expectedLifterID: "nobody"))
    }
}
