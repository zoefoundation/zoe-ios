import Combine
import SwiftData

@MainActor
final class VerifyViewModel: ObservableObject {
    private let store: LibraryStore
    private let verificationService: VerificationService

    init(store: LibraryStore, verificationService: VerificationService = VerificationService(apiClient: APIClient.shared)) {
        self.store = store
        self.verificationService = verificationService
    }

    @discardableResult
    func verify(item: LibraryItem) -> Task<Void, Never> {
        item.verificationState = VerificationState.verifying.rawValue
        try? store.modelContext.save()

        let fileURL = item.resolvedMediaURL
        return Task {
            let result = await verificationService.verify(fileURL: fileURL)
            await MainActor.run {
                item.verificationState = result.state.rawValue
                item.verdictSigningTime = result.signingTime
                item.kid = result.kid
                try? store.modelContext.save()
            }
        }
    }
}
