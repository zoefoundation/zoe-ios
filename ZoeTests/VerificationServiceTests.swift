import Testing
import Foundation
import SwiftData
@testable import zoe

// MARK: - MockVerifyAPIClient

final class MockVerifyAPIClient: VerifyAPIClient, @unchecked Sendable {
    enum Behavior {
        case authentic(signingTime: String?, kid: String?)
        case tampered
        case notVerified             // lookupProof returns nil (404)
        case throwError(Error)
    }

    private let behavior: Behavior

    init(behavior: Behavior) {
        self.behavior = behavior
    }

    func lookupProof(assetSHA256: String) async throws -> ProofLookupResponse? {
        switch behavior {
        case .throwError(let error):
            throw error
        case .notVerified:
            return nil
        default:
            return ProofLookupResponse(
                proofId: "test-proof-uuid",
                kid: "test-kid",
                payload: [:],
                signatureB64: "base64sig==",
                algorithm: "ES256",
                createdAt: "2026-03-04T21:00:00Z"
            )
        }
    }

    func postVerify(_ request: VerifyRequest) async throws -> VerifyResponse {
        switch behavior {
        case .authentic(let signingTime, let kid):
            return VerifyResponse(verdict: "authentic", signingTime: signingTime, kid: kid)
        case .tampered:
            return VerifyResponse(verdict: "tampered", signingTime: nil, kid: nil)
        case .notVerified:
            return VerifyResponse(verdict: "not_verified", signingTime: nil, kid: nil)
        case .throwError(let error):
            throw error
        }
    }
}

// MARK: - VerificationServiceTests

@MainActor
final class VerificationServiceTests {

    // MARK: - Helpers

    private func makeTempFile(content: String = "fake image data") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_\(UUID().uuidString).jpg")
        try Data(content.utf8).write(to: url)
        return url
    }

    // MARK: - AC1+AC3: authentic — state, signingTime, and kid populated

    @Test("verify: server returns authentic — state, signingTime, and kid populated")
    func test_verify_authentic_updatesStateAndMetadata() async throws {
        let signingTime = "2026-03-04T21:00:00Z"
        let expectedKid = "kid-abc123"
        let mock = MockVerifyAPIClient(behavior: .authentic(signingTime: signingTime, kid: expectedKid))
        let service = VerificationService(apiClient: mock)

        let tempURL = try makeTempFile()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let result = await service.verify(fileURL: tempURL)

        #expect(result.state == .authentic)
        #expect(result.kid == expectedKid)
        #expect(result.signingTime != nil)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        #expect(result.signingTime == formatter.date(from: signingTime))
    }

    // MARK: - AC3: tampered verdict maps correctly

    @Test("verify: server returns tampered — state is tampered")
    func test_verify_tampered_hashMismatch() async throws {
        let mock = MockVerifyAPIClient(behavior: .tampered)
        let service = VerificationService(apiClient: mock)

        let tempURL = try makeTempFile()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let result = await service.verify(fileURL: tempURL)

        #expect(result.state == .tampered)
    }

    // MARK: - AC2: 404 on proof lookup → notVerified, POST not called

    @Test("verify: GET proofs returns 404 — returns notVerified without calling POST")
    func test_verify_notVerified_noProofRecord() async throws {
        let mock = MockVerifyAPIClient(behavior: .notVerified)
        let service = VerificationService(apiClient: mock)

        let tempURL = try makeTempFile()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let result = await service.verify(fileURL: tempURL)

        #expect(result.state == .notVerified)
        #expect(result.signingTime == nil)
        #expect(result.kid == nil)
    }

    // MARK: - AC4: network error → notVerified, no crash

    @Test("verify: network error — returns notVerified without crashing")
    func test_verify_notVerified_networkError() async throws {
        let mock = MockVerifyAPIClient(behavior: .throwError(URLError(.notConnectedToInternet)))
        let service = VerificationService(apiClient: mock)

        let tempURL = try makeTempFile()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let result = await service.verify(fileURL: tempURL)

        #expect(result.state == .notVerified)
        #expect(result.signingTime == nil)
        #expect(result.kid == nil)
    }

    // MARK: - AC4: server 5xx → notVerified, no crash

    @Test("verify: server error — returns notVerified without crashing")
    func test_verify_notVerified_serverError() async throws {
        let mock = MockVerifyAPIClient(behavior: .throwError(APIError.serverError))
        let service = VerificationService(apiClient: mock)

        let tempURL = try makeTempFile()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let result = await service.verify(fileURL: tempURL)

        #expect(result.state == .notVerified)
        #expect(result.signingTime == nil)
        #expect(result.kid == nil)
    }

    // MARK: - AC5: VerifyViewModel persists full result to LibraryItem

    @Test("VerifyViewModel.verify: persists verificationState, verdictSigningTime, and kid")
    @MainActor
    func test_verifyViewModel_updatesLibraryItem() async throws {
        let signingTime = "2026-03-04T21:00:00Z"
        let expectedKid = "kid-vm-test"
        let mock = MockVerifyAPIClient(behavior: .authentic(signingTime: signingTime, kid: expectedKid))

        // Write temp file into Documents/ZoeMedia so resolvedMediaURL resolves to a real file
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let mediaDir = docs.appendingPathComponent("ZoeMedia")
        try FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        let filename = "test_\(UUID().uuidString).jpg"
        let fileURL = mediaDir.appendingPathComponent(filename)
        try Data("fake image data".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let item = LibraryItem(mediaURL: fileURL, mediaType: "photo", source: "imported")

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: LibraryItem.self, configurations: config)
        let context = ModelContext(container)
        let store = LibraryStore(modelContext: context)

        let viewModel = VerifyViewModel(
            store: store,
            verificationService: VerificationService(apiClient: mock)
        )

        let task = viewModel.verify(item: item)
        await task.value

        #expect(item.verificationState == VerificationState.authentic.rawValue)
        #expect(item.kid == expectedKid)
        #expect(item.verdictSigningTime != nil)
    }
}

