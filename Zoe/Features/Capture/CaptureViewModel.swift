import AVFoundation
import Combine
import CryptoKit
import OSLog

nonisolated(unsafe) private let logger = Logger(subsystem: "com.zoe", category: "CaptureViewModel")

@MainActor
final class CaptureViewModel: NSObject, ObservableObject {
    // MARK: - Public session (owned here, exposed read-only to CameraPreviewView)
    // nonisolated(unsafe) opts out of strict Sendable checking for these reference-type AVFoundation objects;
    // safe because AVFoundation guarantees its own thread safety for session/output configuration.
    nonisolated(unsafe) let session = AVCaptureSession()

    // MARK: - Published state
    @Published var permissionStatus: AVAuthorizationStatus = .notDetermined
    @Published var isRecording: Bool = false
    @Published var recordingElapsed: TimeInterval = 0

    // MARK: - Private
    nonisolated(unsafe) private let photoOutput = AVCapturePhotoOutput()
    nonisolated(unsafe) private let movieOutput = AVCaptureMovieFileOutput()
    private let signingPipeline: SigningPipeline
    private weak var keyManager: KeyManager?
    private var timerTask: Task<Void, Never>?

    // Dedicated serial queue for all AVCaptureSession setup/teardown (AVFoundation pattern)
    nonisolated(unsafe) private static let sessionQueue = DispatchQueue(
        label: "com.zoe.captureSessionQueue", qos: .userInitiated
    )

    init(signingPipeline: SigningPipeline = SigningPipeline(), keyManager: KeyManager? = nil) {
        self.signingPipeline = signingPipeline
        self.keyManager = keyManager
    }

    // MARK: - Configuration

    func configure(keyManager: KeyManager? = nil) async {
        if let km = keyManager { self.keyManager = km }

        let videoGranted = await AVCaptureDevice.requestAccess(for: .video)
        _ = await AVCaptureDevice.requestAccess(for: .audio)

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
            logger.warning("No video device available (expected on Simulator)")
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
        var settings = AVCapturePhotoSettings()
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        }
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    private func handleCapturedPhoto(_ data: Data) {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".jpg")
        do {
            try data.write(to: fileURL)
            Task.detached { [weak self] in
                try? await self?.signingPipeline.sign(fileURL: fileURL)
            }
        } catch {
            logger.error("Failed to write captured photo to temp file: \(error)")
        }
    }

    // MARK: - Video capture

    func startRecording() {
        guard permissionStatus == .authorized, session.isRunning, !isRecording else { return }
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
            logger.error("Photo capture failed: \(String(describing: error))")
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
            logger.error("Video recording failed: \(String(describing: error))")
            return
        }
        Task.detached { [weak self] in
            try? await self?.signingPipeline.sign(fileURL: outputFileURL)
        }
    }
}
