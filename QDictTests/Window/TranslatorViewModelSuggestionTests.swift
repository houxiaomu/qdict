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

    // MARK: - moveSuggestionSelection (Task 13)

    func testMoveSuggestionDownIncrementsAndSetsFlag() {
        let vm = makeVM(engine: makeEngine(["a", "b", "c"]))
        vm.input = "ab"
        vm.moveSuggestionSelection(by: 1)
        XCTAssertEqual(vm.selectionIndex, 1)
        XCTAssertTrue(vm.hasUserMovedSelection)
    }

    func testMoveSuggestionClampsAtBottom() {
        let vm = makeVM(engine: makeEngine(["a", "b"]))
        vm.input = "ab"
        vm.moveSuggestionSelection(by: 5)
        XCTAssertEqual(vm.selectionIndex, 1)
    }

    func testMoveSuggestionClampsAtTop() {
        let vm = makeVM(engine: makeEngine(["a", "b"]))
        vm.input = "ab"
        vm.moveSuggestionSelection(by: -5)
        XCTAssertEqual(vm.selectionIndex, 0)
    }

    func testMoveSuggestionNoopWhenNotVisible() {
        let vm = makeVM(engine: makeEngine([]))
        vm.input = "ab"
        vm.moveSuggestionSelection(by: 1)
        XCTAssertEqual(vm.selectionIndex, 0)
        XCTAssertFalse(vm.hasUserMovedSelection)
    }

    // MARK: - acceptSuggestionForCompletion (Task 14, Tab)

    func testTabFillsInputWithSelectedWord() {
        let vm = makeVM(engine: makeEngine(["epic", "episode"]))
        vm.input = "epi"
        vm.moveSuggestionSelection(by: 1)
        vm.acceptSuggestionForCompletion()
        XCTAssertEqual(vm.input, "episode")
    }

    func testTabResetsHasUserMovedSelectionFlag() {
        let vm = makeVM(engine: makeEngine(["epic"]))
        vm.input = "epi"
        vm.moveSuggestionSelection(by: 0)
        vm.acceptSuggestionForCompletion()
        XCTAssertFalse(vm.hasUserMovedSelection)
    }

    func testTabIsNoopWhenNoSuggestions() {
        let vm = makeVM(engine: makeEngine([]))
        vm.input = "abc"
        vm.acceptSuggestionForCompletion()
        XCTAssertEqual(vm.input, "abc")
    }

    func testTabDoesNotTriggerSubmit() {
        let vm = makeVM(engine: makeEngine(["epic"]))
        vm.input = "epi"
        vm.acceptSuggestionForCompletion()
        XCTAssertEqual(vm.state, .idle)
    }

    // MARK: - submitOrUseSelected (Task 15, Return)

    func testReturnUsesInputWhenUserDidNotMoveSelection() {
        let vm = makeVM(engine: makeEngine(["epic", "episode"]))
        vm.input = "epi"
        vm.submitOrUseSelected()
        XCTAssertEqual(vm.input, "epi")
        if case .idle = vm.state { XCTFail("expected non-idle after submit") }
    }

    func testReturnUsesSelectedWordAfterUserMovedSelection() {
        let vm = makeVM(engine: makeEngine(["epic", "episode"]))
        vm.input = "epi"
        vm.moveSuggestionSelection(by: 1)
        vm.submitOrUseSelected()
        XCTAssertEqual(vm.input, "episode")
    }

    // MARK: - cancelSuggestionSelection (Task 16, Esc first stage)

    func testEscCancelReturnsTrueWhenUserMoved() {
        let vm = makeVM(engine: makeEngine(["epic", "episode"]))
        vm.input = "epi"
        vm.moveSuggestionSelection(by: 1)
        XCTAssertTrue(vm.cancelSuggestionSelection())
        XCTAssertEqual(vm.selectionIndex, 0)
        XCTAssertFalse(vm.hasUserMovedSelection)
        XCTAssertFalse(vm.suggestions.isEmpty)
    }

    func testEscCancelReturnsFalseWhenNotMoved() {
        let vm = makeVM(engine: makeEngine(["epic"]))
        vm.input = "epi"
        XCTAssertFalse(vm.cancelSuggestionSelection())
    }

    func testEscCancelReturnsFalseWhenSuggestionsHidden() {
        let vm = makeVM(engine: makeEngine([]))
        vm.input = "abc"
        XCTAssertFalse(vm.cancelSuggestionSelection())
    }

    // MARK: - submit/reset clear suggestions (Task 17)

    func testSubmitClearsSuggestions() {
        let vm = makeVM(engine: makeEngine(["epic", "episode"]))
        vm.input = "epi"
        XCTAssertFalse(vm.suggestions.isEmpty)
        vm.submit()
        XCTAssertEqual(vm.suggestions, [])
        XCTAssertEqual(vm.selectionIndex, 0)
        XCTAssertFalse(vm.hasUserMovedSelection)
    }

    func testResetClearsSuggestions() {
        let vm = makeVM(engine: makeEngine(["epic"]))
        vm.input = "epi"
        XCTAssertFalse(vm.suggestions.isEmpty)
        vm.reset()
        XCTAssertEqual(vm.suggestions, [])
    }
}
