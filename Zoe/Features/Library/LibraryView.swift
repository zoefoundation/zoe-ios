import AVFoundation
import SwiftData
import SwiftUI

// Public container: reads @Environment and bootstraps the StateObject
struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState

    var body: some View {
        LibraryViewContent(modelContext: modelContext, keyManager: appState.keyManager)
    }
}

// MARK: - Content (owns the ViewModel as @StateObject)

private struct LibraryViewContent: View {
    @StateObject private var viewModel: LibraryViewModel
    @Query(sort: \LibraryItem.capturedAt, order: .reverse) private var items: [LibraryItem]
    @Namespace private var zoomNamespace
    @State private var navPath: [LibraryItem] = []

    private let keyManager: KeyManager

    init(modelContext: ModelContext, keyManager: KeyManager) {
        self.keyManager = keyManager
        let store = LibraryStore(modelContext: modelContext)
        let verifyVM = VerifyViewModel(store: store)
        _viewModel = StateObject(wrappedValue: LibraryViewModel(store: store, verifyViewModel: verifyVM))
    }

    var body: some View {
        libraryNavigationStack
            .accessibilityIdentifier(AX.Library.screenView)
            .task { await viewModel.configure(keyManager: keyManager) }
            .onAppear { viewModel.verifyPendingItems(from: items) }
            .onChange(of: items) { _, newItems in viewModel.updateCachedItems(newItems) }
            .onOpenURL { url in
                _ = url.startAccessingSecurityScopedResource()
                defer { url.stopAccessingSecurityScopedResource() }
                Task { await viewModel.handleIncomingURL(url) }
            }
            .sheet(isPresented: $viewModel.showingPicker) {
                PHPickerRepresentable { results in
                    Task { await viewModel.handlePickerResult(results) }
                }
                .ignoresSafeArea()
            }
    }

    @ViewBuilder
    private var libraryNavigationStack: some View {
        let navigationStack = NavigationStack(path: $navPath) {
            VStack(spacing: 0) {
                filterChipsRow
                contentBody
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        viewModel.importTapped()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier(AX.Library.importButton)
                }
            }
            .navigationDestination(for: LibraryItem.self) { item in
                MediaDetailView(item: item)
            }
        }

        if #available(iOS 18.0, *) {
            navigationStack
                .navigationTransition(.zoom(sourceID: navPath.last?.id ?? UUID(), in: zoomNamespace))
        } else {
            navigationStack
        }
    }

    @ViewBuilder
    private var contentBody: some View {
        let filtered = viewModel.filteredItems(from: items)
        if filtered.isEmpty {
            emptyState
        } else {
            scrollGrid(items: filtered)
        }
    }

    private var filterChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(.all)
                filterChip(.captured)
                filterChip(.imported)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .padding(.bottom, 8)
    }

    private func filterChip(_ filter: LibraryFilter) -> some View {
        let isActive = viewModel.selectedFilter == filter
        return Button(filter.rawValue) {
            viewModel.selectedFilter = filter
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(isActive ? Color.white : Color.white.opacity(0.08))
        .foregroundStyle(isActive ? Color.black : Color(.secondaryLabel))
        .clipShape(.capsule)
        .accessibilityIdentifier(axID(for: filter))
    }

    private func axID(for filter: LibraryFilter) -> String {
        switch filter {
        case .all:      return AX.Library.filterAll
        case .captured: return AX.Library.filterCaptured
        case .imported: return AX.Library.filterImported
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("Nothing here yet")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Color(.secondaryLabel))
            Text("Capture from the camera or import a file to check its provenance.")
                .font(.footnote)
                .foregroundStyle(Color(.tertiaryLabel))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier(AX.Library.emptyState)
    }

    private let gridColumns = [GridItem(.adaptive(minimum: 80), spacing: 1.5)]

    private func scrollGrid(items: [LibraryItem]) -> some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 1.5) {
                ForEach(items) { item in
                    libraryNavigationLink(for: item)
                }
            }
        }
        .ignoresSafeArea(edges: .horizontal)
        .accessibilityIdentifier(AX.Library.gridView)
    }

    @ViewBuilder
    private func libraryNavigationLink(for item: LibraryItem) -> some View {
        let link = NavigationLink(value: item) {
            LibraryCell(item: item)
        }
        .buttonStyle(.plain)

        if #available(iOS 18.0, *) {
            link.matchedTransitionSource(id: item.id, in: zoomNamespace)
        } else {
            link
        }
    }
}

// MARK: - Grid Cell

private struct LibraryCell: View {
    let item: LibraryItem
    @State private var thumbnail: UIImage?

    var body: some View {
        Color(.systemGray6)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let img = thumbnail {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else if item.mediaType == "video" {
                    Image(systemName: "play.fill")
                        .foregroundStyle(Color(.tertiaryLabel))
                }
            }
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                provenanceDotView.padding(5)
            }
            .accessibilityLabel(cellAccessibilityLabel)
            .accessibilityIdentifier(AX.Library.cell(item.id))
            .task(id: item.id) { await loadThumbnail() }
    }

    private var provenanceDotView: some View {
        let state = VerificationState(rawValue: item.verificationState) ?? .notVerified
        return ProvenanceDot(state: state)
    }

    private var cellAccessibilityLabel: String {
        let typeLabel = item.mediaType == "video" ? "Video" : "Photo"
        let state = VerificationState(rawValue: item.verificationState) ?? .notVerified
        return "\(typeLabel), \(state.accessibilityLabel)"
    }

    private func loadThumbnail() async {
        if item.mediaType == "video" {
            let asset = AVURLAsset(url: item.resolvedMediaURL)
            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            if let (cgImage, _) = try? await gen.image(at: .zero) {
                thumbnail = UIImage(cgImage: cgImage)
            }
        } else {
            let path = item.resolvedMediaURL.path
            thumbnail = UIImage(contentsOfFile: path)
        }
    }
}
