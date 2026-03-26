import AVKit
import AVFoundation
import SwiftData
import SwiftUI

@MainActor
struct MediaDetailView: View {
    let item: LibraryItem

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showDeleteConfirmation = false
    @State private var navigateToVerdict = false
    @State private var player: AVPlayer?

    var body: some View {
        ZStack(alignment: .topLeading) {
            mediaContent
            pillOverlay
                .padding(.leading, 16)
                .padding(.top, 14)
        }
        .accessibilityIdentifier(AX.MediaDetail.screenView)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityIdentifier(AX.MediaDetail.deleteButton)
            }
        }
        .alert("Delete this file?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) { deleteItem() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It will be removed from Zoe Library.")
        }
        .navigationDestination(isPresented: $navigateToVerdict) {
            VerdictView(item: item)
        }
        .onAppear {
            if item.mediaType == "video" {
                player = AVPlayer(url: item.resolvedMediaURL)
            }
        }
    }

    @ViewBuilder
    private var mediaContent: some View {
        if item.mediaType == "video" {
            VideoPlayer(player: player)
                .accessibilityIdentifier(AX.MediaDetail.mediaPreview)
                .contextMenu {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
        } else {
            GeometryReader { geo in
                if let uiImage = UIImage(contentsOfFile: item.resolvedMediaURL.path) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    Color(.systemGray6)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            .accessibilityIdentifier(AX.MediaDetail.mediaPreview)
            .contextMenu {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private var pillOverlay: some View {
        let state = VerificationState(rawValue: item.verificationState) ?? .notVerified
        switch state {
        case .unsigned:
            EmptyView()
        case .verifying:
            ProgressView()
                .tint(.white)
                .accessibilityIdentifier(AX.MediaDetail.loading)
        default:
            ProvenancePill(state: state) {
                navigateToVerdict = true
            }
        }
    }

    private func deleteItem() {
        LibraryStore(modelContext: modelContext).delete(item)
        dismiss()
    }
}
