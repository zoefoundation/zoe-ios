import Foundation

// MARK: - Response Types

struct ChallengeResponse: Codable {
    let challenge: String
    let expiresAt: String
}

struct RegisterRequest: Codable {
    let kid: String
    let publicKeyPem: String
    let attestationObject: String
    let keyIdFromAttest: String
    let deviceModel: String
    let iosVersion: String
    let appVersion: String
    let challenge: String
}

struct RegisterResponse: Codable {
    let status: String
}

// MARK: - Error Envelope

struct APIErrorDetail: Codable {
    let code: String
    let message: String
}

struct APIErrorEnvelope: Codable {
    let error: APIErrorDetail
}

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
