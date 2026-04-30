import XCTest
@testable import Dictonary

final class KeychainServiceTests: XCTestCase {
    func testReadMissingReturnsNil() throws {
        let kc = InMemoryKeychain()
        XCTAssertNil(try kc.read(account: "deepseek"))
    }

    func testWriteThenRead() throws {
        let kc = InMemoryKeychain()
        try kc.write("sk-1234", account: "deepseek")
        XCTAssertEqual(try kc.read(account: "deepseek"), "sk-1234")
    }

    func testWriteOverwrites() throws {
        let kc = InMemoryKeychain()
        try kc.write("sk-1", account: "deepseek")
        try kc.write("sk-2", account: "deepseek")
        XCTAssertEqual(try kc.read(account: "deepseek"), "sk-2")
    }

    func testDeleteRemoves() throws {
        let kc = InMemoryKeychain()
        try kc.write("sk-1234", account: "deepseek")
        try kc.delete(account: "deepseek")
        XCTAssertNil(try kc.read(account: "deepseek"))
    }

    func testDeleteMissingDoesNotThrow() throws {
        let kc = InMemoryKeychain()
        XCTAssertNoThrow(try kc.delete(account: "missing"))
    }
}
