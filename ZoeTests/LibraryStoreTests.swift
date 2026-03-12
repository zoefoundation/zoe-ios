import Foundation
import Testing
import SwiftData
@testable import zoe

@MainActor
final class LibraryStoreTests {

    private func makeStore() throws -> (LibraryStore, ModelContext) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: LibraryItem.self, configurations: config)
        let context = ModelContext(container)
        return (LibraryStore(modelContext: context), context)
    }

    @Test("addItem creates LibraryItem with correct fields")
    func testAddItem_createsLibraryItemWithCorrectFields() throws {
        let (store, _) = try makeStore()
        let url = URL(fileURLWithPath: "/tmp/test.jpg")
        let now = Date()

        let item = store.addItem(
            mediaURL: url,
            mediaType: "photo",
            source: "captured",
            verificationState: .signed,
            capturedAt: now
        )

        #expect(item.mediaURL == url)
        #expect(item.mediaType == "photo")
        #expect(item.source == "captured")
        #expect(item.verificationState == VerificationState.signed.rawValue)
        #expect(item.capturedAt == now)
    }

    @Test("addItem persists item in context")
    func testAddItem_itemPersistedInContext() throws {
        let (store, context) = try makeStore()
        store.addItem(
            mediaURL: URL(fileURLWithPath: "/tmp/a.jpg"),
            mediaType: "photo",
            source: "captured",
            verificationState: .signed
        )

        let all = try context.fetch(FetchDescriptor<LibraryItem>())
        #expect(all.count == 1)
    }

    @Test("delete removes item from context")
    func testDelete_removesItemFromContext() throws {
        let (store, context) = try makeStore()
        let item = store.addItem(
            mediaURL: URL(fileURLWithPath: "/tmp/b.jpg"),
            mediaType: "photo",
            source: "captured",
            verificationState: .unsigned
        )

        store.delete(item)

        let all = try context.fetch(FetchDescriptor<LibraryItem>())
        #expect(all.isEmpty)
    }
}
