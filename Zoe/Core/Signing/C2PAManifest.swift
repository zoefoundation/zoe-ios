import Foundation
import CryptoKit
import UIKit

/// Full `zoe.media.v1` manifest schema for C2PA-style provenance embedding.
struct C2PAManifest: Sendable {
    let schemaVersion: String   // "zoe.media.v1"
    let kid: String             // lowercase hex SHA-256 of DER public key
    let contentHash: String     // lowercase hex SHA-256 of final encoded JPEG bytes
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

    /// Returns C2PA-compatible manifest JSON for use with the `c2pa-ios` `Builder` API.
    /// Wraps our custom fields as a `zoe.media.v1` custom assertion.
    nonisolated func c2paManifestJSON() throws -> String {
        let assertionData: [String: Any] = [
            "schema_version": schemaVersion,
            "kid": kid,
            "content_hash": contentHash,
            "asset_id": assetId,
            "capture_timestamp": captureTimestamp,
            "app_version": appVersion,
            "ios_version": iosVersion,
            "device_model": deviceModel
        ]
        let assertion: [String: Any] = [
            "label": "zoe.media.v1",
            "data": assertionData
        ]
        let manifestDict: [String: Any] = [
            "claim_generator": "ZoeApp/\(appVersion)",
            "format": "image/jpeg",
            "title": "Zoe Media",
            "assertions": [assertion]
        ]
        let data = try JSONSerialization.data(withJSONObject: manifestDict, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// Decode from a JSON dictionary.
    nonisolated static func decode(from jsonData: Data) throws -> C2PAManifest {
        guard let dict = try JSONSerialization.jsonObject(with: jsonData) as? [String: String] else {
            throw C2PADecodeError.invalidJSON
        }
        guard let schemaVersion = dict["schema_version"],
              let kid = dict["kid"],
              let contentHash = dict["content_hash"],
              let assetId = dict["asset_id"],
              let captureTimestamp = dict["capture_timestamp"],
              let appVersion = dict["app_version"],
              let iosVersion = dict["ios_version"],
              let deviceModel = dict["device_model"]
        else { throw C2PADecodeError.missingField }

        return C2PAManifest(
            schemaVersion: schemaVersion,
            kid: kid,
            contentHash: contentHash,
            assetId: assetId,
            captureTimestamp: captureTimestamp,
            appVersion: appVersion,
            iosVersion: iosVersion,
            deviceModel: deviceModel
        )
    }
}

enum C2PADecodeError: Error {
    case invalidJSON
    case missingField
}

/// Manifest + detached signature pair (kept for reference; not used in SPM path).
struct C2PASignedManifest: Sendable {
    let manifest: C2PAManifest
    let signature: Data
}

extension C2PAManifest {
    nonisolated func signed(with signature: Data) -> C2PASignedManifest {
        C2PASignedManifest(manifest: self, signature: signature)
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
