enum RegistrationState: Sendable {
    case unknown
    case registering
    case registered
    case retrying
    case failedPermanent
}

nonisolated extension RegistrationState: Equatable {}
