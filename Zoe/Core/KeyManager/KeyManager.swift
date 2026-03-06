import Combine
import CryptoKit
import Darwin
import Foundation
import OSLog
import Security
import UIKit

// MARK: - RegistrationNetworkOutcome

enum RegistrationNetworkOutcome: Sendable, Equatable {
    case registered
    case kidConflict
    case challengeExpired
    case definitiveFailure(code: String)
    case transientFailure
    case revoked
    case revocationCheckPassed
}

// MARK: - KeyManagerNetworking Protocol

protocol KeyManagerNetworking: Sendable {
    func challenge(kid: String?) async throws -> ChallengeResponse
    func registerKey(_ request: RegisterRequest) async throws -> RegisterResponse
}

extension APIClient: KeyManagerNetworking {}

// MARK: - KeyManager

@MainActor
final class KeyManager: ObservableObject {
    @Published var state: RegistrationState = .unknown
    @Published private(set) var kid: String?

    var isSigningAvailable: Bool { state == .registered }

    private let attestationService: any AttestationService
    private let networking: any KeyManagerNetworking
    private let seKeyFactory: () throws -> (dataRep: Data, publicKey: P256.Signing.PublicKey)
    private var seKey: (dataRep: Data, publicKey: P256.Signing.PublicKey)?
    private let initialStateOverride: RegistrationState?

    private let logger = Logger(subsystem: "com.zoe.app", category: "KeyManager")

    // Keychain constants
    private let keychainKeyTag: String
    private let keychainStateKey: String
    private let keychainService: String

    init(
        attestationService: any AttestationService = LiveAttestationService(),
        networking: any KeyManagerNetworking = APIClient.shared,
        seKeyFactory: (() throws -> (dataRep: Data, publicKey: P256.Signing.PublicKey))? = nil,
        initialStateOverride: RegistrationState? = nil,
        keychainNamespace: String = "com.zoe.app"
    ) {
        self.attestationService = attestationService
        self.networking = networking
        self.initialStateOverride = initialStateOverride
        self.keychainService   = keychainNamespace
        self.keychainKeyTag    = keychainNamespace + ".sekey"
        self.keychainStateKey  = keychainNamespace + ".keystatekey"
        self.seKeyFactory = seKeyFactory ?? {
            let key = try SecureEnclave.P256.Signing.PrivateKey()
            return (key.dataRepresentation, key.publicKey)
        }
    }

    // MARK: - Public API

    func initialise() async {
        // a) Load persisted state
        let persisted = initialStateOverride ?? loadPersistedState()

        // b) If .failedPermanent: set state, return
        if persisted == .failedPermanent {
            state = .failedPermanent
            logger.info("KeyManager: loaded .failedPermanent from Keychain — skipping registration")
            return
        }

        // c) Load or generate SE key
        let keyPair: (dataRep: Data, publicKey: P256.Signing.PublicKey)
        do {
            keyPair = try generateOrLoadSEKey()
        } catch {
            logger.error("KeyManager: SE key unavailable — transitioning to .failedPermanent")
            state = .failedPermanent
            saveRegistrationState(.failedPermanent)
            return
        }
        seKey = keyPair

        // d) Derive and store kid
        kid = deriveKid(from: keyPair.publicKey)

        // e) If .registered: check revocation via challenge(kid:)
        if persisted == .registered {
            state = .registered
            logger.info("KeyManager: .registered loaded from Keychain — checking revocation")
            let revocCheck = await Self.checkRevocation(networking: networking, kid: kid)
            if revocCheck == .revoked {
                logger.error("KeyManager: device_revoked on revocation check → .failedPermanent")
                state = .failedPermanent
                saveRegistrationState(.failedPermanent)
            }
            // Other outcomes (pass or network error) → fail open, stay .registered
            return
        }

        // f) Start registration flow
        await performRegistration(keyPair: keyPair, attemptNumber: 1)
    }

    func sign(data: Data) async throws -> P256.Signing.ECDSASignature {
        let kp: (dataRep: Data, publicKey: P256.Signing.PublicKey)
        if let existing = seKey {
            kp = existing
        } else {
            kp = try generateOrLoadSEKey()
            seKey = kp
        }
        let sePrivKey = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: kp.dataRep)
        return try sePrivKey.signature(for: data)
    }

    // MARK: - SE Key Helpers

    private func generateOrLoadSEKey() throws -> (dataRep: Data, publicKey: P256.Signing.PublicKey) {
        // Check Keychain first
        let readQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainKeyTag,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(readQuery as CFDictionary, &result)
        if status == errSecSuccess, let storedData = result as? Data {
            if let key = try? SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: storedData) {
                return (key.dataRepresentation, key.publicKey)
            }
            // Stored data is not a valid SE key (e.g., simulator software key or corrupted).
            // Delete the stale entry and fall through to regenerate.
            let deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: keychainKeyTag
            ]
            SecItemDelete(deleteQuery as CFDictionary)
        }

        // Not found — generate new key
        let (dataRep, publicKey) = try seKeyFactory()
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainKeyTag,
            kSecValueData as String: dataRep,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
        return (dataRep, publicKey)
    }

    internal func deriveKid(from publicKey: P256.Signing.PublicKey) -> String {
        let derBytes = publicKey.derRepresentation
        let hash = SHA256.hash(data: derBytes)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func exportPublicKeyAsPEM(_ publicKey: P256.Signing.PublicKey) -> String {
        let derBytes = publicKey.derRepresentation
        let b64 = derBytes.base64EncodedString()
        return "-----BEGIN PUBLIC KEY-----\n\(b64)\n-----END PUBLIC KEY-----"
    }

    // MARK: - Keychain State Persistence

    private func saveRegistrationState(_ regState: RegistrationState) {
        let stateString: String
        switch regState {
        case .registered: stateString = "registered"
        case .failedPermanent: stateString = "failedPermanent"
        default: stateString = "unknown"
        }
        guard let stateData = stateString.data(using: .utf8) else { return }

        let updateQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainStateKey
        ]
        let updateAttribs: [String: Any] = [kSecValueData as String: stateData]
        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttribs as CFDictionary)

        if updateStatus == errSecItemNotFound {
            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: keychainStateKey,
                kSecValueData as String: stateData,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    private func loadPersistedState() -> RegistrationState {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainStateKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return .unknown
        }
        switch string {
        case "registered": return .registered
        case "failedPermanent": return .failedPermanent
        default: return .unknown
        }
    }

    // MARK: - Registration Flow

    private func performRegistration(keyPair: (dataRep: Data, publicKey: P256.Signing.PublicKey), attemptNumber: Int) async {
        state = .registering
        logger.info("KeyManager: → .registering (attempt \(attemptNumber))")

        guard attestationService.isSupported else {
            logger.error("KeyManager: App Attest not supported → .failedPermanent")
            state = .failedPermanent
            saveRegistrationState(.failedPermanent)
            return
        }

        let kid = deriveKid(from: keyPair.publicKey)
        let pem = exportPublicKeyAsPEM(keyPair.publicKey)
        let model = normalizedDeviceModel()
        let ios = await UIDevice.current.systemVersion
        let app = appVersion()

        let outcome = await Self.runRegistrationNetwork(
            attestationService: attestationService,
            networking: networking,
            kid: kid, pem: pem, deviceModel: model, iosVersion: ios, appVersion: app
        )

        switch outcome {
        case .registered:
            logger.info("KeyManager: registration success → .registered")
            state = .registered
            saveRegistrationState(.registered)
        case .kidConflict:
            logger.info("KeyManager: kid_conflict (idempotent success) → .registered")
            state = .registered
            saveRegistrationState(.registered)
        case .challengeExpired:
            await handleChallengeExpired(keyPair: keyPair, kid: kid, pem: pem, deviceModel: model, iosVersion: ios, appVersion: app, attemptNumber: attemptNumber)
        case .definitiveFailure(let code):
            logger.error("KeyManager: definitive failure (\(code)) → .failedPermanent")
            state = .failedPermanent
            saveRegistrationState(.failedPermanent)
        case .transientFailure, .revocationCheckPassed, .revoked:
            await handleTransientFailure(keyPair: keyPair, attemptNumber: attemptNumber)
        }
    }

    nonisolated private static func runRegistrationNetwork(
        attestationService: any AttestationService,
        networking: any KeyManagerNetworking,
        kid: String, pem: String,
        deviceModel: String, iosVersion: String, appVersion: String
    ) async -> RegistrationNetworkOutcome {
        do {
            let attKeyID = try await attestationService.generateKeyID()
            let challengeResp = try await networking.challenge(kid: nil)
            let challengeData = Data(challengeResp.challenge.utf8)
            let clientDataHash = Data(SHA256.hash(data: challengeData))
            let attestObj = try await attestationService.attestKey(keyID: attKeyID, clientDataHash: clientDataHash)
            let registerReq = RegisterRequest(
                kid: kid, publicKeyPem: pem,
                attestationObject: attestObj.base64EncodedString(),
                keyIdFromAttest: attKeyID,
                deviceModel: deviceModel, iosVersion: iosVersion, appVersion: appVersion,
                challenge: challengeResp.challenge
            )
            _ = try await networking.registerKey(registerReq)
            return .registered
        } catch let apiError as APIError {
            switch apiError {
            case .definitiveFailure(let code):
                switch code {
                case "kid_conflict": return .kidConflict
                case "challenge_expired": return .challengeExpired
                default: return .definitiveFailure(code: code)
                }
            default:
                return .transientFailure
            }
        } catch {
            return .transientFailure
        }
    }

    private func handleChallengeExpired(
        keyPair: (dataRep: Data, publicKey: P256.Signing.PublicKey),
        kid: String, pem: String,
        deviceModel: String, iosVersion: String, appVersion: String,
        attemptNumber: Int
    ) async {
        let outcome = await Self.runRegistrationNetwork(
            attestationService: attestationService,
            networking: networking,
            kid: kid, pem: pem,
            deviceModel: deviceModel, iosVersion: iosVersion, appVersion: appVersion
        )
        switch outcome {
        case .registered, .kidConflict:
            logger.info("KeyManager: challenge_expired retry success → .registered")
            state = .registered
            saveRegistrationState(.registered)
        case .definitiveFailure(let code):
            logger.error("KeyManager: definitive failure after challenge_expired (\(code)) → .failedPermanent")
            state = .failedPermanent
            saveRegistrationState(.failedPermanent)
        case .challengeExpired, .transientFailure:
            await handleTransientFailure(keyPair: keyPair, attemptNumber: attemptNumber)
        case .revocationCheckPassed, .revoked:
            await handleTransientFailure(keyPair: keyPair, attemptNumber: attemptNumber)
        }
    }

    nonisolated private static func checkRevocation(
        networking: any KeyManagerNetworking,
        kid: String?
    ) async -> RegistrationNetworkOutcome {
        do {
            _ = try await networking.challenge(kid: kid)
            return .revocationCheckPassed
        } catch let apiError as APIError {
            if case .definitiveFailure(let code) = apiError, code == "device_revoked" {
                return .revoked
            }
            return .revocationCheckPassed // fail open
        } catch {
            return .revocationCheckPassed // fail open
        }
    }


    private func handleTransientFailure(keyPair: (dataRep: Data, publicKey: P256.Signing.PublicKey), attemptNumber: Int) async {
        if attemptNumber >= 3 {
            logger.error("KeyManager: max retry attempts reached → .failedPermanent")
            state = .failedPermanent
            saveRegistrationState(.failedPermanent)
            return
        }
        state = .retrying
        logger.info("KeyManager: → .retrying (attempt \(attemptNumber))")
        let delayNs = UInt64(pow(2.0, Double(attemptNumber - 1)) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: delayNs)
        await performRegistration(keyPair: keyPair, attemptNumber: attemptNumber + 1)
    }

    // MARK: - Device Info

    private func normalizedDeviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafeBytes(of: &systemInfo.machine) { ptr in
            let bytes = ptr.bindMemory(to: CChar.self)
            return String(cString: bytes.baseAddress!)
        }
    }

    private func appVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }
}
