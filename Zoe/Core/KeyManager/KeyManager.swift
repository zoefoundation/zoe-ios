import Combine

@MainActor
final class KeyManager: ObservableObject {
    @Published var state: RegistrationState = .unknown
}
