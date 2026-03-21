//
//  CodexModels.swift
//  codexswitch
//
//  Created by Codex on 2026/3/18.
//

import Foundation

enum UsageHealthStatus: String, Codable {
    case ok
    case accountIssue = "account_issue"
    case unknown
}

struct CodexRegistry: Codable {
    var schemaVersion: Int
    var activeAccountKey: String?
    var activeAccountActivatedAtMs: Int64?
    var autoSwitch: AutoSwitchConfig
    var api: ApiConfig
    var accounts: [CodexAccount]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case activeAccountKey = "active_account_key"
        case activeAccountActivatedAtMs = "active_account_activated_at_ms"
        case autoSwitch = "auto_switch"
        case api
        case accounts
    }
}

struct AutoSwitchConfig: Codable {
    var enabled: Bool = false
    var threshold5hPercent: Int = 10
    var thresholdWeeklyPercent: Int = 5

    enum CodingKeys: String, CodingKey {
        case enabled
        case threshold5hPercent = "threshold_5h_percent"
        case thresholdWeeklyPercent = "threshold_weekly_percent"
    }
}

struct ApiConfig: Codable {
    var usage: Bool = false
}

struct CodexAccount: Codable, Identifiable {
    var accountKey: String
    var chatgptAccountID: String
    var chatgptUserID: String
    var email: String
    var alias: String
    var plan: String?
    var authMode: String?
    var createdAt: Int64
    var lastUsedAt: Int64?
    var lastUsage: RateLimitSnapshot?
    var lastUsageAt: Int64?
    var lastUsageStatus: UsageHealthStatus?
    var lastUsageErrorMessage: String?
    var lastLocalRollout: RolloutSignature?

    enum CodingKeys: String, CodingKey {
        case accountKey = "account_key"
        case chatgptAccountID = "chatgpt_account_id"
        case chatgptUserID = "chatgpt_user_id"
        case email
        case alias
        case plan
        case authMode = "auth_mode"
        case createdAt = "created_at"
        case lastUsedAt = "last_used_at"
        case lastUsage = "last_usage"
        case lastUsageAt = "last_usage_at"
        case lastUsageStatus = "last_usage_status"
        case lastUsageErrorMessage = "last_usage_error_message"
        case lastLocalRollout = "last_local_rollout"
    }

    var id: String { accountKey }
}

struct RolloutSignature: Codable {
    var path: String
    var eventTimestampMs: Int64

    enum CodingKeys: String, CodingKey {
        case path
        case eventTimestampMs = "event_timestamp_ms"
    }
}

struct RateLimitSnapshot: Codable {
    var primary: RateLimitWindow?
    var secondary: RateLimitWindow?
    var credits: CreditsSnapshot?
    var planType: String?

    enum CodingKeys: String, CodingKey {
        case primary
        case secondary
        case credits
        case planType = "plan_type"
    }
}

struct RateLimitWindow: Codable {
    var usedPercent: Double
    var windowMinutes: Int?
    var resetsAt: Int64?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case windowMinutes = "window_minutes"
        case resetsAt = "resets_at"
    }
}

struct CreditsSnapshot: Codable {
    var hasCredits: Bool
    var unlimited: Bool
    var balance: String?

    enum CodingKeys: String, CodingKey {
        case hasCredits = "has_credits"
        case unlimited
        case balance
    }
}
