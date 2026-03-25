import Foundation
import SwiftData

@Model
final class LibraryItem {
    var id: UUID
    var mediaURL: URL
    var mediaType: String
    var verificationState: String
    var source: String
    var capturedAt: Date
    var verdictSigningTime: Date?
    var kid: String?

    init(
        id: UUID = UUID(),
        mediaURL: URL,
        mediaType: String,
        verificationState: String = VerificationState.notVerified.rawValue,
        source: String,
        capturedAt: Date = Date(),
        verdictSigningTime: Date? = nil,
        kid: String? = nil
    ) {
        self.id = id
        self.mediaURL = mediaURL
        self.mediaType = mediaType
        self.verificationState = verificationState
        self.source = source
        self.capturedAt = capturedAt
        self.verdictSigningTime = verdictSigningTime
        self.kid = kid
    }

    /// Always resolves to the correct sandbox path regardless of app container UUID changes.
    /// Stored `mediaURL` may contain a stale container path after reinstall; this property
    /// reconstructs the URL from the current Documents directory using only the filename.
    var resolvedMediaURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("ZoeMedia").appendingPathComponent(mediaURL.lastPathComponent)
    }
}
