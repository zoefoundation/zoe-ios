import Combine

@MainActor
final class AppState: ObservableObject {
    let keyManager = KeyManager()

    init() {
        Task {
            await keyManager.initialise()
        }
    }
}
