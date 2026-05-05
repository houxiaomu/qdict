import XCTest
import AppKit
@testable import QDict

/// Regression tests for the 1.0.2 keyboard-routing bug: macOS sets
/// ``.function`` on arrow-key keyDown events, so a router that strips only
/// ``.numericPad`` then compares against ``.empty`` would silently drop
/// every plain ↑/↓ press. ``userPressedOnly`` must reduce all ambient
/// keyboard bits to the four "real" modifier keys.
final class NSEventModifierFlagsUserPressedTests: XCTestCase {

    func testFunctionBitIsStripped() {
        let raw = NSEvent.ModifierFlags.function
        XCTAssertTrue(raw.userPressedOnly.isEmpty)
    }

    func testNumericPadBitIsStripped() {
        let raw = NSEvent.ModifierFlags.numericPad
        XCTAssertTrue(raw.userPressedOnly.isEmpty)
    }

    func testCapsLockBitIsStripped() {
        let raw = NSEvent.ModifierFlags.capsLock
        XCTAssertTrue(raw.userPressedOnly.isEmpty)
    }

    func testHelpBitIsStripped() {
        let raw = NSEvent.ModifierFlags.help
        XCTAssertTrue(raw.userPressedOnly.isEmpty)
    }

    func testCommandPlusFunctionReducesToCommand() {
        // The exact pattern that bit our key router for Cmd+↓.
        let raw: NSEvent.ModifierFlags = [.command, .function]
        XCTAssertEqual(raw.userPressedOnly, .command)
    }

    func testArrowKeyPlainModsReducesToEmpty() {
        // Real ↓ keyDown on an Apple wireless keyboard observed value:
        // 0x800000 (.function bit only).
        let raw = NSEvent.ModifierFlags(rawValue: 0x800000)
        XCTAssertTrue(raw.userPressedOnly.isEmpty)
    }

    func testShiftPlusOptionPreserved() {
        let raw: NSEvent.ModifierFlags = [.shift, .option]
        XCTAssertEqual(raw.userPressedOnly, [.shift, .option])
    }

    func testAllFourPressedAtOncePreserved() {
        let raw: NSEvent.ModifierFlags = [.shift, .control, .option, .command]
        XCTAssertEqual(raw.userPressedOnly, raw)
    }

    func testEmptyStaysEmpty() {
        XCTAssertTrue(NSEvent.ModifierFlags().userPressedOnly.isEmpty)
    }
}
