import XCTest
@testable import Dictonary

@MainActor
final class TranslatorViewModelTests: XCTestCase {

    private func makeVM() -> TranslatorViewModel {
        let svc = TranslationService()
        return TranslatorViewModel(
            service: svc,
            dictTemplate: "{{text}}",
            translTemplate: "{{text}}"
        )
    }

    func testSnapshotNilWhenIdleAndEmpty() {
        let vm = makeVM()
        XCTAssertNil(vm.snapshot())
    }

    func testSnapshotCapturesInputAndState() {
        let vm = makeVM()
        vm.input = "hello"
        XCTAssertEqual(vm.snapshot()?.input, "hello")
        XCTAssertEqual(vm.snapshot()?.state, .idle)
    }

    func testRestoreWritesInputAndState() {
        let vm = makeVM()
        let snap = SessionSnapshot(
            input: "hello",
            state: .done("你好"),
            capturedAt: Date()
        )
        vm.restore(snap)
        XCTAssertEqual(vm.input, "hello")
        XCTAssertEqual(vm.state, .done("你好"))
    }

    func testLoadFromHistoryDoesNotCallService() {
        let vm = makeVM()
        let entry = HistoryEntry(query: "hello", result: "你好", mode: .dictionary)
        vm.loadFromHistory(entry)
        XCTAssertEqual(vm.input, "hello")
        XCTAssertEqual(vm.state, .done("你好"))
    }

    func testResetClearsInputAndState() {
        let vm = makeVM()
        vm.input = "hi"
        vm.restore(SessionSnapshot(input: "hi", state: .done("你"), capturedAt: Date()))
        vm.reset()
        XCTAssertEqual(vm.input, "")
        XCTAssertEqual(vm.state, .idle)
    }
}
