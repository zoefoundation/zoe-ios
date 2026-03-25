import Foundation
import Testing
import SwiftData
@testable import zoe

@MainActor
final class LibraryViewModelTests {

    private func makeViewModel() throws -> (LibraryViewModel, LibraryStore) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: LibraryItem.self, configurations: config)
        let context = ModelContext(container)
        let store = LibraryStore(modelContext: context)
        let verifyVM = VerifyViewModel(store: store)
        let vm = LibraryViewModel(store: store, verifyViewModel: verifyVM)
        return (vm, store)
    }

    @Test("selectedFilter defaults to .all")
    func test_selectedFilter_defaultsToAll() throws {
        let (vm, _) = try makeViewModel()
        #expect(vm.selectedFilter == .all)
    }

    @Test("filteredItems(.all) returns all items")
    func test_filteredItems_all_returnsAll() throws {
        let (vm, store) = try makeViewModel()
        store.addItem(mediaURL: URL(fileURLWithPath: "/tmp/a.jpg"), mediaType: "photo", source: "captured", verificationState: .notVerified)
        store.addItem(mediaURL: URL(fileURLWithPath: "/tmp/b.jpg"), mediaType: "photo", source: "imported", verificationState: .notVerified)

        let all = vm.filteredItems(from: try fetchAll(store: store))
        #expect(all.count == 2)
    }

    @Test("filteredItems(.captured) excludes imported items")
    func test_filteredItems_captured_excludesImported() throws {
        let (vm, store) = try makeViewModel()
        store.addItem(mediaURL: URL(fileURLWithPath: "/tmp/c.jpg"), mediaType: "photo", source: "captured", verificationState: .notVerified)
        store.addItem(mediaURL: URL(fileURLWithPath: "/tmp/d.jpg"), mediaType: "photo", source: "imported", verificationState: .notVerified)

        vm.selectedFilter = .captured
        let result = vm.filteredItems(from: try fetchAll(store: store))
        #expect(result.count == 1)
        #expect(result[0].source == "captured")
    }

    @Test("filteredItems(.imported) excludes captured items")
    func test_filteredItems_imported_excludesCaptured() throws {
        let (vm, store) = try makeViewModel()
        store.addItem(mediaURL: URL(fileURLWithPath: "/tmp/e.jpg"), mediaType: "photo", source: "captured", verificationState: .notVerified)
        store.addItem(mediaURL: URL(fileURLWithPath: "/tmp/f.jpg"), mediaType: "photo", source: "imported", verificationState: .notVerified)

        vm.selectedFilter = .imported
        let result = vm.filteredItems(from: try fetchAll(store: store))
        #expect(result.count == 1)
        #expect(result[0].source == "imported")
    }

    @Test("importTapped sets showingPicker to true")
    func test_importTapped_setShowingPickerTrue() throws {
        let (vm, _) = try makeViewModel()
        #expect(vm.showingPicker == false)
        vm.importTapped()
        #expect(vm.showingPicker == true)
    }

    // MARK: Private helpers

    private func fetchAll(store: LibraryStore) throws -> [LibraryItem] {
        try store.modelContext.fetch(FetchDescriptor<LibraryItem>())
    }
}
