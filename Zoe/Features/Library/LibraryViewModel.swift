import Combine
import Foundation
import Network
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
    private let signingPipeline: SigningPipeline
    private var networkMonitor: NWPathMonitor?
    private var cachedItems: [LibraryItem] = []

    init(store: LibraryStore, verifyViewModel: VerifyViewModel, signingPipeline: SigningPipeline = SigningPipeline()) {
        self.store = store
        self.verifyViewModel = verifyViewModel
        self.signingPipeline = signingPipeline
    }

    func configure(keyManager: KeyManager) async {
        await signingPipeline.setKeyManager(keyManager)
        await signingPipeline.setAPIClient(APIClient.shared)
        startNetworkMonitoring()
    }

    /// Called by the view whenever the @Query items list changes so the monitor always has fresh data.
    func updateCachedItems(_ items: [LibraryItem]) {
        cachedItems = items
    }

    func importTapped() {
        showingPicker = true
    }

    func handlePickerResult(_ results: [PHPickerResult]) async {
        guard let result = results.first else { return }

        // Dedup: skip if this asset is already in the library
        if let assetId = result.assetIdentifier {
            let key = "asset:\(assetId)"
            let existing = (try? store.modelContext.fetch(FetchDescriptor<LibraryItem>()))?.first(where: { $0.kid == key })
            if existing != nil { return }
        }

        let provider = result.itemProvider
        let assetKey = result.assetIdentifier.map { "asset:\($0)" }
        let imageType = UTType.image.identifier
        let movieType = UTType.movie.identifier

        if provider.hasItemConformingToTypeIdentifier(imageType) {
            await loadAndInsert(provider: provider, typeIdentifier: imageType, mediaType: "photo", assetKey: assetKey)
        } else if provider.hasItemConformingToTypeIdentifier(movieType) {
            await loadAndInsert(provider: provider, typeIdentifier: movieType, mediaType: "video", assetKey: assetKey)
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

    /// Re-triggers upload/verification for items that need it.
    /// - `.pending`: proof upload failed (e.g. offline) — retry upload via retryUpload(), then verify
    /// - `.verifying` / `.signed` / `.notVerified`: re-verify against server
    func verifyPendingItems(from items: [LibraryItem]) {
        cachedItems = items
        for item in items {
            switch VerificationState(rawValue: item.verificationState) {
            case .pending:
                Task {
                    let uploaded = await signingPipeline.retryUpload(fileURL: item.resolvedMediaURL)
                    if uploaded {
                        item.verificationState = VerificationState.signed.rawValue
                        try? store.modelContext.save()
                        verifyViewModel.verify(item: item)
                    }
                }
            case .verifying, .signed, .notVerified:
                verifyViewModel.verify(item: item)
            default:
                break
            }
        }
    }

    func filteredItems(from items: [LibraryItem]) -> [LibraryItem] {
        switch selectedFilter {
        case .all:      return items
        case .captured: return items.filter { $0.source == "captured" }
        case .imported: return items.filter { $0.source == "imported" }
        }
    }

    // MARK: Private

    private func startNetworkMonitoring() {
        let monitor = NWPathMonitor()
        networkMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.verifyPendingItems(from: self.cachedItems)
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.zoe.networkMonitor"))
    }

    private func loadAndInsert(provider: NSItemProvider, typeIdentifier: String, mediaType: String, assetKey: String?) async {
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
                    item.kid = assetKey
                    try? self.store.modelContext.save()
                    self.verifyViewModel.verify(item: item)
                    continuation.resume()
                }
            }
        }
    }

    nonisolated private func copyToSandbox(from url: URL, ext: String) -> URL? {
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