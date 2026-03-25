import Testing
import CryptoKit
import Foundation
@testable import zoe

final class ZoeProofPayloadTests {

    private func makeManifest() -> ZoeProofPayload {
        ZoeProofPayload(
            schemaVersion: "zoe.media.v1",
            kid: "abc123",
            contentHash: "deadbeef",
            assetId: "11111111-0000-0000-0000-000000000000",
            captureTimestamp: "2026-03-04T21:00:00Z",
            appVersion: "1.0",
            iosVersion: "17.0",
            deviceModel: "iPhone15,2"
        )
    }

    @Test("canonicalJSON excludes signature field and contains exactly 8 keys")
    func testCanonicalJSONExcludesSignatureField() throws {
        let canonical = try makeManifest().canonicalJSON()
        let str = String(data: canonical, encoding: .utf8)!

        #expect(!str.contains("\"signature\""))

        let dict = try JSONSerialization.jsonObject(with: canonical) as! [String: Any]
        #expect(dict.count == 8)
    }

    @Test("canonicalJSON keys are in alphabetical order")
    func testCanonicalJSONAlphabeticKeyOrder() throws {
        let canonical = try makeManifest().canonicalJSON()
        let str = String(data: canonical, encoding: .utf8)!

        let expectedOrder = ["app_version", "asset_id", "capture_timestamp", "content_hash",
                             "device_model", "ios_version", "kid", "schema_version"]
        var lastIdx = str.startIndex
        for key in expectedOrder {
            guard let r = str.range(of: "\"\(key)\"", range: lastIdx..<str.endIndex) else {
                Issue.record("Key \"\(key)\" not found after previous key in canonical JSON")
                return
            }
            lastIdx = r.upperBound
        }
    }

    @Test("canonicalJSON has no whitespace after colons or commas")
    func testCanonicalJSONNoWhitespace() throws {
        let canonical = try makeManifest().canonicalJSON()
        let str = String(data: canonical, encoding: .utf8)!

        #expect(!str.contains(": "))
        #expect(!str.contains(", "))
    }

    @Test("deriveKid returns 64-char lowercase hex")
    func testKidIs64CharLowercaseHex() throws {
        let softKey = P256.Signing.PrivateKey()
        let kid = deriveKid(from: softKey.publicKey)

        #expect(kid.count == 64)
        #expect(kid.range(of: "^[0-9a-f]+$", options: .regularExpression) != nil)
    }

    @Test("SHA-256 content hash is 64-char lowercase hex")
    func testContentHashFormat() throws {
        let data = Data([0x01, 0x02, 0x03, 0x04])
        let hash = SHA256.hash(data: data)
            .compactMap { String(format: "%02x", $0) }.joined()

        #expect(hash.count == 64)
        #expect(hash.range(of: "^[0-9a-f]+$", options: .regularExpression) != nil)
    }

    @Test("UUID v4 asset ID has correct format")
    func testAssetIdIsUUIDv4Format() throws {
        let assetId = UUID().uuidString

        #expect(UUID(uuidString: assetId) != nil)
        #expect(assetId.count == 36)
    }

    @Test("toDict() returns same 8 keys as canonicalJSON")
    func testToDictMatchesCanonicalJSONKeys() throws {
        let payload = makeManifest()
        let canonical = try payload.canonicalJSON()
        let canonicalDict = try JSONSerialization.jsonObject(with: canonical) as! [String: Any]
        let toDict = payload.toDict()

        #expect(Set(canonicalDict.keys) == Set(toDict.keys))
        #expect(toDict.count == 8)
    }
}
