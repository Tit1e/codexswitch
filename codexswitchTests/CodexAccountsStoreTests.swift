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

    func testImportCurrentAuthPreservesPreviouslyActiveAccount() throws {
        let harness = try StoreTestHarness()
        let store = harness.makeStore()
        let original = try harness.seedAccount(
            store: store,
            email: "first@example.com",
            accountID: "acc-111",
            userID: "user-111"
        )

        try harness.writeActiveAuth(
            store: store,
            email: "second@example.com",
            accountID: "acc-222",
            userID: "user-222"
        )

        store.importCurrentAuth()

        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.activeAccountKey, original.accountKey)
        XCTAssertEqual(store.accounts.count, 2)
        XCTAssertEqual(try harness.readActiveAuthAccountKey(store: store), original.accountKey)
    }

    func testImportCurrentAuthSavesNewAccountSnapshotWhileRestoringPreviousAccount() throws {
        let harness = try StoreTestHarness()
        let store = harness.makeStore()
        let original = try harness.seedAccount(
            store: store,
            email: "first@example.com",
            accountID: "acc-111",
            userID: "user-111"
        )

        try harness.writeActiveAuth(
            store: store,
            email: "second@example.com",
            accountID: "acc-222",
            userID: "user-222"
        )

        store.importCurrentAuth()

        let imported = try XCTUnwrap(store.accounts.first(where: { $0.accountKey != original.accountKey }))
        XCTAssertEqual(imported.email, "second@example.com")
        XCTAssertTrue(harness.accountSnapshotExists(store: store, accountKey: imported.accountKey))
        XCTAssertEqual(try harness.readActiveAuthAccountKey(store: store), original.accountKey)
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
        try writeActiveAuth(
            store: store,
            email: "test@example.com",
            accountID: "acc-123",
            userID: "user-123"
        )
        store.importCurrentAuth()
        return try XCTUnwrap(store.accounts.first)
    }

    func seedAccount(store: CodexAccountsStore, email: String, accountID: String, userID: String) throws -> CodexAccount {
        try writeActiveAuth(store: store, email: email, accountID: accountID, userID: userID)
        store.importCurrentAuth()
        return try XCTUnwrap(store.accounts.first(where: { $0.chatgptAccountID == accountID }))
    }

    func writeActiveAuth(store: CodexAccountsStore, email: String, accountID: String, userID: String) throws {
        try FileManager.default.createDirectory(at: store.codexHomeURL, withIntermediateDirectories: true)
        try authJSON(email: email, accountID: accountID, userID: userID).data(using: .utf8)!.write(to: store.activeAuthURL)
    }

    func readActiveAuthAccountKey(store: CodexAccountsStore) throws -> String {
        let data = try Data(contentsOf: store.activeAuthURL)
        let object = try JSONSerialization.jsonObject(with: data)
        let root = try XCTUnwrap(object as? [String: Any])
        let tokens = try XCTUnwrap(root["tokens"] as? [String: Any])
        let accountID = try XCTUnwrap(tokens["account_id"] as? String)
        let idToken = try XCTUnwrap(tokens["id_token"] as? String)
        let payload = try XCTUnwrap(idToken.split(separator: ".").dropFirst().first)
        let padded = String(payload)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let missingPadding = padded.count % 4
        let base64 = missingPadding == 0 ? padded : padded + String(repeating: "=", count: 4 - missingPadding)
        let decoded = try XCTUnwrap(Data(base64Encoded: base64))
        let payloadObject = try JSONSerialization.jsonObject(with: decoded)
        let payloadRoot = try XCTUnwrap(payloadObject as? [String: Any])
        let auth = try XCTUnwrap(payloadRoot["https://api.openai.com/auth"] as? [String: Any])
        let user = try XCTUnwrap(auth["chatgpt_user_id"] as? String)
        return "\(user)::\(accountID)"
    }

    func accountSnapshotExists(store: CodexAccountsStore, accountKey: String) -> Bool {
        let url = store.accountsDirectoryURL.appendingPathComponent(snapshotFilename(for: accountKey))
        return FileManager.default.fileExists(atPath: url.path)
    }

    private func authJSON(email: String, accountID: String, userID: String) -> String {
        """
        {
          "tokens": {
            "access_token": "access-token-\(accountID)",
            "refresh_token": "refresh-token-\(accountID)",
            "account_id": "\(accountID)",
            "id_token": "\(idToken(email: email, accountID: accountID, userID: userID))"
          }
        }
        """
    }

    private func idToken(email: String, accountID: String, userID: String) -> String {
        let header = base64URL("{\"alg\":\"none\"}")
        let payload = """
        {"email":"\(email)","exp":1900000000,"https://api.openai.com/auth":{"chatgpt_user_id":"\(userID)","chatgpt_account_id":"\(accountID)","chatgpt_plan_type":"plus"}}
        """
        let encodedPayload = base64URL(payload)
        return "\(header).\(encodedPayload).sig"
    }

    private func snapshotFilename(for accountKey: String) -> String {
        if accountKey.contains(where: { !($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == ".") }) || accountKey.isEmpty || accountKey == "." || accountKey == ".." {
            let encoded = Data(accountKey.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
            return "\(encoded).auth.json"
        }
        return "\(accountKey).auth.json"
    }

    private func base64URL(_ value: String) -> String {
        Data(value.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
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
