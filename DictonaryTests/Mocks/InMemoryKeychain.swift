import Foundation
@testable import Dictonary

final class InMemoryKeychain: KeychainService {
    private var storage: [String: String] = [:]

    func read(account: String) throws -> String? {
        storage[account]
    }

    func write(_ value: String, account: String) throws {
        storage[account] = value
    }

    func delete(account: String) throws {
        storage.removeValue(forKey: account)
    }
}
