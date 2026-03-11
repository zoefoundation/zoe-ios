import Foundation
import C2PA
import CryptoKit
import Photos
import UIKit

/// Orchestrates the full signing pipeline: manifest construction → C2PA embedding via c2pa-ios.
actor SigningPipeline {

    private weak var keyManager: KeyManager?

    func setKeyManager(_ km: KeyManager) {
        self.keyManager = km
    }

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

    /// Called by CaptureViewModel after each photo or video capture.
    /// Hashes the file, builds a `zoe.media.v1` C2PA manifest, signs via SE, embeds, and saves to Photos.
    /// All errors are silently absorbed — the unsigned original is saved as a fallback (NFR13).
    ///
    /// - Parameter fileURL: URL of the encoded media file in the temp directory.
    func sign(fileURL: URL) async throws {
        guard let km = keyManager else {
            await saveToPhotoLibrary(url: fileURL, isVideo: fileURL.isVideoFile)
            try? FileManager.default.removeItem(at: fileURL)
            return
        }

        let (isAvailable, kid) = await MainActor.run { (km.isSigningAvailable, km.kid) }
        guard isAvailable, let kid else {
            await saveToPhotoLibrary(url: fileURL, isVideo: fileURL.isVideoFile)
            try? FileManager.default.removeItem(at: fileURL)
            return
        }

        do {
            // 1. Read file bytes for hashing
            let fileData = try Data(contentsOf: fileURL)

            // 2. Compute SHA-256 content hash
            let contentHash = SHA256.hash(data: fileData)
                .compactMap { String(format: "%02x", $0) }.joined()

            // 3. Gather manifest field values
            let iosVersion = await UIDevice.current.systemVersion
            let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown"

            // 4. Build C2PAManifest (all zoe.media.v1 fields — per spec-freeze.md)
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

            // 5. Construct SE-backed c2pa-ios Signer via KeyManager
            let signer = try await km.makeC2PASigner(certsPEM: ZoeSigningCredentials.certsPEM)

            // 6. Determine MIME format from file extension
            let format = fileURL.c2paFormat

            // 7. Embed manifest into file (uses file-URL streams — memory-efficient for video)
            let signedURL = try C2PAEmbedder.embedFile(
                manifest: manifest,
                signer: signer,
                at: fileURL,
                format: format
            )

            // 8. Save signed file to Photos library, clean up both temp files
            await saveToPhotoLibrary(url: signedURL, isVideo: fileURL.isVideoFile)
            try? FileManager.default.removeItem(at: signedURL)
            try? FileManager.default.removeItem(at: fileURL)

        } catch {
            // SILENT ERROR ABSORPTION: signing failed — save unsigned original (NFR13)
            await saveToPhotoLibrary(url: fileURL, isVideo: fileURL.isVideoFile)
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private func saveToPhotoLibrary(url: URL, isVideo: Bool) async {
        // Use current status only — permission must be requested from a UI context (CaptureViewModel.configure)
        // to avoid blocking background/test contexts with a system dialog.
        let authStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard authStatus == .authorized || authStatus == .limited else { return }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let req = PHAssetCreationRequest.forAsset()
                let type: PHAssetResourceType = isVideo ? .video : .photo
                req.addResource(with: type, fileURL: url, options: nil)
            }
        } catch {
            // Photos save failed — silently absorb (capture is already complete, NFR13)
        }
    }
}
