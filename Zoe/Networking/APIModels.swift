import Foundation

// MARK: - Response Types

struct ChallengeResponse: Sendable {
    nonisolated let challenge: String
    nonisolated let expiresAt: String
}

nonisolated extension ChallengeResponse: Codable {}

struct RegisterRequest: Sendable {
    let kid: String
    let publicKeyPem: String
    let attestationObject: String
    let keyIdFromAttest: String
    let deviceModel: String
    let iosVersion: String
    let appVersion: String
    let challenge: String
}

nonisolated extension RegisterRequest: Codable {}

struct RegisterResponse: Sendable {
    let status: String
}

nonisolated extension RegisterResponse: Codable {}

// MARK: - Error Envelope

struct APIErrorDetail: Codable {
    let code: String
    let message: String
}

struct APIErrorEnvelope: Codable {
    let error: APIErrorDetail
}

// MARK: - Verification Types

struct ProofLookupResponse: Decodable, Sendable {
    let proofId: String
    let kid: String
    let payload: [String: String]
    let signatureB64: String
    let algorithm: String
    let createdAt: String
}

struct VerifyRequest: Encodable, Sendable {
    let proofId: String
    let contentHashHex: String
}

struct VerifyResponse: Decodable, Sendable {
    let verdict: String
    let signingTime: String?
    let kid: String?
}

// MARK: - VerifyAPIClient Protocol

protocol VerifyAPIClient: Sendable {
    func lookupProof(assetSHA256: String) async throws -> ProofLookupResponse?
    func postVerify(_ request: VerifyRequest) async throws -> VerifyResponse
}

extension APIClient: VerifyAPIClient {}

// MARK: - APIError

enum APIError: Error {
    case pinningFailed
    case networkError(Error)            // transient — URLError
    case serverError                    // transient — HTTP 5xx or code "server_error"
    case definitiveFailure(code: String) // definitive — attest_invalid / device_unauthorized / device_revoked
    case unexpectedResponse(statusCode: Int)
    case decodingFailed(Error)

    var isTransient: Bool {
        switch self {
        case .networkError, .serverError:
            return true
        case .pinningFailed, .definitiveFailure, .unexpectedResponse, .decodingFailed:
            return false
        }
    }
}
