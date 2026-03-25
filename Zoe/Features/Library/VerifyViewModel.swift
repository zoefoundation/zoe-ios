import Combine
import SwiftData

@MainActor
final class VerifyViewModel: ObservableObject {
    private let store: LibraryStore
    private let verificationService: VerificationService

    init(store: LibraryStore, verificationService: VerificationService = VerificationService()) {
        self.store = store
        self.verificationService = verificationService
    }

    func verify(item: LibraryItem) {
        item.verificationState = VerificationState.verifying.rawValue
        try? store.modelContext.save()

        let fileURL = item.resolvedMediaURL
        Task {
            let verdict = await verificationService.verify(fileURL: fileURL)
            await MainActor.run {
                item.verificationState = verdict.rawValue
                try? store.modelContext.save()
            }
        }
    }
}
