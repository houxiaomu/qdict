import XCTest
@testable import QDict

@MainActor
final class TranslatorWindowControllerTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("TranslatorWindowControllerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeController() -> TranslatorWindowController {
        let svc = TranslationService()
        let history = HistoryStore(fileURL: tempDir.appendingPathComponent("h.json"), limit: 50)
        return TranslatorWindowController(
            service: svc,
            dictTemplate: "{{text}}",
            translTemplate: "{{text}}",
            historyStore: history
        )
    }

    func testShowPreferencesAndSoftHide_invokesCallbackAfterSoftHide() {
        let controller = makeController()
        controller.show()
        XCTAssertTrue(controller.isVisible, "panel should be visible after show()")

        var prefsOpened = 0
        var visibilityWhenCallbackFired: Bool?
        controller.onShowPreferences = {
            prefsOpened += 1
            visibilityWhenCallbackFired = controller.isVisible
        }

        controller.showPreferencesAndSoftHide()

        XCTAssertEqual(prefsOpened, 1, "onShowPreferences must be invoked exactly once")
        XCTAssertEqual(visibilityWhenCallbackFired, false,
                       "panel must already be soft-hidden when the callback fires")
        XCTAssertFalse(controller.isVisible, "panel must remain hidden after the call")
    }

    func testShowPreferencesAndSoftHide_isSafeWhenNoCallbackInstalled() {
        let controller = makeController()
        controller.show()

        controller.onShowPreferences = nil
        controller.showPreferencesAndSoftHide()

        XCTAssertFalse(controller.isVisible)
    }
}
