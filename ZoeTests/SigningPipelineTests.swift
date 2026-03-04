import Testing
import C2PA
import CryptoKit
import Foundation
import UIKit
@testable import zoe

@MainActor
final class SigningPipelineTests {

    // MARK: - Task 6.1: SPM linkage

    @Test("c2pa-ios SPM links: Builder type is reachable")
    func testSPMLinked() throws {
        let minimalJSON = #"{"claim_generator":"Test/1.0","format":"image/jpeg","title":"t"}"#
        let builder = try Builder(manifestJSON: minimalJSON)
        _ = builder
    }

    // MARK: - Task 6.2: Manifest JSON

    @Test("C2PAManifest: canonicalJSON is snake_case and compact; c2paManifestJSON wraps assertion")
    func testManifestJSON() throws {
        let manifest = C2PAManifest(
            schemaVersion: "zoe.media.v1",
            kid: "abc123",
            contentHash: "deadbeef",
            assetId: "11111111-0000-0000-0000-000000000000",
            captureTimestamp: "2026-03-04T21:00:00Z",
            appVersion: "1.0",
            iosVersion: "26.0",
            deviceModel: "iPhone15,2"
        )

        // Check canonical JSON string directly (don't rely on dict iteration order)
        let canonical = try manifest.canonicalJSON()
        let canonicalStr = String(data: canonical, encoding: .utf8)!
        #expect(canonicalStr.contains("\"schema_version\""))
        #expect(canonicalStr.contains("\"content_hash\""))
        #expect(canonicalStr.contains("\"capture_timestamp\""))
        #expect(!canonicalStr.contains(": "))  // compact, no spaces after colon

        // Verify alphabetical key order in the raw JSON string
        let keyOrder = ["app_version","asset_id","capture_timestamp","content_hash",
                        "device_model","ios_version","kid","schema_version"]
        var lastIdx = canonicalStr.startIndex
        for key in keyOrder {
            guard let r = canonicalStr.range(of: "\"\(key)\"", range: lastIdx..<canonicalStr.endIndex) else {
                Issue.record("Key \"\(key)\" not found after previous key in canonical JSON")
                return
            }
            lastIdx = r.upperBound
        }

        // c2paManifestJSON: must contain claim_generator, assertions, zoe.media.v1
        let c2paJSON = try manifest.c2paManifestJSON()
        #expect(c2paJSON.contains("claim_generator"))
        #expect(c2paJSON.contains("zoe.media.v1"))
        #expect(c2paJSON.contains("assertions"))
        let parsed = try JSONSerialization.jsonObject(with: Data(c2paJSON.utf8)) as! [String: Any]
        #expect(parsed["format"] as? String == "image/jpeg")
    }

    // MARK: - Task 6.3: Full embed/extract round-trip with software signer

    @Test("Full spike: embed C2PA manifest with software signer, extract, verify JSON")
    func testFullSpikeWithSoftwareSigner() async throws {
        let signer = try Signer(
            certsPEM: C2PATestCredentials.certsPEM,
            privateKeyPEM: C2PATestCredentials.privateKeyPEM,
            algorithm: .es256,
            tsaURL: nil
        )

        // Generate a real 1×1 JPEG (SOI+EOI alone is rejected by c2pa-ios)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let jpegData = renderer.jpegData(withCompressionQuality: 0.5) { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        let contentHash = SHA256.hash(data: jpegData)
            .compactMap { String(format: "%02x", $0) }.joined()

        let manifest = C2PAManifest(
            schemaVersion: "zoe.media.v1",
            kid: "spike-test-key",
            contentHash: contentHash,
            assetId: UUID().uuidString,
            captureTimestamp: ISO8601DateFormatter().string(from: Date()),
            appVersion: "test",
            iosVersion: "26.0",
            deviceModel: deviceModelString()
        )

        let embeddedJPEG = try C2PAEmbedder.embed(manifest: manifest, signer: signer, into: jpegData)
        #expect(embeddedJPEG.count > jpegData.count)

        let extractedJSON = try C2PAEmbedder.extract(from: embeddedJPEG)
        #expect(!extractedJSON.isEmpty)
        let parsedResult = try JSONSerialization.jsonObject(with: Data(extractedJSON.utf8)) as! [String: Any]
        #expect(parsedResult["manifests"] != nil)
    }
}
