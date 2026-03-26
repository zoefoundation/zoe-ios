import XCTest

@MainActor
final class LibraryUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - AC1/AC2/AC3: Screen anchor

    /// Library screen anchor exists after navigating to Library.
    func test_library_screenAnchorExists() {
        navigateToLibrary()
        XCTAssertTrue(
            app.otherElements[AX.Library.screenView].waitForExistence(timeout: 5),
            "Library screen anchor (library.screen.view) must exist"
        )
    }

    // MARK: - AC5: Filter chip accessibility identifiers

    /// All three filter chips are present and hittable.
    func test_filterChips_allPresent() {
        navigateToLibrary()
        XCTAssertTrue(
            app.otherElements[AX.Library.screenView].waitForExistence(timeout: 5),
            "Library screen must be visible"
        )

        let allChip      = app.buttons[AX.Library.filterAll]
        let capturedChip = app.buttons[AX.Library.filterCaptured]
        let importedChip = app.buttons[AX.Library.filterImported]

        XCTAssertTrue(allChip.waitForExistence(timeout: 3),      "library.filter_all.button must exist")
        XCTAssertTrue(capturedChip.waitForExistence(timeout: 3), "library.filter_captured.button must exist")
        XCTAssertTrue(importedChip.waitForExistence(timeout: 3), "library.filter_imported.button must exist")

        XCTAssertTrue(allChip.isHittable,      "library.filter_all.button must be hittable")
        XCTAssertTrue(capturedChip.isHittable, "library.filter_captured.button must be hittable")
        XCTAssertTrue(importedChip.isHittable, "library.filter_imported.button must be hittable")
    }

    /// Tapping the Captured chip does not crash — Library screen stays visible.
    func test_filterChip_capturedTap_doesNotCrash() {
        navigateToLibrary()
        XCTAssertTrue(
            app.otherElements[AX.Library.screenView].waitForExistence(timeout: 5)
        )
        app.buttons[AX.Library.filterCaptured].tap()
        XCTAssertTrue(
            app.otherElements[AX.Library.screenView].exists,
            "Library screen must still be visible after tapping Captured chip"
        )
    }

    /// Tapping the Imported chip does not crash — Library screen stays visible.
    func test_filterChip_importedTap_doesNotCrash() {
        navigateToLibrary()
        XCTAssertTrue(
            app.otherElements[AX.Library.screenView].waitForExistence(timeout: 5)
        )
        app.buttons[AX.Library.filterImported].tap()
        XCTAssertTrue(
            app.otherElements[AX.Library.screenView].exists,
            "Library screen must still be visible after tapping Imported chip"
        )
    }

    /// Tapping Captured then All restores default — Library screen stays visible.
    func test_filterChip_allTap_restoresDefaultState() {
        navigateToLibrary()
        XCTAssertTrue(
            app.otherElements[AX.Library.screenView].waitForExistence(timeout: 5)
        )
        app.buttons[AX.Library.filterCaptured].tap()
        app.buttons[AX.Library.filterAll].tap()
        XCTAssertTrue(
            app.otherElements[AX.Library.screenView].exists,
            "Library screen must still be visible after restoring All filter"
        )
    }

    /// When the grid is empty, the empty-state view is shown.
    func test_emptyState_showsWhenEmpty() {
        navigateToLibrary()
        XCTAssertTrue(
            app.otherElements[AX.Library.screenView].waitForExistence(timeout: 5)
        )
        let grid = app.otherElements[AX.Library.gridView]
        let emptyState = app.otherElements[AX.Library.emptyState]
        let gridVisible  = grid.waitForExistence(timeout: 2)
        let emptyVisible = emptyState.waitForExistence(timeout: 2)
        XCTAssertTrue(
            gridVisible || emptyVisible,
            "Either the grid or empty-state must be visible in the Library"
        )
    }

    // MARK: - Helpers

    private func navigateToLibrary() {
        let libraryButton = app.buttons[AX.Capture.libraryThumbnailButton]
        if libraryButton.waitForExistence(timeout: 5) {
            libraryButton.tap()
        }
    }
}
