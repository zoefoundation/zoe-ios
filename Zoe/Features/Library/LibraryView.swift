import AVFoundation
import SwiftData
import SwiftUI

struct LibraryView: View {
    @Query(sort: \LibraryItem.capturedAt, order: .reverse) private var items: [LibraryItem]

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    emptyState
                } else {
                    scrollGrid
                }
            }
            .navigationTitle("Library")
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
    }

    private var scrollGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 0) {
                ForEach(items) { item in
                    LibraryCell(item: item)
                }
            }
        }
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
