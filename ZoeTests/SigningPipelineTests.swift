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

    // MARK: - Task 6.3: Secure Enclave sign + full embed/extract round-trip (physical device only)

    /// Validates the full Phase 0 spike on a real device:
    ///   1. Generate an ephemeral SE key (skips gracefully on Simulator where SE is unavailable)
    ///   2. Derive kid from the SE public key
    ///   3. Build a zoe.media.v1 manifest with that kid
    ///   4. Sign canonical manifest JSON with SE key via CryptoKit
    ///   5. Verify SE signature against the SE public key
    ///   6. Embed manifest (with software C2PA signer) and extract → round-trip check
    @Test("Full spike on device: SE key generation, kid derivation, canonical sign, embed/extract")
    func testFullSpikeOnDevice() async throws {
        // --- Step 1: Attempt SE key generation (Simulator: SecKeyCreateRandomKey returns nil) ---
        let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .privateKeyUsage,
            nil
        )!
        let keyAttributes: [String: Any] = [
            kSecAttrKeyType as String:      kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String:      kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String:    false, // ephemeral — not stored in Keychain
                kSecAttrAccessControl as String:  access
            ]
        ]
        var cfError: Unmanaged<CFError>?
        guard let sePrivateKey = SecKeyCreateRandomKey(keyAttributes as CFDictionary, &cfError) else {
            // Simulator: SE unavailable — skip gracefully
            print("[testFullSpikeOnDevice] SE unavailable (Simulator?) — skipping: \(cfError!.takeRetainedValue())")
            return
        }
        guard let sePublicKey = SecKeyCopyPublicKey(sePrivateKey) else {
            Issue.record("Could not copy SE public key")
            return
        }

        // --- Step 2: Derive kid ---
        var copyErr: Unmanaged<CFError>?
        guard
            let pubKeyData = SecKeyCopyExternalRepresentation(sePublicKey, &copyErr) as Data?,
            // SecKeyCopyExternalRepresentation for EC returns the x963 uncompressed point (04||X||Y).
            // For kid derivation we need the DER SubjectPublicKeyInfo form.
            // Construct DER SPKI for P-256: fixed 26-byte header + 65-byte point = 91 bytes.
            pubKeyData.count == 65
        else {
            Issue.record("Unexpected SE public key representation: \(copyErr?.takeRetainedValue().localizedDescription ?? "nil")")
            return
        }
        // ASN.1 DER SubjectPublicKeyInfo header for P-256 (id-ecPublicKey + prime256v1)
        let spkiHeader = Data([
            0x30, 0x59,             // SEQUENCE (89 bytes)
            0x30, 0x13,             // SEQUENCE (19 bytes) — AlgorithmIdentifier
            0x06, 0x07,             // OID (7 bytes) id-ecPublicKey
            0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01,
            0x06, 0x08,             // OID (8 bytes) prime256v1
            0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07,
            0x03, 0x42, 0x00        // BIT STRING (66 bytes, 0 unused bits)
        ])
        let derPublicKey = spkiHeader + pubKeyData
        let kid = SHA256.hash(data: derPublicKey)
            .compactMap { String(format: "%02x", $0) }.joined()
        #expect(kid.count == 64)

        // --- Step 3: Build manifest ---
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let jpegData = renderer.jpegData(withCompressionQuality: 0.5) { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        let contentHash = SHA256.hash(data: jpegData)
            .compactMap { String(format: "%02x", $0) }.joined()

        let manifest = C2PAManifest(
            schemaVersion: "zoe.media.v1",
            kid: kid,
            contentHash: contentHash,
            assetId: UUID().uuidString,
            captureTimestamp: ISO8601DateFormatter().string(from: Date()),
            appVersion: "test",
            iosVersion: UIDevice.current.systemVersion,
            deviceModel: deviceModelString()
        )

        // --- Step 4: Sign canonical manifest JSON with SE key ---
        let canonicalData = try manifest.canonicalJSON()
        guard SecKeyIsAlgorithmSupported(sePrivateKey, .sign, .ecdsaSignatureMessageX962SHA256) else {
            Issue.record("SE key does not support ECDSA P-256 signing")
            return
        }
        var signErr: Unmanaged<CFError>?
        guard let seSignature = SecKeyCreateSignature(
            sePrivateKey,
            .ecdsaSignatureMessageX962SHA256,
            canonicalData as CFData,
            &signErr
        ) as Data? else {
            Issue.record("SE signing failed: \(signErr!.takeRetainedValue())")
            return
        }

        // --- Step 5: Verify SE signature ---
        var verifyErr: Unmanaged<CFError>?
        let verified = SecKeyVerifySignature(
            sePublicKey,
            .ecdsaSignatureMessageX962SHA256,
            canonicalData as CFData,
            seSignature as CFData,
            &verifyErr
        )
        #expect(verified, "SE signature must verify against SE public key")

        // --- Step 6: C2PA embed/extract round-trip (software signer wraps the assertion) ---
        let signer = try Signer(
            certsPEM: C2PATestCredentials.certsPEM,
            privateKeyPEM: C2PATestCredentials.privateKeyPEM,
            algorithm: .es256,
            tsaURL: nil
        )
        let embeddedJPEG = try await Task.detached(priority: .userInitiated) {
            try C2PAEmbedder.embed(manifest: manifest, signer: signer, into: jpegData)
        }.value
        #expect(embeddedJPEG.count > jpegData.count)

        let extractedJSON = try await Task.detached(priority: .userInitiated) {
            try C2PAEmbedder.extract(from: embeddedJPEG)
        }.value
        #expect(!extractedJSON.isEmpty)
        let parsed = try JSONSerialization.jsonObject(with: Data(extractedJSON.utf8)) as! [String: Any]
        #expect(parsed["manifests"] != nil)
    }

    // MARK: - Task 6.3 (continued): Full embed/extract round-trip with software signer

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

        let embeddedJPEG = try await Task.detached(priority: .userInitiated) {
            try C2PAEmbedder.embed(manifest: manifest, signer: signer, into: jpegData)
        }.value
        #expect(embeddedJPEG.count > jpegData.count)

        let extractedJSON = try await Task.detached(priority: .userInitiated) {
            try C2PAEmbedder.extract(from: embeddedJPEG)
        }.value
        #expect(!extractedJSON.isEmpty)
        let parsedResult = try JSONSerialization.jsonObject(with: Data(extractedJSON.utf8)) as! [String: Any]
        #expect(parsedResult["manifests"] != nil)
    }

    // MARK: - Story 2.5 Tests

    @Test("sign(fileURL:) with no keyManager set: unsigned fallback, no throw")
    func testSignFileURL_unsignedFallback() async throws {
        let pipeline = SigningPipeline()
        // No keyManager → isSigningAvailable == false → unsigned fallback path

        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).jpg")
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let jpegData = renderer.jpegData(withCompressionQuality: 0.5) { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        try jpegData.write(to: tmpURL)
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        // saveToPhotoLibrary silently fails in test environment — focus is no-crash/no-throw
        try await pipeline.sign(fileURL: tmpURL)
    }

    @Test("sign(fileURL:) with software key KeyManager completes without throwing")
    func testSignFileURL_happyPath_softwareKey() async throws {
        let softKey = P256.Signing.PrivateKey()
        let km = KeyManager(
            attestationService: MockAttestationService(),
            networking: MockNetworking(),
            seKeyFactory: { (softKey.rawRepresentation, softKey.publicKey) },
            initialStateOverride: .registered,
            keychainNamespace: UUID().uuidString
        )
        await km.initialise()

        let pipeline = SigningPipeline()
        await pipeline.setKeyManager(km)

        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).jpg")
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let jpegData = renderer.jpegData(withCompressionQuality: 0.5) { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        try jpegData.write(to: tmpURL)
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        // On simulator: SE key unavailable → do/catch triggers unsigned fallback → no throw
        // Photos save silently fails in test environment — focus is no-crash/no-throw
        try await pipeline.sign(fileURL: tmpURL)
    }

    @Test("sign(fileURL:) with unavailable KeyManager completes under 500ms")
    func testSignFileURL_nonBlocking_500ms() async throws {
        let pipeline = SigningPipeline()
        // No keyManager → fastest path (unsigned fallback, no SE ops)

        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).jpg")
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let jpegData = renderer.jpegData(withCompressionQuality: 0.5) { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        try jpegData.write(to: tmpURL)
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        let start = Date()
        try await pipeline.sign(fileURL: tmpURL)
        #expect(Date().timeIntervalSince(start) < 0.5)
    }
}
