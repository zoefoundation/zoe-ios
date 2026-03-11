import Testing
import CryptoKit
import Foundation
@testable import zoe

// MARK: - MockAttestationService

final class MockAttestationService: AttestationService, @unchecked Sendable {
    var isSupported: Bool = true
    var generateKeyIDResult: Result<String, Error> = .success("mock-attest-key-id")
    var attestKeyResult: Result<Data, Error> = .success(Data("mock-attestation".utf8))

    func generateKeyID() async throws -> String {
        try generateKeyIDResult.get()
    }

    func attestKey(keyID: String, clientDataHash: Data) async throws -> Data {
        try attestKeyResult.get()
    }
}

// MARK: - MockNetworking

final class MockNetworking: KeyManagerNetworking, @unchecked Sendable {
    var challengeResult: Result<ChallengeResponse, Error> =
        .success(ChallengeResponse(challenge: "test-challenge", expiresAt: "2026-03-05T00:00:00Z"))
    var registerResults: [Result<RegisterResponse, Error>] = [
        .success(RegisterResponse(status: "registered"))
    ]
    private(set) var registerCallCount = 0

    func challenge(kid: String?) async throws -> ChallengeResponse {
        try challengeResult.get()
    }

    func registerKey(_ request: RegisterRequest) async throws -> RegisterResponse {
        let index = min(registerCallCount, registerResults.count - 1)
        registerCallCount += 1
        return try registerResults[index].get()
    }
}

// MARK: - KeyManager Test Factory

private func makeSoftKeyFactory() -> (dataRep: Data, publicKey: P256.Signing.PublicKey) {
    let softKey = P256.Signing.PrivateKey()
    return (softKey.rawRepresentation, softKey.publicKey)
}

@MainActor
private func makeKeyManager(
    attestation: MockAttestationService = MockAttestationService(),
    networking: MockNetworking = MockNetworking(),
    initialStateOverride: RegistrationState? = nil
) -> KeyManager {
    let keyPair = makeSoftKeyFactory()
    return KeyManager(
        attestationService: attestation,
        networking: networking,
        seKeyFactory: { keyPair },
        initialStateOverride: initialStateOverride,
        keychainNamespace: UUID().uuidString
    )
}

// MARK: - KeyManagerTests

@Suite("KeyManagerTests")
struct KeyManagerTests {
    // Test 1: initial state is .unknown before initialise()
    @Test("State is .unknown before initialise")
    func testInitialStateIsUnknown() async {
        let state = await MainActor.run {
            let km = makeKeyManager()
            return km.state
        }
        #expect(state == .unknown)
    }

    // Test 2: .registering → .registered (happy path)
    @Test("Happy path: registering → registered")
    func testHappyPath() async {
        let km = await MainActor.run { makeKeyManager() }
        await km.initialise()
        let (state, kidLen, sigAvail) = await MainActor.run {
            (km.state, km.kid?.count, km.isSigningAvailable)
        }
        #expect(state == .registered)
        #expect(sigAvail == true)
        #expect(kidLen == 64)
    }

    // Test 3: transient failure then success → .registered
    @Test("Transient failure then success: registering → retrying → registering → registered")
    func testTransientThenSuccess() async {
        let networking = MockNetworking()
        networking.registerResults = [
            .failure(APIError.serverError),
            .success(RegisterResponse(status: "registered"))
        ]
        let km = await MainActor.run { makeKeyManager(networking: networking) }
        await km.initialise()
        let state = await MainActor.run { km.state }
        #expect(state == .registered)
        #expect(networking.registerCallCount == 2)
    }

    // Test 4: attest_invalid → .failedPermanent
    @Test("attest_invalid → failedPermanent")
    func testAttestInvalid() async {
        let networking = MockNetworking()
        networking.registerResults = [
            .failure(APIError.definitiveFailure(code: "attest_invalid"))
        ]
        let km = await MainActor.run { makeKeyManager(networking: networking) }
        await km.initialise()
        let (state, sigAvail) = await MainActor.run { (km.state, km.isSigningAvailable) }
        #expect(state == .failedPermanent)
        #expect(sigAvail == false)
    }

    // Test 5: device_unauthorized → .failedPermanent
    @Test("device_unauthorized → failedPermanent")
    func testDeviceUnauthorized() async {
        let networking = MockNetworking()
        networking.registerResults = [
            .failure(APIError.definitiveFailure(code: "device_unauthorized"))
        ]
        let km = await MainActor.run { makeKeyManager(networking: networking) }
        await km.initialise()
        let state = await MainActor.run { km.state }
        #expect(state == .failedPermanent)
    }

    // Test 6: .registered → .failedPermanent on device_revoked
    @Test("registered → failedPermanent on device_revoked challenge")
    func testRegisteredToFailedOnRevoked() async {
        let networking = MockNetworking()
        networking.challengeResult = .failure(APIError.definitiveFailure(code: "device_revoked"))
        let km = await MainActor.run { makeKeyManager(networking: networking, initialStateOverride: .registered) }
        await km.initialise()
        let (state, sigAvail) = await MainActor.run { (km.state, km.isSigningAvailable) }
        #expect(state == .failedPermanent)
        #expect(sigAvail == false)
    }

    // Test 7: deriveKid returns 64 lowercase hex chars
    @Test("deriveKid returns 64 lowercase hex chars")
    func testDeriveKid() async {
        let softKey = P256.Signing.PrivateKey()
        let km = await MainActor.run { makeKeyManager() }
        let result = await MainActor.run { km.deriveKid(from: softKey.publicKey) }
        #expect(result.count == 64)
        #expect(result == result.lowercased())
        #expect(result.allSatisfy { $0.isHexDigit })
    }

    // Test 8: kid_conflict is treated as success
    @Test("kid_conflict treated as registered success")
    func testKidConflict() async {
        let networking = MockNetworking()
        networking.registerResults = [
            .failure(APIError.definitiveFailure(code: "kid_conflict"))
        ]
        let km = await MainActor.run { makeKeyManager(networking: networking) }
        await km.initialise()
        let state = await MainActor.run { km.state }
        #expect(state == .registered)
    }

    // Test 9: max retries (3 transient failures) → .failedPermanent
    @Test("3 transient failures → failedPermanent")
    func testMaxRetries() async {
        let networking = MockNetworking()
        networking.registerResults = [
            .failure(APIError.serverError),
            .failure(APIError.serverError),
            .failure(APIError.serverError)
        ]
        let km = await MainActor.run { makeKeyManager(networking: networking) }
        await km.initialise()
        let state = await MainActor.run { km.state }
        #expect(state == .failedPermanent)
    }

    // Test 10: App Attest not supported → .failedPermanent
    @Test("App Attest not supported → failedPermanent")
    func testAttestNotSupported() async {
        let km = await MainActor.run {
            let mockAttest = MockAttestationService()
            mockAttest.isSupported = false
            return makeKeyManager(attestation: mockAttest)
        }
        await km.initialise()
        let state = await MainActor.run { km.state }
        #expect(state == .failedPermanent)
    }

    @Test("challenge_expired followed by definitive failure does not retry transiently")
    func testChallengeExpiredThenDefinitiveFailure() async {
        let networking = MockNetworking()
        networking.registerResults = [
            .failure(APIError.definitiveFailure(code: "challenge_expired")),
            .failure(APIError.definitiveFailure(code: "attest_invalid"))
        ]
        let km = await MainActor.run { makeKeyManager(networking: networking) }
        await km.initialise()
        let state = await MainActor.run { km.state }
        #expect(state == .failedPermanent)
        #expect(networking.registerCallCount == 2)
    }

    // MARK: - B2: lastError tests

    @Test("lastError is set on definitive failure")
    func testLastErrorSetOnDefinitiveFailure() async {
        let networking = MockNetworking()
        networking.registerResults = [
            .failure(APIError.definitiveFailure(code: "attest_invalid"))
        ]
        let km = await MainActor.run { makeKeyManager(networking: networking) }
        await km.initialise()
        let lastError = await MainActor.run { km.lastError }
        #expect(lastError == "attest_invalid")
    }

    @Test("lastError is set on device_unauthorized")
    func testLastErrorSetOnDeviceUnauthorized() async {
        let networking = MockNetworking()
        networking.registerResults = [
            .failure(APIError.definitiveFailure(code: "device_unauthorized"))
        ]
        let km = await MainActor.run { makeKeyManager(networking: networking) }
        await km.initialise()
        let lastError = await MainActor.run { km.lastError }
        #expect(lastError == "device_unauthorized")
    }

    @Test("lastError is nil after successful registration")
    func testLastErrorNilOnSuccess() async {
        let km = await MainActor.run { makeKeyManager() }
        await km.initialise()
        let lastError = await MainActor.run { km.lastError }
        #expect(lastError == nil)
    }

    @Test("resetRegistration clears state and re-registers successfully")
    func testResetRegistrationRecovery() async {
        // Start with a failed state
        let networking = MockNetworking()
        networking.registerResults = [
            .failure(APIError.definitiveFailure(code: "attest_invalid")),
            .success(RegisterResponse(status: "registered"))
        ]
        let km = await MainActor.run { makeKeyManager(networking: networking) }
        await km.initialise()

        // Verify failed state
        let failedState = await MainActor.run { km.state }
        #expect(failedState == .failedPermanent)
        #expect(await MainActor.run { km.lastError } == "attest_invalid")

        // Reset and re-register
        await km.resetRegistration()

        let (finalState, finalLastError, finalKid) = await MainActor.run {
            (km.state, km.lastError, km.kid)
        }
        #expect(finalState == .registered)
        #expect(finalLastError == nil)
        #expect(finalKid?.count == 64)
    }

    @Test("resetRegistration clears registrationLog and starts fresh")
    func testResetRegistrationClearsLog() async {
        let networking = MockNetworking()
        networking.registerResults = [
            .failure(APIError.definitiveFailure(code: "attest_invalid")),
            .success(RegisterResponse(status: "registered"))
        ]
        let km = await MainActor.run { makeKeyManager(networking: networking) }
        await km.initialise()

        let logCountAfterFirstRun = await MainActor.run { km.registrationLog.count }
        #expect(logCountAfterFirstRun > 0)

        await km.resetRegistration()

        // After reset the log starts fresh — old "attest_invalid" entries gone
        let hasOldError = await MainActor.run {
            km.registrationLog.contains { $0.message.contains("attest_invalid") }
        }
        #expect(hasOldError == false)
    }

    // MARK: - B3b: Registration log tests

    @Test("Happy path populates registrationLog with success entries")
    func testHappyPathPopulatesLog() async {
        let km = await MainActor.run { makeKeyManager() }
        await km.initialise()

        let checks = await MainActor.run {
            let log = km.registrationLog
            let stages = Set(log.map { $0.stage })
            return (
                isEmpty: log.isEmpty,
                hasINIT: stages.contains(.INIT),
                hasSTATE: stages.contains(.STATE),
                hasKEY: stages.contains(.KEY),
                hasCOMPLETE: stages.contains(.COMPLETE),
                lastIsSuccess: log.last?.level == .success
            )
        }
        #expect(!checks.isEmpty)
        #expect(checks.hasINIT)
        #expect(checks.hasSTATE)
        #expect(checks.hasKEY)
        #expect(checks.hasCOMPLETE)
        #expect(checks.lastIsSuccess)
    }

    @Test("Definitive failure populates log with error entry")
    func testDefinitiveFailurePopulatesLog() async {
        let networking = MockNetworking()
        networking.registerResults = [
            .failure(APIError.definitiveFailure(code: "attest_invalid"))
        ]
        let km = await MainActor.run { makeKeyManager(networking: networking) }
        await km.initialise()

        let checks = await MainActor.run {
            let log = km.registrationLog
            return (
                isEmpty: log.isEmpty,
                hasError: log.contains { $0.level == .error },
                hasCompleteError: log.first { $0.stage == .COMPLETE && $0.level == .error } != nil
            )
        }
        #expect(!checks.isEmpty)
        #expect(checks.hasError)
        #expect(checks.hasCompleteError)
    }

    @Test("failedPermanent state load logs error entry")
    func testFailedPermanentStateLogsError() async {
        let km = await MainActor.run {
            makeKeyManager(initialStateOverride: .failedPermanent)
        }
        await km.initialise()

        let hasStateError = await MainActor.run {
            km.registrationLog.contains { $0.stage == .STATE && $0.level == .error }
        }
        #expect(hasStateError)
    }
}
