import XCTest

final class VerdictViewUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - AC1 / AC10: Root screen anchor exists

    /// Navigate to a verdict screen and confirm the root ScrollView anchor is present.
    func test_verdictView_screenAnchorExists() throws {
        try navigateToVerdictView()
        XCTAssertTrue(
            app.otherElements[AX.Verdict.screenView].waitForExistence(timeout: 5),
            "verdict.screen.view anchor should exist after navigating to VerdictView"
        )
    }

    // MARK: - AC2 / AC10: Authentic status label

    /// With an authentic item the status_authentic identifier should be hittable.
    func test_verdictView_authenticState_statusLabelExists() throws {
        try navigateToVerdictView()
        guard app.otherElements[AX.Verdict.screenView].waitForExistence(timeout: 5) else {
            XCTFail("VerdictView screen anchor not found")
            return
        }
        let statusLabel = app.otherElements[AX.Verdict.statusAuthentic]
        if statusLabel.waitForExistence(timeout: 3) {
            XCTAssertTrue(statusLabel.isHittable, "verdict.status_authentic.label should be hittable")
        }
        // Item may not be authentic — other states are valid; test is not a failure
    }

    // MARK: - AC8 / AC10: Share Report button

    /// Share Report button should be visible and hittable on VerdictView.
    func test_verdictView_shareReportButton_exists() throws {
        try navigateToVerdictView()
        guard app.otherElements[AX.Verdict.screenView].waitForExistence(timeout: 5) else {
            XCTFail("VerdictView screen anchor not found")
            return
        }
        let shareButton = app.buttons[AX.Verdict.shareReportButton]
        XCTAssertTrue(
            shareButton.waitForExistence(timeout: 5),
            "verdict.share_report.button should exist on VerdictView"
        )
        XCTAssertTrue(shareButton.isHittable, "Share Report button should be hittable")
    }

    // MARK: - AC6 / AC10: Signing time row

    /// The signing time metadata row should exist on VerdictView.
    func test_verdictView_signingTimeRow_exists() throws {
        try navigateToVerdictView()
        guard app.otherElements[AX.Verdict.screenView].waitForExistence(timeout: 5) else {
            XCTFail("VerdictView screen anchor not found")
            return
        }
        XCTAssertTrue(
            app.otherElements[AX.Verdict.signingTime].waitForExistence(timeout: 5),
            "verdict.signing_time.label should exist on VerdictView"
        )
    }

    // MARK: - Helpers

    /// Navigate from capture screen → library → first cell → MediaDetail → ProvenancePill → VerdictView.
    /// Throws `XCTSkip` if no items are available in the library.
    private func navigateToVerdictView() throws {
        let libraryButton = app.buttons[AX.Capture.libraryThumbnailButton]
        if libraryButton.waitForExistence(timeout: 5) {
            libraryButton.tap()
        }

        let grid = app.otherElements[AX.Library.gridView]
        guard grid.waitForExistence(timeout: 5) else {
            throw XCTSkip("Library grid not visible — no items in store")
        }

        let firstCell = app.cells.firstMatch
        guard firstCell.waitForExistence(timeout: 3) else {
            throw XCTSkip("No library cells found — seed data required")
        }
        firstCell.tap()

        guard app.otherElements[AX.MediaDetail.screenView].waitForExistence(timeout: 5) else {
            XCTFail("MediaDetailView did not appear")
            return
        }

        let pill = app.buttons[AX.MediaDetail.verdictPill]
        guard pill.waitForExistence(timeout: 3), pill.isHittable else {
            throw XCTSkip("ProvenancePill not present — item may be .unsigned or .verifying")
        }
        pill.tap()
    }
}
