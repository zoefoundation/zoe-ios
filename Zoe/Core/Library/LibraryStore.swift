import Foundation
import SwiftData

final class LibraryStore {
    let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    @discardableResult
    func addItem(
        mediaURL: URL,
        mediaType: String,
        source: String,
        verificationState: VerificationState,
        capturedAt: Date = Date()
    ) -> LibraryItem {
        let item = LibraryItem(
            mediaURL: mediaURL,
            mediaType: mediaType,
            verificationState: verificationState.rawValue,
            source: source,
            capturedAt: capturedAt
        )
        modelContext.insert(item)
        try? modelContext.save()
        return item
    }

    func delete(_ item: LibraryItem) {
        modelContext.delete(item)
        try? modelContext.save()
    }
}
