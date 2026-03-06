import Foundation
import C2PA
import CryptoKit
import UIKit

/// Orchestrates the full signing pipeline: manifest construction → C2PA embedding via c2pa-ios.
actor SigningPipeline {

    /// Sign and embed a provenance manifest into JPEG data.
    ///
    /// - Parameters:
    ///   - jpegData: The original JPEG bytes to sign.
    ///   - signer: A `Signer` (software PEM for simulator; SecureEnclave for device).
    ///   - signingKey: Optional P256 key used to derive the `kid` field. If nil, uses a placeholder.
    nonisolated func sign(
        jpegData: Data,
        signer: Signer,
        signingKey: P256.Signing.PrivateKey? = nil
    ) async throws -> Data {
        let contentHash = SHA256.hash(data: jpegData)
            .compactMap { String(format: "%02x", $0) }.joined()

        let iosVersion = await UIDevice.current.systemVersion
        let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown"

        let kid = signingKey.map { deriveKid(from: $0.publicKey) } ?? "spike-test-key"

        let manifest = C2PAManifest(
            schemaVersion: "zoe.media.v1",
            kid: kid,
            contentHash: contentHash,
            assetId: UUID().uuidString,
            captureTimestamp: ISO8601DateFormatter().string(from: Date()),
            appVersion: appVersion,
            iosVersion: iosVersion,
            deviceModel: deviceModelString()
        )

        return try C2PAEmbedder.embed(manifest: manifest, signer: signer, into: jpegData)
    }
}
