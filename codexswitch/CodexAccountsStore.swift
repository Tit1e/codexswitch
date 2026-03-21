//
//  CodexAccountsStore.swift
//  codexswitch
//
//  Created by Codex on 2026/3/18.
//

import AppKit
import Combine
import Foundation

@MainActor
final class CodexAccountsStore: ObservableObject {
    @Published private(set) var accounts: [CodexAccount] = []
    @Published private(set) var activeAccountKey: String?
    @Published private(set) var isSwitching = false
    @Published private(set) var isImporting = false
    @Published private(set) var isRefreshingUsage = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdatedAt: Date?

    private let usageEndpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
    private let decoder = JSONDecoder()
    private var timerCancellable: AnyCancellable?
    private var lastUsageRefreshAt: Date?

    let codexHomeURL: URL
    let accountsDirectoryURL: URL
    let registryURL: URL
    let activeAuthURL: URL

    init() {
        let homeURL = fileManager.homeDirectoryForCurrentUser
        codexHomeURL = homeURL.appendingPathComponent(".codex", isDirectory: true)
        accountsDirectoryURL = codexHomeURL.appendingPathComponent("accounts", isDirectory: true)
        registryURL = accountsDirectoryURL.appendingPathComponent("registry.json")
        activeAuthURL = codexHomeURL.appendingPathComponent("auth.json")

        reload()
        timerCancellable = Timer.publish(every: 20, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.reload()
            }
    }

    var statusIconName: String {
        activeAccountKey == nil ? "person.crop.circle.badge.questionmark" : "person.crop.circle.badge.checkmark"
    }

    var activeAccount: CodexAccount? {
        guard let activeAccountKey else { return nil }
        return accounts.first(where: { $0.accountKey == activeAccountKey })
    }

    func reload() {
        do {
            try syncCurrentAuthBestEffort()
            let registry = try loadRegistry()
            accounts = registry.accounts.sorted(by: accountSort)
            activeAccountKey = registry.activeAccountKey
            errorMessage = nil
            lastUpdatedAt = .now
            scheduleUsageRefreshIfNeeded()
        } catch {
            accounts = []
            activeAccountKey = nil
            errorMessage = error.localizedDescription
        }
    }

    func switchAccount(_ account: CodexAccount) {
        guard !isSwitching else { return }
        isSwitching = true
        defer { isSwitching = false }

        do {
            var registry = try loadRegistry()
            guard registry.accounts.contains(where: { $0.accountKey == account.accountKey }) else {
                throw StoreError.accountNotFound
            }

            let sourceURL = accountAuthURL(for: account.accountKey)
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                throw StoreError.authSnapshotMissing(sourceURL.lastPathComponent)
            }

            try ensureAccountsDirectory()
            try backupActiveAuthIfNeeded(using: sourceURL)
            try replaceItem(at: activeAuthURL, withItemAt: sourceURL)

            registry.activeAccountKey = account.accountKey
            registry.activeAccountActivatedAtMs = Int64(Date().timeIntervalSince1970 * 1000)
            let now = Int64(Date().timeIntervalSince1970)
            registry.accounts = registry.accounts.map { existing in
                var updated = existing
                if updated.accountKey == account.accountKey {
                    updated.lastUsedAt = now
                }
                return updated
            }

            try saveRegistry(registry)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importCurrentAuth() {
        do {
            try importAuthFile(from: activeAuthURL)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addNewAccount() {
        do {
            try launchCodexLoginInTerminal()
            errorMessage = "Terminal 已打开 `codex login`。登录完成后点“导入当前账号”。"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveWorkspaceAlias(_ alias: String, for account: CodexAccount) {
        do {
            let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
            try updateAlias(trimmed.isEmpty ? "Team" : trimmed, for: account)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshAllUsage() {
        Task {
            await refreshAllUsageViaAPI(force: true)
        }
    }

    func deleteAccount(_ account: CodexAccount) {
        do {
            guard activeAccountKey != account.accountKey else {
                throw StoreError.activeAccountDeletionNotAllowed
            }

            var registry = try loadOrCreateRegistry()
            guard let index = registry.accounts.firstIndex(where: { $0.accountKey == account.accountKey }) else {
                throw StoreError.accountNotFound
            }

            registry.accounts.remove(at: index)
            registry.accounts.sort(by: accountSort)
            try saveRegistry(registry)

            let snapshotURL = accountAuthURL(for: account.accountKey)
            if fileManager.fileExists(atPath: snapshotURL.path) {
                try fileManager.removeItem(at: snapshotURL)
            }

            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    func workspaceName(for account: CodexAccount) -> String {
        if !account.alias.isEmpty { return account.alias }
        if let plan = account.plan, !plan.isEmpty {
            return plan.capitalized
        }
        return shortWorkspaceID(account.chatgptAccountID)
    }

    func usageSummary(for account: CodexAccount) -> String {
        let quota5h = remainingText(for: rateWindow(minutes: 300, in: account.lastUsage), label: "5h")
        let weekly = remainingText(for: rateWindow(minutes: 10080, in: account.lastUsage), label: "weekly")
        if quota5h == nil && weekly == nil {
            return "用量暂无数据"
        }
        return [quota5h, weekly].compactMap { $0 }.joined(separator: "  ")
    }

    func displayTitle(for account: CodexAccount) -> String {
        "\(account.email)(\(workspaceName(for: account)))"
    }

    func accountMenuTitle(for account: CodexAccount) -> String {
        let title = displayTitle(for: account)
        let usage = usageSummary(for: account)
        let detail = detailSummary(for: account)

        var parts = [title]
        if usage != "用量暂无数据" {
            parts.append(usage)
        }
        if !detail.isEmpty {
            parts.append(detail)
        }
        return parts.joined(separator: " · ")
    }

    func detailSummary(for account: CodexAccount) -> String {
        var parts = [String]()
        if let plan = account.lastUsage?.planType ?? account.plan {
            parts.append(plan.capitalized)
        }
        if let lastUsageAt = account.lastUsageAt {
            parts.append("刷新于 \(clockTimeText(fromUnixSeconds: lastUsageAt))")
        }
        return parts.joined(separator: " · ")
    }

    func groupedAccounts() -> [(email: String, accounts: [CodexAccount])] {
        let grouped = Dictionary(grouping: accounts, by: \.email)
        return grouped.keys.sorted().map { email in
            let items = (grouped[email] ?? []).sorted(by: accountSort)
            return (email, items)
        }
    }

    private func loadRegistry() throws -> CodexRegistry {
        guard fileManager.fileExists(atPath: registryURL.path) else {
            throw StoreError.registryMissing(registryURL.path)
        }
        let data = try Data(contentsOf: registryURL)
        return try decoder.decode(CodexRegistry.self, from: data)
    }

    private func loadOrCreateRegistry() throws -> CodexRegistry {
        if fileManager.fileExists(atPath: registryURL.path) {
            return try loadRegistry()
        }
        return CodexRegistry(
            schemaVersion: 4,
            activeAccountKey: nil,
            activeAccountActivatedAtMs: nil,
            autoSwitch: AutoSwitchConfig(),
            api: ApiConfig(),
            accounts: []
        )
    }

    private func saveRegistry(_ registry: CodexRegistry) throws {
        try ensureAccountsDirectory()
        var registry = registry
        registry.schemaVersion = 4
        let data = try encoder.encode(registry)
        try writeAtomically(data: data, to: registryURL)
    }

    private func ensureAccountsDirectory() throws {
        try fileManager.createDirectory(at: accountsDirectoryURL, withIntermediateDirectories: true)
    }

    private func accountAuthURL(for accountKey: String) -> URL {
        accountsDirectoryURL.appendingPathComponent(snapshotFilename(for: accountKey))
    }

    private func snapshotFilename(for accountKey: String) -> String {
        if needsFilenameEncoding(accountKey) {
            let encoded = Data(accountKey.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
            return "\(encoded).auth.json"
        }
        return "\(accountKey).auth.json"
    }

    private func needsFilenameEncoding(_ key: String) -> Bool {
        guard !key.isEmpty, key != ".", key != ".." else { return true }
        return key.contains { character in
            !(character.isLetter || character.isNumber || character == "-" || character == "_" || character == ".")
        }
    }

    private func backupActiveAuthIfNeeded(using sourceURL: URL) throws {
        guard fileManager.fileExists(atPath: activeAuthURL.path) else { return }
        let current = try Data(contentsOf: activeAuthURL)
        let incoming = try Data(contentsOf: sourceURL)
        guard current != incoming else { return }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let backupURL = accountsDirectoryURL.appendingPathComponent("auth.json.bak.\(formatter.string(from: .now))")
        try current.write(to: backupURL, options: .atomic)
    }

    private func replaceItem(at destinationURL: URL, withItemAt sourceURL: URL) throws {
        let data = try Data(contentsOf: sourceURL)
        try writeAtomically(data: data, to: destinationURL)
    }

    private func writeAtomically(data: Data, to url: URL) throws {
        let tempURL = url.deletingLastPathComponent().appendingPathComponent("\(url.lastPathComponent).tmp.\(UUID().uuidString)")
        try data.write(to: tempURL, options: .atomic)
        if fileManager.fileExists(atPath: url.path) {
            _ = try fileManager.replaceItemAt(url, withItemAt: tempURL, backupItemName: nil, options: [])
        } else {
            try fileManager.moveItem(at: tempURL, to: url)
        }
    }

    private func updateAlias(_ alias: String, for account: CodexAccount) throws {
        var registry = try loadOrCreateRegistry()
        guard let index = registry.accounts.firstIndex(where: { $0.accountKey == account.accountKey }) else {
            throw StoreError.accountNotFound
        }
        registry.accounts[index].alias = alias
        try saveRegistry(registry)
    }

    private func syncCurrentAuthBestEffort() throws {
        guard fileManager.fileExists(atPath: activeAuthURL.path) else { return }

        let authData = try Data(contentsOf: activeAuthURL)
        let info = try parseAuthInfo(from: authData)
        try ensureAccountsDirectory()

        var registry = try loadOrCreateRegistry()
        let destinationURL = accountAuthURL(for: info.recordKey)
        try writeAtomically(data: authData, to: destinationURL)

        let nowSeconds = Int64(Date().timeIntervalSince1970)
        if let existingIndex = registry.accounts.firstIndex(where: { $0.accountKey == info.recordKey }) {
            var existing = registry.accounts[existingIndex]
            existing.chatgptAccountID = info.accountID
            existing.chatgptUserID = info.userID
            existing.email = info.email
            existing.plan = info.plan
            existing.authMode = "chatgpt"
            registry.accounts[existingIndex] = existing
        } else {
            registry.accounts.append(
                CodexAccount(
                    accountKey: info.recordKey,
                    chatgptAccountID: info.accountID,
                    chatgptUserID: info.userID,
                    email: info.email,
                    alias: "",
                    plan: info.plan,
                    authMode: "chatgpt",
                    createdAt: nowSeconds,
                    lastUsedAt: nil,
                    lastUsage: nil,
                    lastUsageAt: nil,
                    lastUsageStatus: nil,
                    lastUsageErrorMessage: nil,
                    lastLocalRollout: nil
                )
            )
        }

        registry.activeAccountKey = info.recordKey
        registry.activeAccountActivatedAtMs = Int64(Date().timeIntervalSince1970 * 1000)
        if let activeIndex = registry.accounts.firstIndex(where: { $0.accountKey == info.recordKey }) {
            registry.accounts[activeIndex].lastUsedAt = nowSeconds
        }

        registry.accounts.sort(by: accountSort)
        try saveRegistry(registry)
    }

    private func scheduleUsageRefreshIfNeeded() {
        guard !accounts.isEmpty else { return }
        Task {
            await refreshAllUsageViaAPI(force: false)
        }
    }

    private func refreshAllUsageViaAPI(force: Bool) async {
        if isRefreshingUsage { return }
        if !force, let lastUsageRefreshAt, Date().timeIntervalSince(lastUsageRefreshAt) < 90 {
            return
        }

        isRefreshingUsage = true
        defer { isRefreshingUsage = false }

        do {
            var registry = try loadOrCreateRegistry()
            var changed = false

            for index in registry.accounts.indices {
                let account = registry.accounts[index]
                let result = await refreshUsageState(for: account.accountKey)

                switch result {
                case .success(let snapshot):
                    registry.accounts[index].lastUsage = snapshot
                    registry.accounts[index].lastUsageAt = Int64(Date().timeIntervalSince1970)
                    registry.accounts[index].lastUsageStatus = .ok
                    registry.accounts[index].lastUsageErrorMessage = nil
                    registry.accounts[index].plan = snapshot.planType ?? registry.accounts[index].plan
                case .accountIssue(let message):
                    registry.accounts[index].lastUsageStatus = .accountIssue
                    registry.accounts[index].lastUsageErrorMessage = message
                case .unknown(let message):
                    registry.accounts[index].lastUsageStatus = .unknown
                    registry.accounts[index].lastUsageErrorMessage = message
                }

                changed = true
            }

            lastUsageRefreshAt = .now
            if changed {
                try saveRegistry(registry)
                accounts = registry.accounts.sorted(by: accountSort)
                activeAccountKey = registry.activeAccountKey
                lastUpdatedAt = .now
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshUsageState(for accountKey: String) async -> UsageRefreshResult {
        do {
            let credentials = try loadUsageCredentials(for: accountKey)
            return try await fetchUsageSnapshot(credentials: credentials)
        } catch let error as UsageRefreshError {
            switch error {
            case .accountIssue(let message):
                return .accountIssue(message)
            case .unknown(let message):
                return .unknown(message)
            }
        } catch {
            return .unknown("用量接口请求失败")
        }
    }

    private func loadUsageCredentials(for accountKey: String) throws -> UsageCredentials {
        let authURL = accountAuthURL(for: accountKey)
        guard fileManager.fileExists(atPath: authURL.path) else {
            throw UsageRefreshError.accountIssue("账号快照缺失")
        }
        let authData = try Data(contentsOf: authURL)
        let info: ImportedAuthInfo
        do {
            info = try parseAuthInfo(from: authData)
        } catch {
            throw UsageRefreshError.accountIssue("账号认证信息无效")
        }
        guard let accessToken = info.accessToken, !accessToken.isEmpty else {
            throw UsageRefreshError.accountIssue("缺少 access token")
        }
        return UsageCredentials(accessToken: accessToken, accountID: info.accountID)
    }

    private func fetchUsageSnapshot(credentials: UsageCredentials) async throws -> UsageRefreshResult {
        var request = URLRequest(url: usageEndpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 5
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(credentials.accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue("codexswitch", forHTTPHeaderField: "User-Agent")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw UsageRefreshError.unknown("网络异常或请求超时")
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UsageRefreshError.unknown("用量接口响应无效")
        }
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            return .accountIssue("认证失效，请重新登录")
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            return .unknown("用量接口暂时不可用")
        }

        do {
            guard let snapshot = try parseAPIUsageResponse(data: data) else {
                return .unknown("用量数据为空")
            }
            return .success(snapshot)
        } catch {
            throw UsageRefreshError.unknown("用量数据解析失败")
        }
    }

    private func parseAPIUsageResponse(data: Data) throws -> RateLimitSnapshot? {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any] else { return nil }

        let rateLimit = root["rate_limit"] as? [String: Any]
        let primary = parseAPIWindow(rateLimit?["primary_window"])
        let secondary = parseAPIWindow(rateLimit?["secondary_window"])
        let credits = parseCredits(root["credits"])
        let planType = root["plan_type"] as? String

        guard primary != nil || secondary != nil || credits != nil || planType != nil else {
            return nil
        }

        return RateLimitSnapshot(primary: primary, secondary: secondary, credits: credits, planType: planType)
    }

    private func parseAPIWindow(_ value: Any?) -> RateLimitWindow? {
        guard let object = value as? [String: Any] else { return nil }
        guard let usedPercent = (object["used_percent"] as? NSNumber)?.doubleValue else { return nil }
        let limitWindowSeconds = (object["limit_window_seconds"] as? NSNumber)?.intValue
        let windowMinutes = limitWindowSeconds.map { Int(ceil(Double($0) / 60.0)) }
        let resetsAt = (object["reset_at"] as? NSNumber)?.int64Value
        return RateLimitWindow(usedPercent: usedPercent, windowMinutes: windowMinutes, resetsAt: resetsAt)
    }

    private func parseCredits(_ value: Any?) -> CreditsSnapshot? {
        guard let object = value as? [String: Any] else { return nil }
        let hasCredits = (object["has_credits"] as? Bool) ?? false
        let unlimited = (object["unlimited"] as? Bool) ?? false
        let balance = object["balance"] as? String
        return CreditsSnapshot(hasCredits: hasCredits, unlimited: unlimited, balance: balance)
    }

    private func importAuthFile(from sourceURL: URL) throws {
        guard !isImporting else { return }
        isImporting = true
        defer { isImporting = false }
        if sourceURL.standardizedFileURL == activeAuthURL.standardizedFileURL {
            try syncCurrentAuthBestEffort()
            return
        }

        let authData = try Data(contentsOf: sourceURL)
        let info = try parseAuthInfo(from: authData)

        try ensureAccountsDirectory()
        var registry = try loadOrCreateRegistry()
        let destinationURL = accountAuthURL(for: info.recordKey)
        try writeAtomically(data: authData, to: destinationURL)

        let nowSeconds = Int64(Date().timeIntervalSince1970)
        let existingIndex = registry.accounts.firstIndex(where: { $0.accountKey == info.recordKey })
        if let existingIndex {
            var existing = registry.accounts[existingIndex]
            existing.chatgptAccountID = info.accountID
            existing.chatgptUserID = info.userID
            existing.email = info.email
            existing.plan = info.plan
            existing.authMode = "chatgpt"
            registry.accounts[existingIndex] = existing
        } else {
            registry.accounts.append(
                CodexAccount(
                    accountKey: info.recordKey,
                    chatgptAccountID: info.accountID,
                    chatgptUserID: info.userID,
                    email: info.email,
                    alias: "",
                    plan: info.plan,
                    authMode: "chatgpt",
                    createdAt: nowSeconds,
                    lastUsedAt: nil,
                    lastUsage: nil,
                    lastUsageAt: nil,
                    lastUsageStatus: nil,
                    lastUsageErrorMessage: nil,
                    lastLocalRollout: nil
                )
            )
        }

        registry.accounts.sort(by: accountSort)
        try saveRegistry(registry)
    }

    private func parseAuthInfo(from data: Data) throws -> ImportedAuthInfo {
        let rootObject = try JSONSerialization.jsonObject(with: data)
        guard let root = rootObject as? [String: Any] else {
            throw StoreError.invalidAuthFile("auth.json 不是合法对象")
        }

        guard let tokens = root["tokens"] as? [String: Any] else {
            throw StoreError.invalidAuthFile("缺少 tokens 字段")
        }
        let accessToken = tokens["access_token"] as? String
        guard let accountID = tokens["account_id"] as? String, !accountID.isEmpty else {
            throw StoreError.invalidAuthFile("缺少 account_id")
        }
        guard let idToken = tokens["id_token"] as? String, !idToken.isEmpty else {
            throw StoreError.invalidAuthFile("缺少 id_token")
        }

        let payload = try decodeJWTPayload(idToken)
        guard let email = (payload["email"] as? String)?.lowercased(), !email.isEmpty else {
            throw StoreError.invalidAuthFile("缺少 email")
        }
        guard let auth = payload["https://api.openai.com/auth"] as? [String: Any] else {
            throw StoreError.invalidAuthFile("缺少 OpenAI auth claims")
        }

        let userID = ((auth["chatgpt_user_id"] as? String) ?? (auth["user_id"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userID.isEmpty else {
            throw StoreError.invalidAuthFile("缺少 user_id")
        }

        if let jwtAccountID = auth["chatgpt_account_id"] as? String, !jwtAccountID.isEmpty, jwtAccountID != accountID {
            throw StoreError.invalidAuthFile("account_id 与 JWT 不一致")
        }

        let plan = (auth["chatgpt_plan_type"] as? String)?.lowercased()
        return ImportedAuthInfo(
            email: email,
            userID: userID,
            accountID: accountID,
            recordKey: "\(userID)::\(accountID)",
            plan: plan,
            accessToken: accessToken
        )
    }

    private func decodeJWTPayload(_ jwt: String) throws -> [String: Any] {
        let segments = jwt.split(separator: ".")
        guard segments.count >= 2 else {
            throw StoreError.invalidAuthFile("id_token 不是合法 JWT")
        }

        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        if padding > 0 {
            base64 += String(repeating: "=", count: padding)
        }
        guard let data = Data(base64Encoded: base64) else {
            throw StoreError.invalidAuthFile("JWT payload 解码失败")
        }
        let object = try JSONSerialization.jsonObject(with: data)
        guard let payload = object as? [String: Any] else {
            throw StoreError.invalidAuthFile("JWT payload 不是对象")
        }
        return payload
    }

    private func launchCodexLoginInTerminal() throws {
        let script = """
        tell application "Terminal"
            activate
            do script "codex login"
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try process.run()
    }

    private func accountSort(lhs: CodexAccount, rhs: CodexAccount) -> Bool {
        let emailComparison = lhs.email.localizedCaseInsensitiveCompare(rhs.email)
        if emailComparison != .orderedSame {
            return emailComparison == .orderedAscending
        }
        return lhs.accountKey < rhs.accountKey
    }

    private func rateWindow(minutes: Int, in snapshot: RateLimitSnapshot?) -> RateLimitWindow? {
        guard let snapshot else { return nil }
        if snapshot.primary?.windowMinutes == minutes { return snapshot.primary }
        if snapshot.secondary?.windowMinutes == minutes { return snapshot.secondary }
        return minutes == 300 ? snapshot.primary : snapshot.secondary
    }

    private func remainingText(for window: RateLimitWindow?, label: String) -> String? {
        guard let window else { return nil }
        let resetText = resetText(for: window.resetsAt)
        if let resetsAt = window.resetsAt, resetsAt <= Int64(Date().timeIntervalSince1970) {
            if let resetText {
                return "\(label) 剩余 100% · 重置于 \(resetText)"
            }
            return "\(label) 剩余 100%"
        }
        let remaining = max(0, min(100, Int((100 - window.usedPercent).rounded(.down))))
        if let resetText {
            return "\(label) 剩余 \(remaining)% · 重置于 \(resetText)"
        }
        return "\(label) 剩余 \(remaining)%"
    }

    private func shortWorkspaceID(_ accountID: String) -> String {
        guard accountID.count > 12 else { return accountID }
        return "\(accountID.prefix(8))...\(accountID.suffix(4))"
    }

    private func relativeDateText(fromUnixSeconds seconds: Int64) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: Date(timeIntervalSince1970: TimeInterval(seconds)), relativeTo: .now)
    }

    private func clockTimeText(fromUnixSeconds seconds: Int64) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(seconds)))
    }

    private func resetText(for unixSeconds: Int64?) -> String? {
        guard let unixSeconds else { return nil }

        let date = Date(timeIntervalSince1970: TimeInterval(unixSeconds))
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "今天 HH:mm"
            return formatter.string(from: date)
        }

        if calendar.isDateInTomorrow(date) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "明天 HH:mm"
            return formatter.string(from: date)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
    }
}

extension Character {
    fileprivate var isLetter: Bool {
        unicodeScalars.allSatisfy(CharacterSet.letters.contains)
    }

    fileprivate var isNumber: Bool {
        unicodeScalars.allSatisfy(CharacterSet.decimalDigits.contains)
    }
}

enum StoreError: LocalizedError {
    case registryMissing(String)
    case accountNotFound
    case activeAccountDeletionNotAllowed
    case authSnapshotMissing(String)
    case invalidAuthFile(String)

    var errorDescription: String? {
        switch self {
        case .registryMissing(let path):
            return "未找到 registry.json: \(path)"
        case .accountNotFound:
            return "账号不存在，可能已经被外部工具移除。"
        case .activeAccountDeletionNotAllowed:
            return "请先切换到其他账号，再删除当前激活账号。"
        case .authSnapshotMissing(let filename):
            return "未找到账号快照文件: \(filename)"
        case .invalidAuthFile(let reason):
            return "auth.json 无法导入: \(reason)"
        }
    }
}

private struct ImportedAuthInfo {
    let email: String
    let userID: String
    let accountID: String
    let recordKey: String
    let plan: String?
    let accessToken: String?
}

private struct UsageCredentials {
    let accessToken: String
    let accountID: String
}

private enum UsageRefreshResult {
    case success(RateLimitSnapshot)
    case accountIssue(String)
    case unknown(String)
}

private enum UsageRefreshError: Error {
    case accountIssue(String)
    case unknown(String)
}
