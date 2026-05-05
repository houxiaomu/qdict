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
        vm.suggestions = [item]
        XCTAssertTrue(vm.isSuggestionsVisible)
        vm.isDrawerOpen = true
        XCTAssertFalse(vm.isSuggestionsVisible)
    }

    // MARK: - refreshSuggestions short-circuits

    private func makeStubItem(_ w: String) -> SuggestionItem {
        SuggestionItem(id: w, kind: .dictionary, word: w, pos: nil, gloss: "g", badge: .none)
    }

    private func makeEngine(_ words: [String]) -> StubEngine {
        StubEngine(items: words.map { makeStubItem($0) })
    }

    func testRefreshShortCircuitsOnTooShortInput() {
        let vm = makeVM(engine: makeEngine(["a"]))
        vm.input = "a"                                  // length < 2
        XCTAssertEqual(vm.suggestions, [])
    }

    func testRefreshShortCircuitsOnNonASCII() {
        let vm = makeVM(engine: makeEngine(["abc"]))
        vm.input = "你好"
        XCTAssertEqual(vm.suggestions, [])
    }

    func testRefreshShortCircuitsOnTrailingSpace() {
        let vm = makeVM(engine: makeEngine(["look up"]))
        vm.input = "look "                              // ends with space
        XCTAssertEqual(vm.suggestions, [])
    }

    func testRefreshLoadsItemsForValidPrefix() {
        let vm = makeVM(engine: makeEngine(["epic", "episode"]))
        vm.input = "epi"
        XCTAssertEqual(vm.suggestions.map(\.word), ["epic", "episode"])
        XCTAssertEqual(vm.selectionIndex, 0)
        XCTAssertFalse(vm.hasUserMovedSelection)
    }

    func testRefreshShortCircuitsDuringStreaming() {
        let vm = makeVM(engine: makeEngine(["epic"]))
        vm.state = .streaming("partial")
        vm.input = "epic"
        XCTAssertEqual(vm.suggestions, [])
    }

    func testRefreshAllowedInDoneState() {
        let vm = makeVM(engine: makeEngine(["epic"]))
        vm.state = .done("done text")
        vm.input = "epi"
        XCTAssertEqual(vm.suggestions.map(\.word), ["epic"])
    }

    func testRefreshResetsSelectionOnNewInput() {
        let vm = makeVM(engine: makeEngine(["epic", "episode"]))
        vm.input = "epi"
        vm.selectionIndex = 1
        vm.input = "epis"
        XCTAssertEqual(vm.selectionIndex, 0)
    }
}
