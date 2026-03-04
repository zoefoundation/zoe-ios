enum VerificationState: String, CaseIterable {
    case signed
    case unsigned
    case authentic
    case tampered
    case notVerified
    case verifying
}
