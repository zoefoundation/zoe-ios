@preconcurrency import AVFoundation
import Combine
import OSLog
import Photos
import UIKit

enum CaptureMode { case photo, video }

@MainActor
final class CaptureViewModel: NSObject, ObservableObject {
    // MARK: - Public session (owned here, exposed read-only to CameraPreviewView)
    // nonisolated(unsafe) opts out of strict Sendable checking for these reference-type AVFoundation objects;
    // safe because AVFoundation guarantees its own thread safety for session/output configuration.
    nonisolated(unsafe) let session = AVCaptureSession()

    // MARK: - Published state
    @Published var permissionStatus: AVAuthorizationStatus = .notDetermined
    @Published var captureMode: CaptureMode = .photo
    @Published var isRecording: Bool = false
    @Published var recordingElapsed: TimeInterval = 0
    @Published var captureFlash: Bool = false

    // MARK: - Private
    nonisolated(unsafe) private let photoOutput = AVCapturePhotoOutput()
    nonisolated(unsafe) private let movieOutput = AVCaptureMovieFileOutput()
    private let signingPipeline: SigningPipeline
    private weak var keyManager: KeyManager?
    private var libraryStore: LibraryStore?
    private var timerTask: Task<Void, Never>?
    private var isSessionConfigured = false

    // Dedicated serial queue for all AVCaptureSession setup/teardown (AVFoundation pattern)
    private static let sessionQueue = DispatchQueue(
        label: "com.zoe.captureSessionQueue", qos: .userInitiated
    )

    init(signingPipeline: SigningPipeline = SigningPipeline(), keyManager: KeyManager? = nil) {
        self.signingPipeline = signingPipeline
        self.keyManager = keyManager
    }

    // MARK: - Configuration

    func configure(keyManager: KeyManager? = nil, libraryStore: LibraryStore? = nil) async {
        if let km = keyManager { self.keyManager = km }
        if let km = keyManager {
            await signingPipeline.setKeyManager(km)
        }
        await signingPipeline.setAPIClient(APIClient.shared)
        if let store = libraryStore { self.libraryStore = store }

        // On subsequent tab returns: skip full setup, just restart the session
        if isSessionConfigured {
            resumeSession()
            return
        }

        let videoGranted = await AVCaptureDevice.requestAccess(for: .video)
        _ = await AVCaptureDevice.requestAccess(for: .audio)
        _ = await PHPhotoLibrary.requestAuthorization(for: .addOnly)

        permissionStatus = AVCaptureDevice.authorizationStatus(for: .video)
        guard videoGranted else { return }

        let session = self.session
        let photoOutput = self.photoOutput
        let movieOutput = self.movieOutput
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Self.sessionQueue.async {
                Self.configureSession(session: session, photoOutput: photoOutput, movieOutput: movieOutput)
                continuation.resume()
            }
        }
        isSessionConfigured = true
    }

    private func resumeSession() {
        let session = self.session
        guard !session.isRunning else { return }
        Self.sessionQueue.async { session.startRunning() }
    }

    private nonisolated static func configureSession(
        session: AVCaptureSession,
        photoOutput: AVCapturePhotoOutput,
        movieOutput: AVCaptureMovieFileOutput
    ) {
        session.beginConfiguration()

        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
              session.canAddInput(videoInput) else {
            Logger(subsystem: "com.zoe", category: "CaptureViewModel")
                .warning("No video device available (expected on Simulator)")
            session.commitConfiguration()
            return
        }
        session.addInput(videoInput)

        if let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }

        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
        if session.canAddOutput(movieOutput) { session.addOutput(movieOutput) }

        session.commitConfiguration()
        session.startRunning()
    }

    // MARK: - Photo capture

    func capturePhoto() {
        guard permissionStatus == .authorized, session.isRunning else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        captureFlash = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            captureFlash = false
        }
        let availableCodecs = photoOutput.availablePhotoCodecTypes
        let settings: AVCapturePhotoSettings
        if let codec = Self.preferredPhotoCodec(from: availableCodecs) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: codec])
        } else {
            settings = AVCapturePhotoSettings()
        }
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    nonisolated static func preferredPhotoCodec(from availableCodecs: [AVVideoCodecType]) -> AVVideoCodecType? {
        if availableCodecs.contains(.jpeg) { return .jpeg }
        if availableCodecs.contains(.hevc) { return .hevc }
        return nil
    }

    private func handleCapturedPhoto(_ data: Data) {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".jpg")
        do {
            try data.write(to: fileURL)
            Task.detached { [weak self] in
                guard let self else { return }
                let outcome = try? await self.signingPipeline.sign(fileURL: fileURL)
                if let outcome {
                    await MainActor.run { [weak self] () -> Void in
                        self?.libraryStore?.addItem(
                            mediaURL: outcome.sandboxURL,
                            mediaType: "photo",
                            source: "captured",
                            verificationState: outcome.verificationState
                        )
                    }
                }
            }
        } catch {
            Logger(subsystem: "com.zoe", category: "CaptureViewModel")
                .error("Failed to write captured photo to temp file: \(error)")
        }
    }

    // MARK: - Video capture

    func toggleCaptureMode() {
        captureMode = captureMode == .photo ? .video : .photo
    }

    func startRecording() {
        guard permissionStatus == .authorized, session.isRunning, !isRecording else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mov")
        movieOutput.startRecording(to: outputURL, recordingDelegate: self)
        isRecording = true
        startTimer()
    }

    func stopRecording() {
        movieOutput.stopRecording()
    }

    // MARK: - Session teardown

    func stopSession() {
        let session = self.session
        Self.sessionQueue.async { session.stopRunning() }
    }

    // MARK: - Timer

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task { @MainActor [weak self] in
            while !(Task.isCancelled) {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { break }
                self.recordingElapsed += 1
            }
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CaptureViewModel: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil, let data = photo.fileDataRepresentation() else {
            Logger(subsystem: "com.zoe", category: "CaptureViewModel")
                .error("Photo capture failed: \(String(describing: error))")
            return
        }
        Task { @MainActor [weak self] in
            self?.handleCapturedPhoto(data)
        }
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension CaptureViewModel: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            self?.isRecording = false
            self?.recordingElapsed = 0
            self?.stopTimer()
        }
        guard error == nil else {
            Logger(subsystem: "com.zoe", category: "CaptureViewModel")
                .error("Video recording failed: \(String(describing: error))")
            return
        }
        Task.detached { [weak self] in
            guard let self else { return }
            let outcome = try? await self.signingPipeline.sign(fileURL: outputFileURL)
            if let outcome {
                await MainActor.run { [weak self] () -> Void in
                    self?.libraryStore?.addItem(
                        mediaURL: outcome.sandboxURL,
                        mediaType: "video",
                        source: "captured",
                        verificationState: outcome.verificationState
                    )
                }
            }
        }
    }
}
