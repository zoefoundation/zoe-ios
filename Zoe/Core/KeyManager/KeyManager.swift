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
extension APIClient: SigningAPIClient {}

// MARK: - KeyManager

@MainActor
final class KeyManager: ObservableObject {
    @Published var state: RegistrationState = .unknown
    @Published private(set) var kid: String?
    @Published private(set) var lastError: String?
    @Published private(set) var registrationLog: [RegistrationLogEntry] = []

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
        // a) Detect fresh install: UserDefaults is wiped on delete; Keychain is not.
        //    If the install sentinel is absent, purge any stale Keychain entries so a
        //    previous .failedPermanent can't block registration after reinstall.
        let installSentinelKey = keychainService + ".installed"
        log(.INIT, "Starting registration sequence")
        if initialStateOverride == nil && UserDefaults.standard.string(forKey: installSentinelKey) == nil {
            log(.INIT, "Fresh install detected — purging stale Keychain state", level: .warning)
            logger.info("KeyManager: fresh install detected — clearing stale Keychain state")
            purgeKeychainState()
            UserDefaults.standard.set("1", forKey: installSentinelKey)
        }

        // b) Load persisted state
        let persisted = initialStateOverride ?? loadPersistedState()
        log(.STATE, "Persisted state: \(persisted)")

        // c) If .failedPermanent: set state, return
        if persisted == .failedPermanent {
            log(.STATE, "Loaded .failedPermanent — registration permanently blocked", level: .error)
            state = .failedPermanent
            logger.info("KeyManager: loaded .failedPermanent — skipping registration")
            return
        }

        // d) Load or generate SE key
        let keyPair: (dataRep: Data, publicKey: P256.Signing.PublicKey)
        do {
            let existingData: Data? = {
                let q: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: keychainService,
                    kSecAttrAccount as String: keychainKeyTag,
                    kSecReturnData as String: true,
                    kSecMatchLimit as String: kSecMatchLimitOne
                ]
                var r: AnyObject?
                return SecItemCopyMatching(q as CFDictionary, &r) == errSecSuccess ? r as? Data : nil
            }()
            if existingData != nil {
                log(.KEY, "Loading SE key from Keychain...")
            } else {
                log(.KEY, "No SE key found — generating new Secure Enclave keypair...")
            }
            keyPair = try generateOrLoadSEKey()
            let kidPrefix = deriveKid(from: keyPair.publicKey).prefix(12)
            if existingData != nil {
                log(.KEY, "SE key loaded — kid: \(kidPrefix)...", level: .success)
            } else {
                log(.KEY, "New SE keypair generated — kid: \(kidPrefix)...", level: .success)
            }
        } catch {
            log(.KEY, "SE key unavailable — hardware error → failedPermanent", level: .error)
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
            let kidPrefix = kid?.prefix(12) ?? "?"
            log(.REVOC, "Already registered — checking revocation via /v1/challenge (kid: \(kidPrefix)...)")
            logger.info("KeyManager: .registered loaded from Keychain — checking revocation")
            let revocCheck = await Self.checkRevocation(networking: networking, kid: kid)
            if revocCheck == .revoked {
                log(.REVOC, "Revocation check: device_revoked → failedPermanent", level: .error)
                logger.error("KeyManager: device_revoked on revocation check → .failedPermanent")
                lastError = "device_revoked"
                state = .failedPermanent
                saveRegistrationState(.failedPermanent)
            } else {
                log(.REVOC, "Revocation check passed — device remains active", level: .success)
            }
            // Other outcomes (pass or network error) → fail open, stay .registered
            return
        }

        // f) Start registration flow
        await performRegistration(keyPair: keyPair, attemptNumber: 1)
    }

    /// Clears ALL persisted registration state and re-runs initialise() from scratch.
    ///
    /// What gets cleared:
    /// - Keychain: SE key data representation handle
    /// - Keychain: registered/failedPermanent state
    /// - UserDefaults: failedPermanent flag + install sentinel
    /// - In-memory: seKey, kid, lastError, registrationLog
    ///
    /// Result: a brand-new SE keypair is generated on next initialise() → new kid.
    /// The previous SE private key remains permanently inaccessible in hardware.
    public func resetRegistration() async {
        purgeKeychainState()
        UserDefaults.standard.removeObject(forKey: keychainService + ".installed")
        state = .unknown
        lastError = nil
        kid = nil
        seKey = nil
        registrationLog = []
        await initialise()
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

    // MARK: - Logging Helper

    private func log(
        _ stage: RegistrationLogEntry.Stage,
        _ message: String,
        level: RegistrationLogEntry.Level = .info
    ) {
        let entry = RegistrationLogEntry(stage: stage, message: message, level: level)
        registrationLog.append(entry)
        switch level {
        case .info, .success: logger.info("\(entry.formatted, privacy: .public)")
        case .warning:        logger.warning("\(entry.formatted, privacy: .public)")
        case .error:          logger.error("\(entry.formatted, privacy: .public)")
        }
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

    private func purgeKeychainState() {
        for account in [keychainStateKey, keychainKeyTag] {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: account
            ]
            SecItemDelete(query as CFDictionary)
        }
        // Also clear the UserDefaults-backed failedPermanent flag
        UserDefaults.standard.removeObject(forKey: udFailedPermanentKey)
    }

    // MARK: - State persistence keys
    // .registered   → Keychain (cryptographic identity, must survive app re-launch)
    // .failedPermanent → UserDefaults (soft policy flag; wiped on app delete, resettable)

    private var udFailedPermanentKey: String { keychainService + ".failedPermanent" }

    private func saveRegistrationState(_ regState: RegistrationState) {
        switch regState {
        case .registered:
            // Persist to Keychain
            guard let data = "registered".data(using: .utf8) else { return }
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: keychainStateKey
            ]
            if SecItemUpdate(updateQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecItemNotFound {
                let addQuery: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: keychainService,
                    kSecAttrAccount as String: keychainStateKey,
                    kSecValueData as String: data,
                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                ]
                SecItemAdd(addQuery as CFDictionary, nil)
            }
        case .failedPermanent:
            // Persist to UserDefaults — clearable without needing app reinstall
            UserDefaults.standard.set(true, forKey: udFailedPermanentKey)
        default:
            break
        }
    }

    private func loadPersistedState() -> RegistrationState {
        // Check UserDefaults for failedPermanent first (fast path, clears on app delete)
        if UserDefaults.standard.bool(forKey: udFailedPermanentKey) {
            return .failedPermanent
        }
        // Check Keychain for registered state
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
              let string = String(data: data, encoding: .utf8),
              string == "registered" else {
            return .unknown
        }
        return .registered
    }

    // MARK: - Registration Flow

    private func performRegistration(keyPair: (dataRep: Data, publicKey: P256.Signing.PublicKey), attemptNumber: Int) async {
        state = .registering
        log(.REGISTER, "Sending registration — POST /v1/keys/register (attempt \(attemptNumber)/3)...")
        logger.info("KeyManager: → .registering (attempt \(attemptNumber))")

        guard attestationService.isSupported else {
            log(.ATTEST, "App Attest not supported on this device → failedPermanent", level: .error)
            logger.error("KeyManager: App Attest not supported → .failedPermanent")
            state = .failedPermanent
            saveRegistrationState(.failedPermanent)
            return
        }
        log(.ATTEST, "Checking App Attest availability...")

        let kid = deriveKid(from: keyPair.publicKey)
        let pem = exportPublicKeyAsPEM(keyPair.publicKey)
        let model = normalizedDeviceModel()
        let ios = UIDevice.current.systemVersion
        let app = appVersion()

        let outcome = await Self.runRegistrationNetwork(
            attestationService: attestationService,
            networking: networking,
            kid: kid, pem: pem, deviceModel: model, iosVersion: ios, appVersion: app
        )

        switch outcome {
        case .registered:
            log(.COMPLETE, "Registration complete — signing available (kid: \(kid.prefix(12))...)", level: .success)
            logger.info("KeyManager: registration success → .registered")
            state = .registered
            saveRegistrationState(.registered)
        case .kidConflict:
            log(.COMPLETE, "kid_conflict (idempotent success) — signing available", level: .success)
            logger.info("KeyManager: kid_conflict (idempotent success) → .registered")
            state = .registered
            saveRegistrationState(.registered)
        case .challengeExpired:
            log(.CHALLENGE, "Challenge expired — retrying with fresh challenge", level: .warning)
            await handleChallengeExpired(keyPair: keyPair, kid: kid, pem: pem, deviceModel: model, iosVersion: ios, appVersion: app, attemptNumber: attemptNumber)
        case .definitiveFailure(let code):
            log(.COMPLETE, "Registration failed permanently — error: \(code)", level: .error)
            logger.error("KeyManager: definitive failure (\(code)) → .failedPermanent")
            lastError = code
            state = .failedPermanent
            saveRegistrationState(.failedPermanent)
        case .transientFailure, .revocationCheckPassed, .revoked:
            log(.REGISTER, "Transient failure on attempt \(attemptNumber)", level: .warning)
            await handleTransientFailure(keyPair: keyPair, attemptNumber: attemptNumber)
        }
    }

    nonisolated private static func runRegistrationNetwork(
        attestationService: any AttestationService,
        networking: any KeyManagerNetworking,
        kid: String, pem: String,
        deviceModel: String, iosVersion: String, appVersion: String
    ) async -> RegistrationNetworkOutcome {
        let logger = Logger(subsystem: "com.zoe.app", category: "KeyManager")
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
            case .pinningFailed:
                logger.error("KeyManager: registration failed — certificate pinning rejected server cert")
                return .transientFailure
            case .networkError(let underlying):
                logger.error("KeyManager: registration failed — network error: \(underlying.localizedDescription)")
                return .transientFailure
            case .serverError:
                logger.error("KeyManager: registration failed — server error (5xx)")
                return .transientFailure
            case .unexpectedResponse(let statusCode):
                logger.error("KeyManager: registration failed — unexpected HTTP \(statusCode)")
                return .transientFailure
            case .decodingFailed(let underlying):
                logger.error("KeyManager: registration failed — decoding error: \(underlying.localizedDescription)")
                return .transientFailure
            }
        } catch {
            logger.error("KeyManager: registration failed — unexpected error: \(error.localizedDescription) | \(String(describing: error))")
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
            lastError = code
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
            // Network/transient exhaustion: fail this session only — do NOT persist to Keychain
            // so the next app launch will attempt registration again.
            log(.COMPLETE, "Session failed (attempt budget exhausted) — will retry on next launch", level: .warning)
            logger.error("KeyManager: max retry attempts reached — session failed, will retry on next launch")
            state = .failedPermanent
            return
        }
        state = .retrying
        let delay = Int(pow(2.0, Double(attemptNumber - 1)))
        log(.RETRY, "Scheduling retry #\(attemptNumber + 1) in \(delay)s (exponential backoff)...", level: .warning)
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
