# Accessibility Identifiers — Zoe iOS

> **Status: ACTIVE STANDARD**
> This document moved from the root `docs/` directory because it belongs to the iOS app boundary.
> Any UI task is **NOT DONE** unless all identifiers in its scope are added, named correctly, and validated at runtime via XcodeBuildMCP. See [Done Definition](#done-definition).

---

## 1. Naming Convention

All `accessibilityIdentifier` values follow a strict three-part format:

```
[screen].[element].[role]
```

| Part | Description | Examples |
|---|---|---|
| `screen` | The owning screen or shared component | `capture`, `library`, `media_detail`, `verdict`, `debug` |
| `element` | Stable, descriptive element name — no index-only names | `shutter_photo`, `mode_toggle`, `empty_state`, `item_<uuid>` |
| `role` | The semantic role of the element | `button`, `label`, `view`, `cell`, `tab`, `badge`, `sheet`, `loading`, `input` |

### Rules

- **Lowercase snake_case** for all three parts
- **No index-only identifiers** — `library.item.0.cell` is a FAIL; `library.item.<uuid>.cell` is correct
- **Unique in screen context** — no two visible elements on the same screen share the same identifier
- **Dynamic items** use a stable natural key (UUID, server ID, slug) — never a positional index
- **Placeholders** — if a screen is not yet implemented, its identifiers must still be declared in `AccessibilityIdentifiers.swift` (see §3) before the screen ships

### Approved Role Suffixes

| Role | Use for |
|---|---|
| `button` | Any tappable control that triggers an action |
| `label` | Text or status display elements |
| `view` | Container or root screen anchors |
| `cell` | List or grid item containers |
| `tab` | Tab bar items |
| `badge` | Non-interactive overlay indicators (recording dot, provenance dot) |
| `sheet` | Modal/sheet root containers |
| `loading` | Activity indicators / spinners |
| `input` | Text fields, search bars |
| `toggle` | Toggles and segmented controls |
| `empty` | Empty state containers |
| `error` | Error state containers |
| `success` | Success state containers |

---

## 2. Identifier Registry

This is the canonical list of all `accessibilityIdentifier` values in the app. **Update this table whenever identifiers are added or changed.**

### 2.1 App Root — `ZoeApp`

> **Note:** TabView navigation has been removed. Library is now accessed via the thumbnail button in `CaptureView`. The `app.tab_capture.tab` and `app.tab_library.tab` identifiers are retired.

### 2.2 Capture Screen — `CaptureView`

#### Permission Denied State

| Identifier | Element | Notes |
|---|---|---|
| `capture.permission_denied.view` | Root VStack of the denied state | Anchor for detecting this state in tests |
| `capture.open_settings.button` | "Open Settings" button | `Button` |

#### Live Camera State

| Identifier | Element | Notes |
|---|---|---|
| `capture.camera_preview.view` | `CameraPreviewView` | Root anchor of the live camera state |
| `capture.camera_flip.button` | Front/back camera toggle (top-right) | `Button` |
| `capture.photo_video_mode.toggle` | PHOTO / VIDEO pill toggle (bottom) | Capsule HStack of two `Button`s |
| `capture.library_thumbnail.button` | Latest-capture circle (bottom-left) opens Library sheet | `Button` |
| `capture.recording_badge.badge` | Red dot + timer HStack (only visible when recording) | Non-interactive; `.accessibilityHidden(true)` |

#### Shutter Controls (mutually exclusive — only one visible at a time)

| Identifier | Element | State | Notes |
|---|---|---|---|
| `capture.shutter_photo.button` | White circle shutter | `captureMode == .photo`, not recording | `Button` |
| `capture.shutter_video.button` | Red circle shutter | `captureMode == .video`, not recording | `Button` |
| `capture.shutter_stop.button` | Stop recording (red square) | `isRecording == true` | `Button` |

#### Debug Controls (DEBUG builds only)

| Identifier | Element | Notes |
|---|---|---|
| `debug.open.button` | Ladybug button (top-left) opens `RegistrationDebugView` sheet | `#if DEBUG` only |

### 2.3 Library Screen — `LibraryView`

| Identifier | Element | Notes |
|---|---|---|
| `library.screen.view` | `NavigationStack` root | Anchor for detecting this screen |
| `library.dismiss.button` | `[✕]` nav bar dismiss button | Closes the sheet; presented via `CaptureView` |
| `library.empty_state.empty` | Empty state VStack | Visible only when `items.isEmpty` |
| `library.grid.view` | `ScrollView` + `LazyVGrid` container | Visible only when items exist |
| `library.import.button` | `[+]` nav bar import button | Triggers `PHPickerViewController` |
| `library.filter_all.button` | "All" filter chip | Default active on sheet entry |
| `library.filter_captured.button` | "Captured" filter chip | Shows only `source == "captured"` items |
| `library.filter_imported.button` | "Imported" filter chip | Shows only `source == "imported"` items |
| `library.item.<uuid>.cell` | Individual `LibraryCell` | `<uuid>` = `item.id.uuidString.lowercased()` |

### 2.4 Media Detail Screen — `MediaDetailView`

> **Status: Implemented** — Full screen with ProvenancePill, delete flow, and VerdictView navigation.

| Identifier | Element | Notes |
|---|---|---|
| `media_detail.screen.view` | Root screen anchor | |
| `media_detail.media_preview.view` | Image/video preview | |
| `media_detail.verdict_pill.label` | Provenance verdict badge | Tappable; navigates to VerdictView |
| `media_detail.verify.button` | Trigger verification action | |
| `media_detail.loading.loading` | Verification in-progress state | Shown during `.verifying` state |
| `media_detail.share.button` | Share / export button | |
| `media_detail.delete.button` | Trash icon toolbar button | Triggers delete confirmation alert |

### 2.5 Verdict Screen — `VerdictView`

> **Status: Implemented** — Full VerdictScreen with metadata, technical detail, and share report.

| Identifier | Element | Notes |
|---|---|---|
| `verdict.screen.view` | Root screen anchor | |
| `verdict.status_authentic.label` | Authentic result state | |
| `verdict.status_tampered.label` | Tampered result state | |
| `verdict.status_unsigned.label` | Unsigned result state | |
| `verdict.status_not_verified.label` | Not verified result state | |
| `verdict.signing_time.label` | Signing timestamp display | |
| `verdict.kid_excerpt.label` | Key ID (truncated) display | |
| `verdict.dismiss.button` | Dismiss / close verdict | |
| `verdict.share_report.button` | Share Report button | Opens `UIActivityViewController` with report text |

### 2.6 Registration Debug Sheet — `RegistrationDebugView`

> **DEBUG builds only.** Identifiers are conditional on `#if DEBUG`. Opened via the ladybug button (`debug.open.button`) in `CaptureView`.

| Identifier | Element | Notes |
|---|---|---|
| `debug.open.button` | Ladybug button in `CaptureView` top-left | Opens the debug sheet |
| `debug.sheet.sheet` | Root `NavigationStack` | |
| `debug.registration_state.label` | Current state value text | |
| `debug.signing_available.label` | Signing available YES/NO text | |
| `debug.kid_excerpt.label` | KID prefix display | |
| `debug.last_error.label` | Last error text (conditional) | |
| `debug.reset.button` | "Reset & Retry Registration" button | |
| `debug.reset_loading.loading` | `ProgressView` during reset | |

---

## 3. Central Constants File

All identifiers **must** be declared in `ios/Zoe/Core/Accessibility/AccessibilityIdentifiers.swift` as static string constants. Never use raw string literals in view modifiers.

```swift
// ios/Zoe/Core/Accessibility/AccessibilityIdentifiers.swift
enum AX {
    enum App {
        static let tabCapture = "app.tab_capture.tab"
        static let tabLibrary = "app.tab_library.tab"
    }

    enum Capture {
        static let permissionDeniedView = "capture.permission_denied.view"
        static let openSettingsButton   = "capture.open_settings.button"
        static let cameraPreview        = "capture.camera_preview.view"
        static let modeToggleButton     = "capture.mode_toggle.button"
        static let recordingBadge       = "capture.recording_badge.badge"
        static let shutterPhotoButton   = "capture.shutter_photo.button"
        static let shutterVideoButton   = "capture.shutter_video.button"
        static let shutterStopButton    = "capture.shutter_stop.button"
    }

    enum Library {
        static let screenView   = "library.screen.view"
        static let emptyState   = "library.empty_state.empty"
        static let gridView     = "library.grid.view"
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
    }

    #if DEBUG
    enum Debug {
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
```

### Usage in views

```swift
// Correct
Button("Open Settings") { ... }
    .accessibilityIdentifier(AX.Capture.openSettingsButton)

// Correct
ZStack { ... }
    .accessibilityIdentifier(AX.Library.cell(item.id))

// Never inline raw string literals
Button("Open Settings") { ... }
    .accessibilityIdentifier("capture.open_settings.button")
```

---

## 4. Automation-First UI Requirements

### Semantic control requirement

All interactive elements **must** be `Button`, `Toggle`, `TextField`, `Picker`, or another semantic SwiftUI control. Plain shapes with gesture modifiers fail automation because they are not exposed as interactive in the accessibility tree.

### Known violation that must be fixed before identifiers are applied

| Element | File | Issue | Required fix |
|---|---|---|---|
| Photo shutter (`captureMode == .photo`) | `CaptureView.swift` | `Circle + .onTapGesture + .onLongPressGesture` on a non-Button | Wrap in `Button` with custom label; move long-press to `.simultaneousGesture` on the Button |
| Video shutter (`captureMode == .video`, idle) | `CaptureView.swift` | `Circle + .onTapGesture` on a non-Button | Wrap in `Button` with custom label |

> **Rule:** An identifier on a non-semantic control is not sufficient — automation must be able to `.tap()` the element without XCUITest falling back to coordinate-based tapping.

---

## 5. Done Definition

A UI task is **DONE** if and only if **ALL** of the following are true:

| Gate | Criterion | FAIL condition |
|---|---|---|
| **Coverage** | Every interactive element and key state in scope has an `accessibilityIdentifier` | Any button, input, toggle, critical state, or screen anchor is missing an identifier |
| **Naming** | All identifiers follow `[screen].[element].[role]` from §1 and are declared in `AX` enum | Raw strings in views; generic names like `button1`; index-only dynamic identifiers |
| **Semantic controls** | All interactive elements are semantic SwiftUI controls | `onTapGesture` on shapes; hit-test blocking overlays; non-interactable elements |
| **Registry updated** | `ios/docs/accessibility-identifiers.md` §2 table reflects the new identifiers | Doc not updated after adding identifiers |
| **Build passes** | App builds and launches via XcodeBuildMCP simulator build | Build errors or simulator launch failures |
| **Runtime validated** | Key flows exercised by navigating, tapping by identifier, and verifying states | Only code changed — no simulator verification performed |
| **No duplicates** | All identifiers are unique in their screen context | Two elements share the same identifier on the same screen |

---

## 6. XcodeBuildMCP Validation Workflow

After any UI change, run this sequence before marking a story done:

```text
1. simulator build              — confirms clean compile
2. simulator test               — full test suite green
3. launch on simulator          — app starts
4. navigate to relevant screen  — exercise the changed flow
5. tap/query by identifier      — verify all new identifiers live
```

Automation queries identifiers as:

```swift
let shutterButton = app.buttons["capture.shutter_photo.button"]
XCTAssert(shutterButton.exists)
shutterButton.tap()

let cell = app.cells["library.item.3f2a1b00-....cell"]
```

---

## 7. Change Log

| Date | Change | Author |
|---|---|---|
| 2026-03-25 | Initial spec created — full identifier registry for current app surface | Winston / Leo |
| 2026-03-25 | Story 3.2 — added `library.import.button`, `library.filter_all.button`, `library.filter_captured.button`, `library.filter_imported.button` | Amelia / Leo |
| 2026-03-26 | Story 3.4 — added `media_detail.delete.button`; updated §2.4 status from Placeholder to Implemented | Amelia / Leo |
| 2026-03-26 | Story 3.5 — added `verdict.share_report.button` to §2.5; updated §2.5 status from Placeholder to Implemented | Amelia / Leo |
| 2026-03-26 | Story 3.6 — VerificationState.dotColor added; grid changed to adaptive(minimum: 80); `.unsigned` accessibilityLabel updated | Amelia / Leo |
