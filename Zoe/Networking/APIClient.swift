import Foundation

// MARK: - Proof Types

struct ProofBundleRequest: Encodable {
    let payload: [String: String]   // zoe.media.v1 canonical fields dict
    let signatureB64: String        // ECDSA P-256 DER representation, base64-encoded
    let algorithm: String           // "ES256"
}

struct ProofUploadResponse: Decodable {
    let proofId: String             // Server-generated UUID
}

// MARK: - SigningAPIClient Protocol

protocol SigningAPIClient: Sendable {
    func uploadProof(_ bundle: ProofBundleRequest) async throws -> ProofUploadResponse
}

// MARK: - CertificatePinningDelegate

final class CertificatePinningDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let pinnedCertificateData: Data

    init(pinnedCertificateData: Data) {
        self.pinnedCertificateData = pinnedCertificateData
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        let chain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate] ?? []
        if matchesPinnedCertificate(chain: chain, pinnedData: pinnedCertificateData) {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    // internal (not private) — directly testable from ZoeTests
    func matchesPinnedCertificate(chain: [SecCertificate], pinnedData: Data) -> Bool {
        chain.contains { SecCertificateCopyData($0) as Data == pinnedData }
    }
}

// MARK: - APIClient

final class APIClient: Sendable {
    private let session: URLSession
    private let baseURL: URL

    static let shared: APIClient = APIClient(
        baseURL: APIEndpoints.baseURL,
        pinnedCertData: APIClient.loadPinnedCertData()
    )

    init(baseURL: URL = APIEndpoints.baseURL, pinnedCertData: Data) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        let delegate = CertificatePinningDelegate(pinnedCertificateData: pinnedCertData)
        self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    static func loadPinnedCertData() -> Data {
        guard let url = Bundle.main.url(forResource: "isrg_root_x1", withExtension: "der"),
              let data = try? Data(contentsOf: url) else {
            fatalError("isrg_root_x1.der not found in bundle — add to target membership in Xcode")
        }
        return data
    }

    private func makeJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private func makeJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }

    // MARK: - challenge()

    func challenge(kid: String? = nil) async throws -> ChallengeResponse {
        var request = URLRequest(url: endpointURL(for: APIEndpoints.challengePath))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let kid = kid {
            struct ChallengeBody: Encodable { let kid: String }
            request.httpBody = try makeJSONEncoder().encode(ChallengeBody(kid: kid))
        } else {
            request.httpBody = Data("{}".utf8)
        }
        let (data, response) = try await performRequest(request)
        return try decode(ChallengeResponse.self, from: data, response: response)
    }

    // MARK: - registerKey(_:)

    func registerKey(_ registerRequest: RegisterRequest) async throws -> RegisterResponse {
        var request = URLRequest(url: endpointURL(for: APIEndpoints.registerPath))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try makeJSONEncoder().encode(registerRequest)

        let (data, response) = try await performRequest(request)
        return try decode(RegisterResponse.self, from: data, response: response)
    }

    // MARK: - uploadProof(_:)

    func uploadProof(_ bundle: ProofBundleRequest) async throws -> ProofUploadResponse {
        var request = URLRequest(url: endpointURL(for: APIEndpoints.proofsPath))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try makeJSONEncoder().encode(bundle)
        let (data, response) = try await performRequest(request)
        return try decode(ProofUploadResponse.self, from: data, response: response)
    }

    // MARK: - Helpers

    private func performRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw Self.classifyTransportError(error)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.unexpectedResponse(statusCode: -1)
        }
        return (data, httpResponse)
    }

    nonisolated static func classifyTransportError(_ error: Error) -> APIError {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .secureConnectionFailed,
                 .serverCertificateHasBadDate,
                 .serverCertificateUntrusted,
                 .serverCertificateHasUnknownRoot,
                 .serverCertificateNotYetValid,
                 .clientCertificateRejected,
                 .clientCertificateRequired:
                return .pinningFailed
            default:
                return .networkError(urlError)
            }
        }
        return .networkError(error)
    }

    func endpointURL(for path: String) -> URL {
        Self.makeEndpointURL(baseURL: baseURL, path: path)
    }

    nonisolated static func makeEndpointURL(baseURL: URL, path: String) -> URL {
        let normalizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return baseURL.appendingPathComponent(normalizedPath)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data, response: HTTPURLResponse) throws -> T {
        let statusCode = response.statusCode
        if (200..<300).contains(statusCode) {
            do {
                return try makeJSONDecoder().decode(T.self, from: data)
            } catch {
                throw APIError.decodingFailed(error)
            }
        }

        // Try to parse error envelope
        let errorCode: String?
        if let envelope = try? makeJSONDecoder().decode(APIErrorEnvelope.self, from: data) {
            errorCode = envelope.error.code
        } else {
            errorCode = nil
        }

        if (500..<600).contains(statusCode) || errorCode == "server_error" {
            throw APIError.serverError
        }

        if let code = errorCode {
            switch code {
            case "attest_invalid", "device_unauthorized", "device_revoked",
                 "challenge_expired", "kid_conflict":
                throw APIError.definitiveFailure(code: code)
            default:
                throw APIError.definitiveFailure(code: code)
            }
        }

        throw APIError.unexpectedResponse(statusCode: statusCode)
    }
}
