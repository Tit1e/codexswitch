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
        XCTAssertEqual(openAI["access"] as? String, "access-token-acc-123")
        XCTAssertEqual(openAI["refresh"] as? String, "refresh-token-acc-123")
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

    func testReloadRecognizesAPIKeyMode() throws {
        let harness = try StoreTestHarness()
        let store = harness.makeStore()

        try harness.writeActiveAPIKey(store: store, apiKey: "sk-test-12345678")
        try harness.writeConfigBaseURL(store: store, baseURL: "http://127.0.0.1:8888/v1")
        store.reload()

        XCTAssertEqual(store.activeMode, .apiKey)
        XCTAssertEqual(store.selectedMode, .apiKey)
        XCTAssertEqual(store.activeAPIKeyFingerprint, "sk-t...5678")
        XCTAssertEqual(store.draftAPIKey, "sk-test-12345678")
        XCTAssertEqual(store.draftAPIBaseURL, "http://127.0.0.1:8888/v1")
    }

    func testInitialSelectedModeMatchesCurrentAuthMode() throws {
        let harness = try StoreTestHarness()
        try harness.writeActiveAPIKeyRaw(apiKey: "sk-test-12345678")
        try harness.writeConfigBaseURLRaw(baseURL: "http://127.0.0.1:8888/v1")

        let store = harness.makeStore()

        XCTAssertEqual(store.activeMode, .apiKey)
        XCTAssertEqual(store.selectedMode, .apiKey)
    }

    func testConfirmModeSwitchWritesAPIKeyAuthJSON() throws {
        let harness = try StoreTestHarness()
        let store = harness.makeStore()
        _ = try harness.seedSingleAccount(store: store)

        store.selectMode(.apiKey)
        store.updateDraftAPIKey("sk-live-abcdefgh")
        store.updateDraftAPIBaseURL("http://127.0.0.1:9000/v1")
        store.confirmModeSwitch()

        let object = try harness.readCodexAuthObject()
        XCTAssertEqual(object["OPENAI_API_KEY"] as? String, "sk-live-abcdefgh")
        XCTAssertEqual(object["auth_mode"] as? String, "apikey")
        XCTAssertEqual(store.activeMode, .apiKey)
        XCTAssertEqual(try harness.readConfigBaseURL(store: store), "http://127.0.0.1:9000/v1")
    }

    func testConfirmModeSwitchBackToAuthRestoresSelectedAccount() throws {
        let harness = try StoreTestHarness()
        let store = harness.makeStore()
        let account = try harness.seedSingleAccount(store: store)

        store.selectMode(.apiKey)
        store.updateDraftAPIKey("sk-live-abcdefgh")
        store.confirmModeSwitch()

        store.selectMode(.auth)
        store.selectAuthAccount(account)
        store.confirmModeSwitch()

        XCTAssertEqual(store.activeMode, .auth)
        XCTAssertEqual(try harness.readActiveAuthAccountKey(store: store), account.accountKey)
    }

    func testReloadPreservesAPIKeyDraftWhileEditing() throws {
        let harness = try StoreTestHarness()
        let store = harness.makeStore()

        try harness.writeActiveAPIKey(store: store, apiKey: "sk-test-12345678")
        try harness.writeConfigBaseURL(store: store, baseURL: "http://127.0.0.1:8888/v1")
        store.reload()
        store.selectMode(.apiKey)
        store.updateDraftAPIKey("sk-draft-87654321")
        store.updateDraftAPIBaseURL("http://127.0.0.1:9999/v1")

        store.reload()

        XCTAssertEqual(store.selectedMode, .apiKey)
        XCTAssertEqual(store.draftAPIKey, "sk-draft-87654321")
        XCTAssertEqual(store.draftAPIBaseURL, "http://127.0.0.1:9999/v1")
    }

    func testSameActiveAPIKeyDisablesConfirm() throws {
        let harness = try StoreTestHarness()
        let store = harness.makeStore()

        try harness.writeActiveAPIKey(store: store, apiKey: "sk-test-12345678")
        try harness.writeConfigBaseURL(store: store, baseURL: "http://127.0.0.1:8888/v1")
        store.reload()
        store.selectMode(.apiKey)
        store.updateDraftAPIKey("sk-test-12345678")
        store.updateDraftAPIBaseURL("http://127.0.0.1:8888/v1")

        XCTAssertFalse(store.canConfirmSelection)
    }

    func testChangingOnlyAPIBaseURLEnablesConfirm() throws {
        let harness = try StoreTestHarness()
        let store = harness.makeStore()

        try harness.writeActiveAPIKey(store: store, apiKey: "sk-test-12345678")
        try harness.writeConfigBaseURL(store: store, baseURL: "http://127.0.0.1:8888/v1")
        store.reload()
        store.selectMode(.apiKey)
        store.updateDraftAPIKey("sk-test-12345678")
        store.updateDraftAPIBaseURL("http://127.0.0.1:9999/v1")

        XCTAssertTrue(store.canConfirmSelection)
    }

    func testConfirmModeSwitchBacksUpConfigWhenAPIBaseURLChanges() throws {
        let harness = try StoreTestHarness()
        let store = harness.makeStore()
        _ = try harness.seedSingleAccount(store: store)
        try harness.writeConfigBaseURL(store: store, baseURL: "http://127.0.0.1:8888/v1")

        store.selectMode(.apiKey)
        store.updateDraftAPIKey("sk-live-abcdefgh")
        store.updateDraftAPIBaseURL("http://127.0.0.1:9999/v1")
        store.confirmModeSwitch()

        XCTAssertTrue(harness.configBackupExists())
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

    func readCodexAuthObject() throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: readCodexAuth())
        return try XCTUnwrap(object as? [String: Any])
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

    func writeActiveAPIKey(store: CodexAccountsStore, apiKey: String) throws {
        try FileManager.default.createDirectory(at: store.codexHomeURL, withIntermediateDirectories: true)
        let object: [String: String] = [
            "OPENAI_API_KEY": apiKey,
            "auth_mode": "apikey"
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: store.activeAuthURL)
    }

    func writeActiveAPIKeyRaw(apiKey: String) throws {
        let codexHomeURL = rootURL.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexHomeURL, withIntermediateDirectories: true)
        let object: [String: String] = [
            "OPENAI_API_KEY": apiKey,
            "auth_mode": "apikey"
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: codexHomeURL.appendingPathComponent("auth.json"))
    }

    func writeConfigBaseURL(store: CodexAccountsStore, baseURL: String) throws {
        try FileManager.default.createDirectory(at: store.codexHomeURL, withIntermediateDirectories: true)
        let content = """
        [model_providers.cpa]
        base_url = "\(baseURL)"
        """
        try Data((content + "\n").utf8).write(to: store.codexConfigURL)
    }

    func writeConfigBaseURLRaw(baseURL: String) throws {
        let codexHomeURL = rootURL.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexHomeURL, withIntermediateDirectories: true)
        let content = """
        [model_providers.cpa]
        base_url = "\(baseURL)"
        """
        try Data((content + "\n").utf8).write(to: codexHomeURL.appendingPathComponent("config.toml"))
    }

    func readConfigBaseURL(store: CodexAccountsStore) throws -> String {
        let content = try String(contentsOf: store.codexConfigURL, encoding: .utf8)
        let prefix = "base_url = \""
        guard let line = content.components(separatedBy: .newlines).first(where: { $0.contains(prefix) }) else {
            return ""
        }
        let value = line.replacingOccurrences(of: prefix, with: "")
        return value.replacingOccurrences(of: "\"", with: "")
    }

    func configBackupExists() -> Bool {
        let backupsURL = rootURL.appendingPathComponent(".codex/accounts", isDirectory: true)
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: backupsURL.path) else { return false }
        return items.contains(where: { $0.hasPrefix("config.bak.") && $0.hasSuffix(".toml") })
    }
}
