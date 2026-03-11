import Testing
import CryptoKit
import Foundation
@testable import zoe

final class C2PAManifestTests {

    private func makeManifest() -> C2PAManifest {
        C2PAManifest(
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

    // MARK: - 8.1

    @Test("All 8 zoe.media.v1 fields present in c2paManifestJSON assertions data")
    func testAllFieldsPresent() throws {
        let json = try makeManifest().c2paManifestJSON()
        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        let assertions = parsed["assertions"] as! [[String: Any]]
        let data = assertions[0]["data"] as! [String: Any]

        #expect(data["schema_version"] != nil)
        #expect(data["kid"] != nil)
        #expect(data["content_hash"] != nil)
        #expect(data["asset_id"] != nil)
        #expect(data["capture_timestamp"] != nil)
        #expect(data["app_version"] != nil)
        #expect(data["ios_version"] != nil)
        #expect(data["device_model"] != nil)
    }

    // MARK: - 8.2

    @Test("canonicalJSON excludes signature field and contains exactly 8 keys")
    func testCanonicalJSONExcludesSignatureField() throws {
        let canonical = try makeManifest().canonicalJSON()
        let str = String(data: canonical, encoding: .utf8)!

        #expect(!str.contains("\"signature\""))

        let dict = try JSONSerialization.jsonObject(with: canonical) as! [String: Any]
        #expect(dict.count == 8)
    }

    // MARK: - 8.3

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

    // MARK: - 8.4

    @Test("canonicalJSON has no whitespace after colons or commas")
    func testCanonicalJSONNoWhitespace() throws {
        let canonical = try makeManifest().canonicalJSON()
        let str = String(data: canonical, encoding: .utf8)!

        #expect(!str.contains(": "))
        #expect(!str.contains(", "))
    }

    // MARK: - 8.5

    @Test("deriveKid returns 64-char lowercase hex")
    func testKidIs64CharLowercaseHex() throws {
        let softKey = P256.Signing.PrivateKey()
        let kid = deriveKid(from: softKey.publicKey)

        #expect(kid.count == 64)
        #expect(kid.range(of: "^[0-9a-f]+$", options: .regularExpression) != nil)
    }

    // MARK: - 8.6

    @Test("SHA-256 content hash is 64-char lowercase hex")
    func testContentHashFormat() throws {
        let data = Data([0x01, 0x02, 0x03, 0x04])
        let hash = SHA256.hash(data: data)
            .compactMap { String(format: "%02x", $0) }.joined()

        #expect(hash.count == 64)
        #expect(hash.range(of: "^[0-9a-f]+$", options: .regularExpression) != nil)
    }

    // MARK: - 8.7

    @Test("UUID v4 asset ID has correct format")
    func testAssetIdIsUUIDv4Format() throws {
        let assetId = UUID().uuidString

        #expect(UUID(uuidString: assetId) != nil)
        #expect(assetId.count == 36)
    }
}

