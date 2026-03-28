import Foundation

// Canonical accessibility identifier constants.
// All identifiers follow [screen].[element].[role] naming convention.
// See ios/docs/accessibility-identifiers.md for the current iOS doc home.
enum AX {
    enum Capture {
        static let permissionDeniedView     = "capture.permission_denied.view"
        static let openSettingsButton       = "capture.open_settings.button"
        static let cameraPreview            = "capture.camera_preview.view"
        static let cameraFlipButton         = "capture.camera_flip.button"
        static let photoVideoToggle         = "capture.photo_video_mode.toggle"
        static let libraryThumbnailButton   = "capture.library_thumbnail.button"
        static let recordingBadge           = "capture.recording_badge.badge"
        static let shutterPhotoButton       = "capture.shutter_photo.button"
        static let shutterVideoButton       = "capture.shutter_video.button"
        static let shutterStopButton        = "capture.shutter_stop.button"
    }

    enum Library {
        static let screenView     = "library.screen.view"
        static let emptyState     = "library.empty_state.empty"
        static let gridView       = "library.grid.view"
        static let dismissButton  = "library.dismiss.button"
        static let importButton   = "library.import.button"
        static let filterAll      = "library.filter_all.button"
        static let filterCaptured = "library.filter_captured.button"
        static let filterImported = "library.filter_imported.button"
        static func cell(_ id: UUID) -> String {
            "library.item.\(id.uuidString.lowercased()).cell"
        }
    }

    enum MediaDetail {
        static let screenView   = "media_detail.screen.view"
        static let mediaPreview = "media_detail.media_preview.view"
        static let verdictPill  = "media_detail.verdict_pill.label"
        static let verifyButton = "media_detail.verify.button"
        static let loading      = "media_detail.loading.loading"
        static let shareButton  = "media_detail.share.button"
        static let deleteButton = "media_detail.delete.button"
    }

    enum Verdict {
        static let screenView        = "verdict.screen.view"
        static let statusAuthentic   = "verdict.status_authentic.label"
        static let statusTampered    = "verdict.status_tampered.label"
        static let statusUnsigned    = "verdict.status_unsigned.label"
        static let statusNotVerified = "verdict.status_not_verified.label"
        static let signingTime       = "verdict.signing_time.label"
        static let kidExcerpt        = "verdict.kid_excerpt.label"
        static let dismissButton     = "verdict.dismiss.button"
        static let shareReportButton = "verdict.share_report.button"
    }

    #if DEBUG
    enum Debug {
        static let openButton        = "debug.open.button"
        static let sheet             = "debug.sheet.sheet"
        static let registrationState = "debug.registration_state.label"
        static let signingAvailable  = "debug.signing_available.label"
        static let kidExcerpt        = "debug.kid_excerpt.label"
        static let lastError         = "debug.last_error.label"
        static let resetButton       = "debug.reset.button"
        static let resetLoading      = "debug.reset_loading.loading"
    }
    #endif
}
