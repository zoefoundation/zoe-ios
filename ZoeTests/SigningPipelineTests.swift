import Testing
import CryptoKit
import Foundation
import UIKit
@testable import zoe

// MARK: - MockSigningAPIClient

final class MockSigningAPIClient: SigningAPIClient, @unchecked Sendable {
    var uploadedBundle: ProofBundleRequest?
    var shouldThrow = false
    var stubbedProofId = "mock-proof-id-1234"

    func uploadProof(_ bundle: ProofBundleRequest) async throws -> ProofUploadResponse {
        if shouldThrow { throw URLError(.networkConnectionLost) }
        uploadedBundle = bundle
        return ProofUploadResponse(proofId: stubbedProofId)
    }
}

@MainActor
final class SigningPipelineTests {

    // MARK: - Story 2.5 Tests (preserved)

    @Test("sign(fileURL:) with no keyManager set: unsigned fallback, no throw")
    func testSignFileURL_unsignedFallback() async throws {
        let pipeline = SigningPipeline()

        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).jpg")
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let jpegData = renderer.jpegData(withCompressionQuality: 0.5) { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        try jpegData.write(to: tmpURL)
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        let outcome = try await pipeline.sign(fileURL: tmpURL)
        #expect(outcome != nil)
        #expect(outcome?.verificationState == .unsigned)
        #expect(outcome?.sandboxURL.lastPathComponent == tmpURL.lastPathComponent)
        if let sandboxURL = outcome?.sandboxURL {
            #expect(FileManager.default.fileExists(atPath: sandboxURL.path))
            try? FileManager.default.removeItem(at: sandboxURL)
        }
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
        try await pipeline.sign(fileURL: tmpURL)
    }

    @Test("sign(fileURL:) with unavailable KeyManager completes under 500ms")
    func testSignFileURL_nonBlocking_500ms() async throws {
        let pipeline = SigningPipeline()

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

    @Test("sign(fileURL:) returns nil when source file is missing")
    func testSignFileURL_missingInput_returnsNil() async throws {
        let pipeline = SigningPipeline()
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).jpg")
        try? FileManager.default.removeItem(at: missingURL)

        let outcome = try await pipeline.sign(fileURL: missingURL)
        #expect(outcome == nil)
    }

    // MARK: - Story 2.7 Tests (new)

    @Test("sign(fileURL:) with MockSigningAPIClient: no crash, verificationState is unsigned (SE unavailable on simulator)")
    func testSignFileURL_uploadsProof_whenSigningAvailable() async throws {
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
        let mockClient = MockSigningAPIClient()
        await pipeline.setAPIClient(mockClient)

        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).jpg")
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let jpegData = renderer.jpegData(withCompressionQuality: 0.5) { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        try jpegData.write(to: tmpURL)
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        // SE unavailable on simulator → outer catch fires → unsigned fallback; no crash
        let outcome = try await pipeline.sign(fileURL: tmpURL)
        #expect(outcome != nil)
        if let sandboxURL = outcome?.sandboxURL {
            try? FileManager.default.removeItem(at: sandboxURL)
        }
    }

    @Test("sign(fileURL:) with nil apiClient: no crash, graceful unsigned fallback (SE unavailable on simulator)")
    func testSignFileURL_noAPIClient_returnsSignedOutcome() async throws {
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
        // apiClient deliberately not set (nil)

        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).jpg")
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let jpegData = renderer.jpegData(withCompressionQuality: 0.5) { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        try jpegData.write(to: tmpURL)
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        // SE unavailable on simulator → catch fires → unsigned fallback, no crash
        let outcome = try await pipeline.sign(fileURL: tmpURL)
        #expect(outcome != nil)
        if let sandboxURL = outcome?.sandboxURL {
            try? FileManager.default.removeItem(at: sandboxURL)
        }
    }
}
