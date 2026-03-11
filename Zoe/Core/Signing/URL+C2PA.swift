import Foundation

// MARK: - URL helpers for C2PA format detection

extension URL {
    /// MIME type string for use with c2pa-ios Builder.sign(format:)
    nonisolated var c2paFormat: String {
        switch pathExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "mov":         return "video/quicktime"
        case "mp4":         return "video/mp4"
        case "heic":        return "image/heic"
        default:            return "image/jpeg"  // safe fallback for AVFoundation JPEG output
        }
    }

    /// True for video file types from AVFoundation
    nonisolated var isVideoFile: Bool {
        ["mov", "mp4", "m4v"].contains(pathExtension.lowercased())
    }
}
