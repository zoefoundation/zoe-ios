import Foundation
import C2PA
import CryptoKit

/// Embed strategy used in Epic 2 (recorded in spike result doc).
let embedStrategy = "c2pa-ios/v0.0.8"

/// C2PA manifest embedder / extractor using the official `c2pa-ios` Swift Package.
///
/// Uses file-based streams (required by the Builder API); temp files are created
/// and cleaned up within each call.
struct C2PAEmbedder: Sendable {

    // MARK: - Embed

    /// Embed a C2PA manifest into a JPEG byte buffer using the c2pa-ios `Builder` API.
    nonisolated static func embed(manifest: C2PAManifest, signer: Signer, into jpegData: Data) throws -> Data {
        let manifestJSON = try manifest.c2paManifestJSON()
        let builder = try Builder(manifestJSON: manifestJSON)

        let tmpDir = FileManager.default.temporaryDirectory
        let srcURL = tmpDir.appendingPathComponent("\(UUID().uuidString).jpg")
        let dstURL = tmpDir.appendingPathComponent("\(UUID().uuidString).jpg")
        defer {
            try? FileManager.default.removeItem(at: srcURL)
            try? FileManager.default.removeItem(at: dstURL)
        }

        try jpegData.write(to: srcURL)
        let srcStream = try Stream(readFrom: srcURL)
        let dstStream = try Stream(writeTo: dstURL)

        _ = try builder.sign(format: "image/jpeg", source: srcStream, destination: dstStream, signer: signer)
        return try Data(contentsOf: dstURL)
    }

    /// Embed a C2PA manifest into a media file using file-URL streams.
    /// Returns the URL of the signed output temp file. Caller is responsible for cleanup.
    nonisolated static func embedFile(
        manifest: C2PAManifest,
        signer: Signer,
        at sourceURL: URL,
        format: String
    ) throws -> URL {
        let manifestJSON = try manifest.c2paManifestJSON()
        let builder = try Builder(manifestJSON: manifestJSON)

        let ext = sourceURL.pathExtension.isEmpty ? "tmp" : sourceURL.pathExtension
        let dstURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).\(ext)")

        let srcStream = try Stream(readFrom: sourceURL)
        let dstStream = try Stream(writeTo: dstURL)
        _ = try builder.sign(format: format, source: srcStream, destination: dstStream, signer: signer)
        return dstURL
    }

    // MARK: - Extract

    /// Extract the C2PA manifest JSON from a signed JPEG.
    nonisolated static func extract(from jpegData: Data) throws -> String {
        let tmpDir = FileManager.default.temporaryDirectory
        let srcURL = tmpDir.appendingPathComponent("\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: srcURL) }

        try jpegData.write(to: srcURL)
        return try C2PA.readFile(at: srcURL)
    }
}

// MARK: - Errors

enum C2PAError: Error, Sendable {
    case invalidInput
    case embedFailed
    case manifestNotFound
    case decodingFailed(String)
}
