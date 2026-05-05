import XCTest
@testable import QDict

private struct StubEngine: SuggestionEngine {
    let items: [SuggestionItem]
    func query(_ prefix: String, limit: Int) -> [SuggestionItem] {
        Array(items.prefix(limit))
    }
}

@MainActor
final class TranslatorViewModelSuggestionTests: XCTestCase {

    private func makeVM(engine: SuggestionEngine = StubEngine(items: [])) -> TranslatorViewModel {
        TranslatorViewModel(
            service: TranslationService(),
            dictTemplate: "{{text}}",
            translTemplate: "{{text}}",
            suggestionEngine: engine
        )
    }

    func testInitialStateIsEmptyAndHidden() {
        let vm = makeVM()
        XCTAssertEqual(vm.suggestions, [])
        XCTAssertEqual(vm.selectionIndex, 0)
        XCTAssertFalse(vm.hasUserMovedSelection)
        XCTAssertFalse(vm.isSuggestionsVisible)
    }

    func testIsSuggestionsVisibleRequiresNonEmptyAndDrawerClosed() {
        let item = SuggestionItem(id: "a", kind: .dictionary, word: "a", pos: nil, gloss: "g", badge: .none)
        let vm = makeVM(engine: StubEngine(items: [item]))
        // Directly seed the @Published field — at this stage no observer exists
        // yet (refreshSuggestions wiring is added in Task 12). Even after that
        // task lands, this assignment is a redundant no-op, not a breakage.
        vm.suggestions = [item]
        XCTAssertTrue(vm.isSuggestionsVisible)
        vm.isDrawerOpen = true
        XCTAssertFalse(vm.isSuggestionsVisible)
    }
}
