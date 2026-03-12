enum VerificationState: String, CaseIterable {
    case signed
    case unsigned
    case authentic
    case tampered
    case notVerified
    case verifying
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
        }
    }
}
