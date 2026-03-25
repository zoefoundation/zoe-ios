import Foundation

// MARK: - URL helpers for media type detection

extension URL {
    /// True for video file types from AVFoundation
    nonisolated var isVideoFile: Bool {
        ["mov", "mp4", "m4v"].contains(pathExtension.lowercased())
    }
}
