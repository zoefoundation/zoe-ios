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

            Color.white
                .opacity(viewModel.captureFlash ? 1 : 0)
                .animation(.easeOut(duration: 0.15), value: viewModel.captureFlash)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            if viewModel.isRecording {
                recordingIndicator
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 8)
            }

            #if DEBUG
            debugButton
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 16)
                .padding(.leading, 16)
            #endif

            // Shutter — floats above the tab bar
            VStack {
                Spacer()
                shutterControl
                    .padding(.bottom, 70)
            }

            // Bottom controls: transparent, sits above the home indicator safe area
            VStack(spacing: 0) {
                Spacer()
                ZStack(alignment: .center) {
                    CaptureModeTabBar(selection: $viewModel.captureMode)
                        .frame(height: 49)

                    HStack {
                        LibraryThumbnailButton { showingLibrary = true }
                            .padding(.leading, 20)
                        Spacer()
                        cameraFlipButton
                            .padding(.trailing, 20)
                    }
                }
                .frame(height: 49)
                .padding(.bottom, -12)
                .accessibilityIdentifier(AX.Capture.photoVideoToggle)
            }
        }
    }

    // MARK: - Camera flip button

    private var cameraFlipButton: some View {
        Button { viewModel.toggleCamera() } label: {
            Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                .font(.system(size: 22))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
        }
        .tint(.white)
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
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1.5))
                } else {
                    Circle()
                        .strokeBorder(.white.opacity(0.5), lineWidth: 1.5)
                        .frame(width: 44, height: 44)
                }
            }
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

// MARK: - Native UITabBar wrapper for Photo / Video mode selection

private struct CaptureModeTabBar: UIViewRepresentable {
    @Binding var selection: CaptureMode

    func makeUIView(context: Context) -> UITabBar {
        let bar = UITabBar()

        let photo = UITabBarItem(title: "Photo", image: UIImage(systemName: "camera.fill"), tag: 0)
        let video = UITabBarItem(title: "Video", image: UIImage(systemName: "video.fill"), tag: 1)

        // Bigger, semibold text — same weight feel as the old Capture/Library bar
        let font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        [photo, video].forEach { item in
            item.setTitleTextAttributes([.font: font], for: .normal)
            item.setTitleTextAttributes([.font: font], for: .selected)
        }

        bar.items = [photo, video]
        bar.selectedItem = selection == .photo ? photo : video

        // White tint throughout — active bright, inactive dimmed
        bar.tintColor = .white
        bar.unselectedItemTintColor = UIColor.white.withAlphaComponent(0.45)

        // Fully transparent — no background at all
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = nil
        appearance.backgroundColor = .clear
        appearance.shadowColor = .clear
        bar.standardAppearance = appearance
        bar.scrollEdgeAppearance = appearance
        bar.isTranslucent = true

        bar.delegate = context.coordinator
        return bar
    }

    func updateUIView(_ bar: UITabBar, context: Context) {
        let targetTag = selection == .photo ? 0 : 1
        guard bar.selectedItem?.tag != targetTag else { return }
        bar.selectedItem = bar.items?.first { $0.tag == targetTag }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITabBarDelegate {
        var parent: CaptureModeTabBar
        init(_ parent: CaptureModeTabBar) { self.parent = parent }

        func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
            parent.selection = item.tag == 0 ? .photo : .video
        }
    }
}
