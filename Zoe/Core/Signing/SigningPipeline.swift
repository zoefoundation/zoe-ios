import Foundation
import CryptoKit
import Photos
import UIKit

/// Outcome of `SigningPipeline.sign(fileURL:)`, carrying the sandbox URL and provenance state.
/// Sendable: URL and VerificationState (String rawValue enum) are both Sendable.
struct SigningOutcome: Sendable {
    let sandboxURL: URL
    let verificationState: VerificationState
}

/// Orchestrates the full signing pipeline: payload construction → CryptoKit SE signing → proof upload.
actor SigningPipeline {

    private weak var keyManager: KeyManager?
    private var apiClient: (any SigningAPIClient)?

    func setKeyManager(_ km: KeyManager) {
        self.keyManager = km
    }

    func setAPIClient(_ client: any SigningAPIClient) {
        self.apiClient = client
    }

    /// Called by CaptureViewModel after each photo or video capture.
    /// Hashes the file, builds a `zoe.media.v1` proof payload, signs via SE key,
    /// uploads the proof bundle, and saves the original file to Photos.
    /// All errors are silently absorbed — the unsigned original is saved as a fallback (NFR13).
    ///
    /// - Parameter fileURL: URL of the encoded media file in the temp directory.
    /// - Returns: `SigningOutcome` with sandbox URL and verification state, or nil if sandbox save failed.
    @discardableResult
    func sign(fileURL: URL) async throws -> SigningOutcome? {
        guard let km = keyManager else {
            let sandboxURL = saveToSandbox(url: fileURL)
            await saveToPhotoLibrary(url: fileURL, isVideo: fileURL.isVideoFile)
            try? FileManager.default.removeItem(at: fileURL)
            return sandboxURL.map { SigningOutcome(sandboxURL: $0, verificationState: .unsigned) }
        }

        let (isAvailable, kid) = await MainActor.run { (km.isSigningAvailable, km.kid) }
        guard isAvailable, let kid else {
            let sandboxURL = saveToSandbox(url: fileURL)
            await saveToPhotoLibrary(url: fileURL, isVideo: fileURL.isVideoFile)
            try? FileManager.default.removeItem(at: fileURL)
            return sandboxURL.map { SigningOutcome(sandboxURL: $0, verificationState: .unsigned) }
        }

        do {
            // 1. Read file bytes for hashing
            let fileData = try Data(contentsOf: fileURL)

            // 2. Compute SHA-256 content hash
            let contentHash = SHA256.hash(data: fileData)
                .compactMap { String(format: "%02x", $0) }.joined()

            // 3. Gather payload field values
            let iosVersion = await UIDevice.current.systemVersion
            let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown"

            // 4. Build ZoeProofPayload
            let payload = ZoeProofPayload(
                schemaVersion: "zoe.media.v1",
                kid: kid,
                contentHash: contentHash,
                assetId: UUID().uuidString,
                captureTimestamp: ISO8601DateFormatter().string(from: Date()),
                appVersion: appVersion,
                iosVersion: iosVersion,
                deviceModel: deviceModelString()
            )

            // 5. Sign canonical JSON bytes via SE private key in KeyManager
            let canonicalData = try payload.canonicalJSON()
            let signature = try await km.sign(data: canonicalData)
            let signatureB64 = signature.derRepresentation.base64EncodedString()

            // 6. Upload proof bundle to server
            let bundle = ProofBundleRequest(
                payload: payload.toDict(),
                signatureB64: signatureB64,
                algorithm: "ES256"
            )

            // 7. Save ORIGINAL file to sandbox and Photos (before upload attempt)
            let sandboxURL = saveToSandbox(url: fileURL)
            await saveToPhotoLibrary(url: fileURL, isVideo: fileURL.isVideoFile)
            try? FileManager.default.removeItem(at: fileURL)

            if let client = apiClient {
                do {
                    _ = try await client.uploadProof(bundle)
                    return sandboxURL.map { SigningOutcome(sandboxURL: $0, verificationState: .signed) }
                } catch {
                    // Upload failed (e.g. offline) — file is signed locally, proof upload is pending
                    return sandboxURL.map { SigningOutcome(sandboxURL: $0, verificationState: .pending) }
                }
            }
            return sandboxURL.map { SigningOutcome(sandboxURL: $0, verificationState: .signed) }

        } catch {
            // Signing itself failed (SE unavailable, key revoked, etc.) — save unsigned original (NFR13)
            let sandboxURL = saveToSandbox(url: fileURL)
            await saveToPhotoLibrary(url: fileURL, isVideo: fileURL.isVideoFile)
            try? FileManager.default.removeItem(at: fileURL)
            return sandboxURL.map { SigningOutcome(sandboxURL: $0, verificationState: .unsigned) }
        }
    }

    /// Re-signs an already-sandboxed file and retries the proof upload.
    /// Unlike `sign()`, this does NOT copy, move, or delete any files.
    /// Used to recover `.pending` items when network connectivity returns.
    /// - Returns: `true` if proof was successfully uploaded, `false` otherwise.
    func retryUpload(fileURL: URL) async -> Bool {
        guard let km = keyManager, let client = apiClient else { return false }
        let (isAvailable, kid) = await MainActor.run { (km.isSigningAvailable, km.kid) }
        guard isAvailable, let kid else { return false }
        do {
            let fileData = try Data(contentsOf: fileURL)
            let contentHash = SHA256.hash(data: fileData)
                .map { String(format: "%02x", $0) }.joined()
            let iosVersion = await UIDevice.current.systemVersion
            let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown"
            let payload = ZoeProofPayload(
                schemaVersion: "zoe.media.v1",
                kid: kid,
                contentHash: contentHash,
                assetId: UUID().uuidString,
                captureTimestamp: ISO8601DateFormatter().string(from: Date()),
                appVersion: appVersion,
                iosVersion: iosVersion,
                deviceModel: deviceModelString()
            )
            let canonicalData = try payload.canonicalJSON()
            let signature = try await km.sign(data: canonicalData)
            let signatureB64 = signature.derRepresentation.base64EncodedString()
            let bundle = ProofBundleRequest(
                payload: payload.toDict(),
                signatureB64: signatureB64,
                algorithm: "ES256"
            )
            _ = try await client.uploadProof(bundle)
            return true
        } catch {
            return false
        }
    }

    nonisolated private func saveToSandbox(url: URL) -> URL? {
        let mediaDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ZoeMedia")
        try? FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true, attributes: nil)
        let dest = mediaDir.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.copyItem(at: url, to: dest)
            return dest
        } catch {
            return nil
        }
    }

    private func saveToPhotoLibrary(url: URL, isVideo: Bool) async {
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

