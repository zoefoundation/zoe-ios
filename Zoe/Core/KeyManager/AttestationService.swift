import DeviceCheck

// MARK: - AttestationService Protocol

protocol AttestationService: Sendable {
    var isSupported: Bool { get }
    func generateKeyID() async throws -> String
    func attestKey(keyID: String, clientDataHash: Data) async throws -> Data
}

// MARK: - LiveAttestationService

final class LiveAttestationService: AttestationService {
    var isSupported: Bool { DCAppAttestService.shared.isSupported }

    func generateKeyID() async throws -> String {
        try await DCAppAttestService.shared.generateKey()
    }

    func attestKey(keyID: String, clientDataHash: Data) async throws -> Data {
        try await DCAppAttestService.shared.attestKey(keyID, clientDataHash: clientDataHash)
    }
}
