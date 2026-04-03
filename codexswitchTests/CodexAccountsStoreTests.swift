import XCTest
@testable import Codex_Switch

@MainActor
final class CodexAccountsStoreTests: XCTestCase {
    func testLoadOrCreateRegistryDefaultsOpenCodeSyncToFalse() throws {
        let harness = try StoreTestHarness()
        let store = harness.makeStore()

        XCTAssertFalse(store.syncOpenCodeOnSwitch)
    }

    func testToggleOpenCodeSyncPersistsToRegistry() throws {
        let harness = try StoreTestHarness()
        let store = harness.makeStore()

        store.setSyncOpenCodeOnSwitch(true)

        XCTAssertTrue(store.syncOpenCodeOnSwitch)
        let registry = try harness.readRegistryObject()
        XCTAssertEqual(registry["sync_opencode_on_switch"] as? Bool, true)
    }

    func testSwitchAccountSkipsOpenCodeWhenSyncDisabled() throws {
        let harness = try StoreTestHarness()
        let store = harness.makeStore()
        let account = try harness.seedSingleAccount(store: store)

        store.switchAccount(account)

        XCTAssertNil(store.errorMessage)
        XCTAssertFalse(harness.openCodeAuthExists())
    }

    func testSwitchAccountSyncsOpenCodeWhenEnabledAndInstalled() throws {
        let harness = try StoreTestHarness(installedOpenCode: true)
        let store = harness.makeStore()
        let account = try harness.seedSingleAccount(store: store)
        store.setSyncOpenCodeOnSwitch(true)

        store.switchAccount(account)

        XCTAssertNil(store.errorMessage)
        let auth = try harness.readOpenCodeAuthObject()
        let openAI = try XCTUnwrap(auth["openai"] as? [String: Any])
        XCTAssertEqual(openAI["type"] as? String, "oauth")
        XCTAssertEqual(openAI["access"] as? String, "access-token")
        XCTAssertEqual(openAI["refresh"] as? String, "refresh-token")
        XCTAssertEqual(openAI["accountId"] as? String, "acc-123")
        XCTAssertNotNil(openAI["expires"] as? NSNumber)
    }

    func testSwitchAccountReportsPartialSuccessWhenOpenCodeWriteFails() throws {
        let harness = try StoreTestHarness(installedOpenCode: true, writableOpenCodeDirectory: false)
        let store = harness.makeStore()
        let account = try harness.seedSingleAccount(store: store)
        store.setSyncOpenCodeOnSwitch(true)

        store.switchAccount(account)

        XCTAssertEqual(store.errorMessage, "Codex 已切换，但 OpenCode 同步失败")
        XCTAssertEqual(store.activeAccountKey, account.accountKey)
    }
}

@MainActor
private struct StoreTestHarness {
    let rootURL: URL
    let installedOpenCode: Bool
    let writableOpenCodeDirectory: Bool

    init(installedOpenCode: Bool = false, writableOpenCodeDirectory: Bool = true) throws {
        self.rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        self.installedOpenCode = installedOpenCode
        self.writableOpenCodeDirectory = writableOpenCodeDirectory
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let openCodeDataURL = rootURL.appendingPathComponent(".local/share/opencode", isDirectory: true)
        if installedOpenCode {
            if writableOpenCodeDirectory {
                try FileManager.default.createDirectory(at: openCodeDataURL, withIntermediateDirectories: true)
            } else {
                try FileManager.default.createDirectory(at: openCodeDataURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data("blocked".utf8).write(to: openCodeDataURL)
            }
        }
    }

    func makeStore() -> CodexAccountsStore {
        CodexAccountsStore(
            codexHomeURL: rootURL.appendingPathComponent(".codex", isDirectory: true),
            openCodeDataURL: rootURL.appendingPathComponent(".local/share/opencode", isDirectory: true),
            isOpenCodeCommandAvailable: { installedOpenCode }
        )
    }

    func seedSingleAccount(store: CodexAccountsStore) throws -> CodexAccount {
        let authJSON = """
        {
          "tokens": {
            "access_token": "access-token",
            "refresh_token": "refresh-token",
            "account_id": "acc-123",
            "id_token": "eyJhbGciOiJub25lIn0.eyJlbWFpbCI6InRlc3RAZXhhbXBsZS5jb20iLCJleHAiOjE5MDAwMDAwMDAsImh0dHBzOi8vYXBpLm9wZW5haS5jb20vYXV0aCI6eyJjaGF0Z3B0X3VzZXJfaWQiOiJ1c2VyLTEyMyIsImNoYXRncHRfYWNjb3VudF9pZCI6ImFjYy0xMjMiLCJjaGF0Z3B0X3BsYW5fdHlwZSI6InBsdXMifX0.sig"
          }
        }
        """
        try FileManager.default.createDirectory(at: store.codexHomeURL, withIntermediateDirectories: true)
        try authJSON.data(using: .utf8)!.write(to: store.activeAuthURL)
        store.importCurrentAuth()
        return try XCTUnwrap(store.accounts.first)
    }

    func openCodeAuthExists() -> Bool {
        FileManager.default.fileExists(atPath: rootURL.appendingPathComponent(".local/share/opencode/auth.json").path)
    }

    func readCodexAuth() throws -> Data {
        try Data(contentsOf: rootURL.appendingPathComponent(".codex/auth.json"))
    }

    func readOpenCodeAuth() throws -> Data {
        try Data(contentsOf: rootURL.appendingPathComponent(".local/share/opencode/auth.json"))
    }

    func readOpenCodeAuthObject() throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: readOpenCodeAuth())
        return try XCTUnwrap(object as? [String: Any])
    }

    func readRegistryObject() throws -> [String: Any] {
        let url = rootURL.appendingPathComponent(".codex/accounts/registry.json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        return try XCTUnwrap(object as? [String: Any])
    }
}
