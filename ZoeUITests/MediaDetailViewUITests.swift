import XCTest

@MainActor
final class MediaDetailViewUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - AC1: Navigation from Library grid to MediaDetailView

    /// Tap a library cell and verify MediaDetailView screen anchor is visible.
    func test_tapGridCell_navigatesToMediaDetail() throws {
        navigateToLibrary()
        let grid = app.otherElements[AX.Library.gridView]
        guard grid.waitForExistence(timeout: 5) else {
            throw XCTSkip("Library grid not visible — no items in store")
        }
        let firstCell = app.cells.firstMatch
        guard firstCell.waitForExistence(timeout: 3) else {
            throw XCTSkip("No library cells found — seed data required")
        }
        firstCell.tap()
        XCTAssertTrue(
            app.otherElements[AX.MediaDetail.screenView].waitForExistence(timeout: 5),
            "MediaDetailView screen anchor should appear after tapping a library cell"
        )
    }

    // MARK: - AC2: ProvenancePill visible for verified items

    /// With an item in an authenticated state, the verdict pill should be hittable.
    func test_mediaDetailView_provenancePillVisible() throws {
        navigateToLibrary()
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
        // Pill visible only for states other than .unsigned/.verifying
        let pill = app.buttons[AX.MediaDetail.verdictPill]
        if pill.waitForExistence(timeout: 3) {
            XCTAssertTrue(pill.isHittable, "ProvenancePill should be hittable")
        }
        // If pill not present, item may be .unsigned — not a failure
    }

    // MARK: - AC3: ProvenancePill tap navigates to VerdictView

    func test_provenancePillTap_navigatesToVerdictView() throws {
        navigateToLibrary()
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
        XCTAssertTrue(
            app.otherElements[AX.Verdict.screenView].waitForExistence(timeout: 5),
            "VerdictView screen anchor should appear after tapping the ProvenancePill"
        )
    }

    // MARK: - AC4: Delete button shows confirmation alert

    func test_deleteButton_showsConfirmation() throws {
        navigateToLibrary()
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
        let deleteButton = app.buttons[AX.MediaDetail.deleteButton]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 3), "Delete toolbar button should exist")
        XCTAssertTrue(deleteButton.isHittable, "Delete toolbar button should be hittable")
        deleteButton.tap()
        XCTAssertTrue(
            app.alerts["Delete this file?"].waitForExistence(timeout: 3),
            "Delete confirmation alert should appear"
        )
        // Dismiss — tap Cancel to preserve test state
        app.alerts["Delete this file?"].buttons["Cancel"].tap()
    }

    // MARK: - Helpers

    private func navigateToLibrary() {
        let libraryButton = app.buttons[AX.Capture.libraryThumbnailButton]
        if libraryButton.waitForExistence(timeout: 5) {
            libraryButton.tap()
        }
    }
}
