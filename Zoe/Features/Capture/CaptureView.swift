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
        .sensoryFeedback(.selection, trigger: viewModel.captureMode)
        .sensoryFeedback(.impact(weight: .heavy, intensity: 1.0), trigger: viewModel.hapticCaptureTrigger)
        .sensoryFeedback(.impact(weight: .medium), trigger: viewModel.hapticRecordingTrigger)
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

            // Shutter — floating above the bottom bar
            VStack {
                Spacer()
                shutterControl
                    .padding(.bottom, 72)
            }

            // Bottom bar — tab-bar style, pinned to extreme bottom
            VStack {
                Spacer()
                captureBottomBar
            }
        }
    }

    // MARK: - Bottom bar (native tab-bar style: thumbnail | Photo  Video | flip)

    private var captureBottomBar: some View {
        HStack(spacing: 0) {
            LibraryThumbnailButton { showingLibrary = true }
                .padding(.leading, 20)

            modeTabButton(label: "Photo", mode: .photo)
            modeTabButton(label: "Video", mode: .video)

            cameraFlipButton
                .padding(.trailing, 20)
        }
        .frame(height: 49)
        .background(
            Rectangle()
                .fill(.bar)
                .ignoresSafeArea(edges: .bottom)
        )
        .accessibilityIdentifier(AX.Capture.photoVideoToggle)
    }

    private func modeTabButton(label: String, mode: CaptureMode) -> some View {
        Button { viewModel.captureMode = mode } label: {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(viewModel.captureMode == mode ? Color.accentColor : Color.secondary)
                .frame(maxWidth: .infinity, minHeight: 49)
        }
        .disabled(viewModel.isRecording)
    }

    // MARK: - Camera flip button (bottom-right of bottom bar)

    private var cameraFlipButton: some View {
        Button { viewModel.toggleCamera() } label: {
            Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                .font(.system(size: 20))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Color.white.opacity(0.12))
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
                        .frame(width: 52, height: 52)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color(.systemGray3))
                        .frame(width: 52, height: 52)
                }
            }
            .overlay(Circle().strokeBorder(.white.opacity(0.4), lineWidth: 1.5))
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
