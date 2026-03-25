import AVFoundation
import SwiftData
import SwiftUI

struct LibraryView: View {
    @Query(sort: \LibraryItem.capturedAt, order: .reverse) private var items: [LibraryItem]
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: LibraryViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    content(vm: vm)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if let vm = viewModel {
                        Button {
                            vm.importTapped()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityIdentifier(AX.Library.importButton)
                    }
                }
            }
        }
        .accessibilityIdentifier(AX.Library.screenView)
        .onAppear {
            if viewModel == nil {
                let store = LibraryStore(modelContext: modelContext)
                let verifyVM = VerifyViewModel(store: store)
                viewModel = LibraryViewModel(store: store, verifyViewModel: verifyVM)
            }
        }
        .onOpenURL { url in
            url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }
            Task { await viewModel?.handleIncomingURL(url) }
        }
        .sheet(isPresented: Binding(
            get: { viewModel?.showingPicker ?? false },
            set: { viewModel?.showingPicker = $0 }
        )) {
            if let vm = viewModel {
                PHPickerRepresentable { results in
                    Task { await vm.handlePickerResult(results) }
                }
                .ignoresSafeArea()
            }
        }
    }

    @ViewBuilder
    private func content(vm: LibraryViewModel) -> some View {
        let filtered = vm.filteredItems(from: items)
        VStack(spacing: 0) {
            filterChipsRow(vm: vm)
            if filtered.isEmpty {
                emptyState
            } else {
                scrollGrid(items: filtered)
            }
        }
    }

    private func filterChipsRow(vm: LibraryViewModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(.all, vm: vm)
                filterChip(.captured, vm: vm)
                filterChip(.imported, vm: vm)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }

    private func filterChip(_ filter: LibraryFilter, vm: LibraryViewModel) -> some View {
        let isActive = vm.selectedFilter == filter
        return Button(filter.rawValue) {
            vm.selectedFilter = filter
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

    private func scrollGrid(items: [LibraryItem]) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 0) {
                ForEach(items) { item in
                    LibraryCell(item: item)
                }
            }
        }
        .accessibilityIdentifier(AX.Library.gridView)
    }
}

// MARK: - Grid Cell

private struct LibraryCell: View {
    let item: LibraryItem
    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            thumbnailContent
            provenanceDotView
                .padding(5)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
        .accessibilityLabel(cellAccessibilityLabel)
        .accessibilityIdentifier(AX.Library.cell(item.id))
        .task(id: item.id) { await loadThumbnail() }
    }

    private var thumbnailContent: some View {
        Group {
            if let img = thumbnail {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(.systemGray6)
                    .overlay {
                        if item.mediaType == "video" {
                            Image(systemName: "play.fill")
                                .foregroundStyle(Color(.tertiaryLabel))
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            let asset = AVURLAsset(url: item.mediaURL)
            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            if let (cgImage, _) = try? await gen.image(at: .zero) {
                thumbnail = UIImage(cgImage: cgImage)
            }
        } else {
            let path = item.mediaURL.path
            thumbnail = UIImage(contentsOfFile: path)
        }
    }
}
