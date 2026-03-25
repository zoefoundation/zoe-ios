import Foundation
import CryptoKit
import UIKit

/// Full `zoe.media.v1` proof payload for detached signed proof bundles.
struct ZoeProofPayload: Sendable {
    let schemaVersion: String   // "zoe.media.v1"
    let kid: String             // lowercase hex SHA-256 of DER public key
    let contentHash: String     // lowercase hex SHA-256 of final encoded file bytes
    let assetId: String         // UUID v4
    let captureTimestamp: String // ISO 8601 UTC e.g. "2026-03-04T21:00:00Z"
    let appVersion: String      // CFBundleShortVersionString
    let iosVersion: String      // UIDevice.current.systemVersion
    let deviceModel: String     // utsname machine string e.g. "iPhone15,2"

    nonisolated init(
        schemaVersion: String,
        kid: String,
        contentHash: String,
        assetId: String,
        captureTimestamp: String,
        appVersion: String,
        iosVersion: String,
        deviceModel: String
    ) {
        self.schemaVersion = schemaVersion
        self.kid = kid
        self.contentHash = contentHash
        self.assetId = assetId
        self.captureTimestamp = captureTimestamp
        self.appVersion = appVersion
        self.iosVersion = iosVersion
        self.deviceModel = deviceModel
    }

    /// Returns canonical JSON for signing: snake_case keys, alphabetically sorted, no whitespace, UTF-8.
    /// The server recanonicalizes using: json.dumps(payload, sort_keys=True, separators=(',', ':')).encode('utf-8')
    nonisolated func canonicalJSON() throws -> Data {
        let dict: [String: Any] = [
            "app_version": appVersion,
            "asset_id": assetId,
            "capture_timestamp": captureTimestamp,
            "content_hash": contentHash,
            "device_model": deviceModel,
            "ios_version": iosVersion,
            "kid": kid,
            "schema_version": schemaVersion
        ]
        return try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
    }

    /// Returns the 8 canonical fields as a dictionary matching the server's expected wire format.
    nonisolated func toDict() -> [String: String] {
        return [
            "app_version": appVersion,
            "asset_id": assetId,
            "capture_timestamp": captureTimestamp,
            "content_hash": contentHash,
            "device_model": deviceModel,
            "ios_version": iosVersion,
            "kid": kid,
            "schema_version": schemaVersion
        ]
    }
}

// MARK: - Helpers

/// Derive the kid (key ID) from a P256 public key: lowercase hex SHA-256 of DER representation.
nonisolated func deriveKid(from publicKey: P256.Signing.PublicKey) -> String {
    let derBytes = publicKey.derRepresentation
    let hash = SHA256.hash(data: derBytes)
    return hash.compactMap { String(format: "%02x", $0) }.joined()
}

/// Read device model string from utsname (e.g. "iPhone15,2").
nonisolated func deviceModelString() -> String {
    var sysInfo = utsname()
    uname(&sysInfo)
    return withUnsafeBytes(of: &sysInfo.machine) { bytes in
        bytes.compactMap { $0 == 0 ? nil : Character(UnicodeScalar($0)) }
            .map { String($0) }.joined()
    }
}
