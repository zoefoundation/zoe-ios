enum VerificationState: String, CaseIterable {
    case signed
    case unsigned
    case authentic
    case tampered
    case notVerified
    case verifying
    case pending    // signed locally, proof upload to server pending (e.g. captured offline)
}

extension VerificationState {
    var accessibilityLabel: String {
        switch self {
        case .signed:      return "Signed"
        case .unsigned:    return "Unsigned"
        case .authentic:   return "Authentic"
        case .tampered:    return "Tampered — content was modified after signing"
        case .notVerified: return "Not Verified — no provenance signature found"
        case .verifying:   return "verifying provenance"
        case .pending:     return "Pending — upload in progress"
        }
    }

    var pillShortLabel: String {
        switch self {
        case .signed:      return "Signed"
        case .unsigned:    return "Unsigned"
        case .authentic:   return "Authentic"
        case .tampered:    return "Tampered"
        case .notVerified: return "Not Verified"
        case .verifying:   return "Verifying"
        case .pending:     return "Pending Upload"
        }
    }
}
