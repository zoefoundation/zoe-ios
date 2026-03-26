import Foundation
import CryptoKit

// MARK: - VerificationResult

struct VerificationResult: Sendable {
    let state: VerificationState
    let signingTime: Date?
    let kid: String?
}

// MARK: - VerificationService

actor VerificationService {
    private let apiClient: any VerifyAPIClient

    init(apiClient: any VerifyAPIClient) {
        self.apiClient = apiClient
    }

    func verify(fileURL: URL) async -> VerificationResult {
        do {
            let data = try Data(contentsOf: fileURL)
            let hash = SHA256.hash(data: data)
            let hexString = hash.map { String(format: "%02x", $0) }.joined()

            guard let proof = try await apiClient.lookupProof(assetSHA256: hexString) else {
                return VerificationResult(state: .notVerified, signingTime: nil, kid: nil)
            }

            let response = try await apiClient.postVerify(
                VerifyRequest(proofId: proof.proofId, contentHashHex: hexString)
            )

            let signingTime: Date?
            if let timeString = response.signingTime {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime]
                signingTime = formatter.date(from: timeString)
            } else {
                signingTime = nil
            }

            switch Verdict(rawValue: response.verdict) {
            case .authentic:
                return VerificationResult(state: .authentic, signingTime: signingTime, kid: response.kid)
            case .tampered:
                return VerificationResult(state: .tampered, signingTime: signingTime, kid: response.kid)
            case .notVerified, .none:
                return VerificationResult(state: .notVerified, signingTime: nil, kid: nil)
            }
        } catch {
            return VerificationResult(state: .notVerified, signingTime: nil, kid: nil)
        }
    }
}
