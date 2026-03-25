import AVFoundation
import SwiftData
import SwiftUI
import UIKit

struct CaptureView: View {
    @StateObject private var viewModel = CaptureViewModel()
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @State private var showingLibrary = false
    #if DEBUG
    @State private var showingDebugView = false
    #endif

    var body: some View {
        Group {
            if viewModel.permissionStatus == .denied || viewModel.permissionStatus == .restricted {
                permissionDeniedView
            } else {
                cameraView
            }
        }
        .task { await viewModel.configure(keyManager: appState.keyManager, libraryStore: LibraryStore(modelContext: modelContext)) }
        .onDisappear { viewModel.stopSession() }
        .sheet(isPresented: $showingLibrary) {
            LibraryView()
        }
        #if DEBUG
        .sheet(isPresented: $showingDebugView) {
            RegistrationDebugView(keyManager: appState.keyManager)
        }
        #endif
    }

    // MARK: - Permission denied

    private var permissionDeniedView: some View {
        VStack(spacing: 12) {
            Text("Camera access required")
                .font(.system(size: 17, weight: .regular, design: .default))
            Text("Enable camera access in Settings to use Zoe.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .accessibilityIdentifier(AX.Capture.openSettingsButton)
        }
        .padding()
        .accessibilityIdentifier(AX.Capture.permissionDeniedView)
    }

    // MARK: - Live camera

    private var cameraView: some View {
        ZStack {
            CameraPreviewView(session: viewModel.session)
                .ignoresSafeArea()
                .accessibilityIdentifier(AX.Capture.cameraPreview)

            // White flash on photo capture
            Color.white
                .opacity(viewModel.captureFlash ? 1 : 0)
                .animation(.easeOut(duration: 0.15), value: viewModel.captureFlash)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // Recording indicator — top center
            if viewModel.isRecording {
                recordingIndicator
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 8)
            }

            // Top-left: debug button (DEBUG only)
            #if DEBUG
            debugButton
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 16)
                .padding(.leading, 16)
            #endif

            // Top-right: front/back camera flip
            cameraFlipButton
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 16)
                .padding(.trailing, 16)

            // Bottom: thumbnail + shutter + photo/video toggle
            VStack(spacing: 0) {
                Spacer()
                HStack(alignment: .center) {
                    LibraryThumbnailButton { showingLibrary = true }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    shutterControl
                    Spacer()
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                photoVideoToggle
                    .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Camera flip button (top-right)

    private var cameraFlipButton: some View {
        Button { viewModel.toggleCamera() } label: {
            Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .padding(10)
                .background(.black.opacity(0.35))
                .clipShape(Circle())
        }
        .accessibilityIdentifier(AX.Capture.cameraFlipButton)
    }

    // MARK: - Debug button (top-left, DEBUG only)

    #if DEBUG
    private var debugButton: some View {
        Button { showingDebugView = true } label: {
            Image(systemName: "ladybug.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .padding(10)
                .background(.black.opacity(0.35))
                .clipShape(Circle())
        }
        .accessibilityIdentifier(AX.Debug.openButton)
    }
    #endif

    // MARK: - Photo/Video mode toggle (bottom)

    private var photoVideoToggle: some View {
        HStack(spacing: 0) {
            modeToggleButton(title: "PHOTO", mode: .photo)
            modeToggleButton(title: "VIDEO", mode: .video)
        }
        .padding(3)
        .background(.black.opacity(0.35))
        .clipShape(Capsule())
        .accessibilityIdentifier(AX.Capture.photoVideoToggle)
    }

    private func modeToggleButton(title: String, mode: CaptureMode) -> some View {
        Button { viewModel.captureMode = mode } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(viewModel.captureMode == mode ? .black : .white)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(viewModel.captureMode == mode ? .white : .clear)
                .clipShape(Capsule())
        }
    }

    // MARK: - Recording indicator (red dot + timer, top-center)

    private var recordingIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
            Text(formattedElapsed(viewModel.recordingElapsed))
                .font(.caption)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.black.opacity(0.4))
        .clipShape(Capsule())
        .accessibilityIdentifier(AX.Capture.recordingBadge)
        .accessibilityHidden(true)
    }

    // MARK: - Shutter / record button (72pt)
    // Photo mode: tap = photo, long-press = video
    // Video mode: tap = start/stop recording

    private var shutterControl: some View {
        Group {
            if viewModel.isRecording {
                // Stop recording button — red inner square
                Button { viewModel.stopRecording() } label: {
                    ZStack {
                        Circle()
                            .strokeBorder(.white, lineWidth: 3)
                            .frame(width: 72, height: 72)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.red)
                            .frame(width: 32, height: 32)
                    }
                }
                .accessibilityIdentifier(AX.Capture.shutterStopButton)
            } else if viewModel.captureMode == .photo {
                // Photo shutter — white circle, long-press starts video
                Button { viewModel.capturePhoto() } label: {
                    Circle()
                        .fill(.white)
                        .frame(width: 72, height: 72)
                        .overlay(
                            Circle()
                                .strokeBorder(.white.opacity(0.4), lineWidth: 3)
                                .frame(width: 80, height: 80)
                        )
                        .scaleEffect(viewModel.captureFlash ? 1.15 : 1.0)
                        .animation(.easeInOut(duration: 0.1), value: viewModel.captureFlash)
                }
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.5)
                        .onEnded { _ in viewModel.startRecording() }
                )
                .accessibilityIdentifier(AX.Capture.shutterPhotoButton)
            } else {
                // Video mode shutter — red circle with white ring (like iOS camera)
                Button { viewModel.startRecording() } label: {
                    Circle()
                        .fill(.red)
                        .frame(width: 72, height: 72)
                        .overlay(
                            Circle()
                                .strokeBorder(.white.opacity(0.4), lineWidth: 3)
                                .frame(width: 80, height: 80)
                        )
                }
                .accessibilityIdentifier(AX.Capture.shutterVideoButton)
            }
        }
    }

    // MARK: - Helpers

    private func formattedElapsed(_ elapsed: TimeInterval) -> String {
        let mins = Int(elapsed) / 60
        let secs = Int(elapsed) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Library thumbnail button

private struct LibraryThumbnailButton: View {
    @Query(sort: \LibraryItem.capturedAt, order: .reverse) private var items: [LibraryItem]
    let action: () -> Void
    @State private var thumbnail: UIImage?

    var body: some View {
        Button(action: action) {
            Group {
                if let img = thumbnail {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo.stack")
                        .foregroundStyle(.white)
                        .font(.system(size: 22))
                }
            }
            .frame(width: 52, height: 52)
            .background(Color.black.opacity(0.35))
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1.5))
        }
        .accessibilityIdentifier(AX.Capture.libraryThumbnailButton)
        .task(id: items.first?.id) { await loadThumbnail() }
    }

    private func loadThumbnail() async {
        guard let item = items.first else { thumbnail = nil; return }
        if item.mediaType == "video" {
            let asset = AVURLAsset(url: item.resolvedMediaURL)
            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            if let (cgImage, _) = try? await gen.image(at: .zero) {
                thumbnail = UIImage(cgImage: cgImage)
            }
        } else {
            thumbnail = UIImage(contentsOfFile: item.resolvedMediaURL.path)
        }
    }
}
