import AVFoundation
import SwiftUI
import UIKit

struct CaptureView: View {
    @StateObject private var viewModel = CaptureViewModel()
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
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
        }
        .padding()
    }

    // MARK: - Live camera

    private var cameraView: some View {
        ZStack {
            CameraPreviewView(session: viewModel.session)
                .ignoresSafeArea()

            // White flash on photo capture
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

            // Mode toggle — top right
            modeToogleButton
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 16)
                .padding(.trailing, 16)

            VStack {
                Spacer()
                shutterControl
                    .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Mode toggle button

    private var modeToogleButton: some View {
        Button { viewModel.toggleCaptureMode() } label: {
            Image(systemName: viewModel.captureMode == .photo ? "video.fill" : "camera.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .padding(10)
                .background(.black.opacity(0.35))
                .clipShape(Circle())
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
            } else if viewModel.captureMode == .photo {
                // Photo shutter — white circle, long-press starts video
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
                    .onTapGesture { viewModel.capturePhoto() }
                    .onLongPressGesture(minimumDuration: 0.5) { viewModel.startRecording() }
                    #if DEBUG
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 2.0)
                            .onEnded { _ in showingDebugView = true }
                    )
                    #endif
            } else {
                // Video mode shutter — red circle with white ring (like iOS camera)
                Circle()
                    .fill(.red)
                    .frame(width: 72, height: 72)
                    .overlay(
                        Circle()
                            .strokeBorder(.white.opacity(0.4), lineWidth: 3)
                            .frame(width: 80, height: 80)
                    )
                    .onTapGesture { viewModel.startRecording() }
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
