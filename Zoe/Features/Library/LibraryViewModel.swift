import Combine
import Foundation
import PhotosUI
import SwiftData
import UniformTypeIdentifiers

enum LibraryFilter: String, CaseIterable {
    case all = "All"
    case captured = "Captured"
    case imported = "Imported"
}

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var selectedFilter: LibraryFilter = .all
    @Published var showingPicker = false

    private let store: LibraryStore
    private let verifyViewModel: VerifyViewModel

    init(store: LibraryStore, verifyViewModel: VerifyViewModel) {
        self.store = store
        self.verifyViewModel = verifyViewModel
    }

    func importTapped() {
        showingPicker = true
    }

    func handlePickerResult(_ results: [PHPickerResult]) async {
        guard let result = results.first else { return }
        let provider = result.itemProvider
        let imageType = UTType.image.identifier
        let movieType = UTType.movie.identifier

        if provider.hasItemConformingToTypeIdentifier(imageType) {
            await loadAndInsert(provider: provider, typeIdentifier: imageType, mediaType: "photo")
        } else if provider.hasItemConformingToTypeIdentifier(movieType) {
            await loadAndInsert(provider: provider, typeIdentifier: movieType, mediaType: "video")
        }
    }

    func handleIncomingURL(_ url: URL) async {
        let ext = url.pathExtension.lowercased()
        let mediaType = ["mov", "mp4", "m4v", "avi"].contains(ext) ? "video" : "photo"
        guard let destURL = copyToSandbox(from: url, ext: ext) else { return }
        let item = store.addItem(
            mediaURL: destURL,
            mediaType: mediaType,
            source: "imported",
            verificationState: .verifying
        )
        verifyViewModel.verify(item: item)
    }

    func filteredItems(from items: [LibraryItem]) -> [LibraryItem] {
        switch selectedFilter {
        case .all:      return items
        case .captured: return items.filter { $0.source == "captured" }
        case .imported: return items.filter { $0.source == "imported" }
        }
    }

    // MARK: Private

    private func loadAndInsert(provider: NSItemProvider, typeIdentifier: String, mediaType: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] tmpURL, error in
                guard let self, let tmpURL, error == nil else {
                    continuation.resume()
                    return
                }
                let ext = tmpURL.pathExtension
                guard let destURL = self.copyToSandbox(from: tmpURL, ext: ext) else {
                    continuation.resume()
                    return
                }
                Task { @MainActor in
                    let item = self.store.addItem(
                        mediaURL: destURL,
                        mediaType: mediaType,
                        source: "imported",
                        verificationState: .verifying
                    )
                    self.verifyViewModel.verify(item: item)
                    continuation.resume()
                }
            }
        }
    }

    private func copyToSandbox(from url: URL, ext: String) -> URL? {
        let mediaDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ZoeMedia")
        try? FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true, attributes: nil)
        let dest = mediaDir.appendingPathComponent("\(UUID().uuidString).\(ext)")
        do {
            try FileManager.default.copyItem(at: url, to: dest)
            return dest
        } catch {
            return nil
        }
    }
}
