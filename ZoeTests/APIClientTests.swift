import Testing
import Foundation
@testable import zoe

final class APIClientTests {

    // MARK: - 7.2 Pinning: matching certificate data is accepted

    @Test("Pinning: matching certificate data is accepted")
    func testPinningAcceptsMatchingCert() throws {
        let pinnedData = try loadBundledCert()
        let cert = try #require(SecCertificateCreateWithData(nil, pinnedData as CFData))
        let delegate = CertificatePinningDelegate(pinnedCertificateData: pinnedData)
        #expect(delegate.matchesPinnedCertificate(chain: [cert], pinnedData: pinnedData))
    }

    // MARK: - 7.3 Pinning: mismatched certificate data is rejected

    @Test("Pinning: mismatched certificate data is rejected")
    func testPinningRejectsMismatchedCert() throws {
        let pinnedData = try loadBundledCert()
        let cert = try #require(SecCertificateCreateWithData(nil, pinnedData as CFData))
        let wrongData = Data(repeating: 0xAB, count: pinnedData.count)
        let delegate = CertificatePinningDelegate(pinnedCertificateData: pinnedData)
        #expect(!delegate.matchesPinnedCertificate(chain: [cert], pinnedData: wrongData))
    }

    // MARK: - 7.4 APIError: transient classification

    @Test("APIError: transient errors are classified correctly")
    func testAPIErrorTransientClassification() {
        #expect(APIError.serverError.isTransient)
        #expect(APIError.networkError(URLError(.timedOut)).isTransient)
        #expect(!APIError.definitiveFailure(code: "attest_invalid").isTransient)
        #expect(!APIError.definitiveFailure(code: "device_revoked").isTransient)
        #expect(!APIError.pinningFailed.isTransient)
    }

    @Test("Transport error mapping: certificate failures map to pinningFailed")
    func testTransportErrorMappingForTLSFailure() {
        let mapped = APIClient.classifyTransportError(URLError(.secureConnectionFailed))
        if case .pinningFailed = mapped {} else {
            Issue.record("Expected .pinningFailed, got \(mapped)")
        }
    }

    // MARK: - 7.5 ChallengeResponse: decodes snake_case from JSON

    @Test("ChallengeResponse: decodes snake_case from JSON")
    func testChallengeResponseDecoding() throws {
        let json = #"{"challenge":"tok123","expires_at":"2026-03-05T12:00:00Z"}"#
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(ChallengeResponse.self, from: Data(json.utf8))
        #expect(response.challenge == "tok123")
        #expect(response.expiresAt == "2026-03-05T12:00:00Z")
    }

    // MARK: - 7.6 RegisterRequest: encodes to snake_case JSON

    @Test("RegisterRequest: encodes to snake_case JSON")
    func testRegisterRequestEncoding() throws {
        let req = RegisterRequest(
            kid: "abc",
            publicKeyPem: "pem",
            attestationObject: "att",
            keyIdFromAttest: "kid",
            deviceModel: "iPhone15,2",
            iosVersion: "26.0",
            appVersion: "1.0",
            challenge: "tok"
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(req)
        let json = String(data: data, encoding: .utf8)!
        #expect(json.contains("\"public_key_pem\""))
        #expect(json.contains("\"key_id_from_attest\""))
    }

    // MARK: - Private Helpers

    private func loadBundledCert() throws -> Data {
        let url = try #require(
            Bundle(for: APIClientTests.self).url(forResource: "isrg_root_x1", withExtension: "der")
        )
        return try Data(contentsOf: url)
    }
}
