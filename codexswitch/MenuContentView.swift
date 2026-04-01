//
//  MenuContentView.swift
//  codexswitch
//
//  Created by Codex on 2026/3/18.
//

import SwiftUI

struct MenuContentView: View {
    @ObservedObject var store: CodexAccountsStore
    @State private var pendingAction: PendingAction?
    private let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String

    var body: some View {
        VStack(spacing: 14) {
            header

            actionBar

            if let pendingAction {
                confirmationBanner(for: pendingAction)
            }

            if store.accounts.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(store.accounts) { account in
                        accountCard(for: account)
                    }
                }
                .padding(.vertical, 2)
            }

            footer
        }
        .padding(14)
        .frame(width: 380)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.22),
                        Color.white.opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Codex Switch")
                    .font(.system(size: 16, weight: .semibold))
                if let active = store.activeAccount {
                    Text("当前：\(active.email)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    Text("当前没有激活账号")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Circle()
                .fill(Color.accentColor.opacity(0.16))
                .frame(width: 30, height: 30)
                .overlay(
                    Image(systemName: store.statusIconName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                )
        }
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            actionButton("导入当前账号", systemImage: "square.and.arrow.down") {
                store.importCurrentAuth()
            }

            actionButton("添加账号", systemImage: "plus.circle") {
                store.addNewAccount()
            }

            actionButton("刷新用量", systemImage: "arrow.clockwise") {
                store.refreshAllUsage()
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.errorMessage ?? "还没有可切换的 Codex 账号")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
        }
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if let lastUpdatedAt = store.lastUpdatedAt {
                    Text("列表更新于 \(lastUpdatedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                if let errorMessage = store.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            if let appVersion, !appVersion.isEmpty {
                Text("v\(appVersion)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Button("退出应用", role: .destructive) {
                store.quit()
            }
        }
    }

    private func confirmationBanner(for action: PendingAction) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(action.title(store: store))
                .font(.system(size: 12, weight: .semibold))

            Text(action.message(store: store))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button("取消") {
                    pendingAction = nil
                }
                .buttonStyle(.bordered)

                Button(action.confirmTitle, role: action.buttonRole) {
                    confirmPendingAction(action)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(action.backgroundColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(action.backgroundColor.opacity(0.25), lineWidth: 1)
        )
    }

    private func accountCard(for account: CodexAccount) -> some View {
        let isActive = store.activeAccountKey == account.accountKey

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 8) {
                        titleView(for: account)

                        Spacer(minLength: 8)

                        if let lastUsageAt = account.lastUsageAt {
                            Text(clockText(fromUnixSeconds: lastUsageAt))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        if let line = usageLine(for: account, minutes: 300, label: "5h") {
                            usageBadge(line, tint: .blue)
                        }
                        if let line = usageLine(for: account, minutes: 10080, label: "weekly") {
                            usageBadge(line, tint: .blue)
                        }
                        if let status = usageStatusLine(for: account) {
                            usageBadge(status.text, tint: status.tint)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    if !isActive {
                        pendingAction = .switchAccount(account)
                    }
                }

                deleteButton(for: account, isActive: isActive)
            }

        }
        .padding(12)
        .background(cardBackground(for: account, isActive: isActive), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardOverlayColor(for: account, isActive: isActive))
                .allowsHitTesting(false)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(cardBorderColor(for: account, isActive: isActive), lineWidth: 1)
                .allowsHitTesting(false)
        )
    }

    @ViewBuilder
    private func titleView(for account: CodexAccount) -> some View {
        HStack(spacing: 6) {
            Text(account.email)
                .font(.system(size: 13, weight: .semibold))
                .multilineTextAlignment(.leading)
            if let plan = displayPlan(for: account) {
                planTag(plan)
            }
        }
    }

    private func cardBackground(for account: CodexAccount, isActive: Bool) -> some ShapeStyle {
        if account.lastUsageStatus == .accountIssue {
            return AnyShapeStyle(Color.red.opacity(0.16))
        }
        if isActive {
            return AnyShapeStyle(.ultraThinMaterial)
        }
        return AnyShapeStyle(.thinMaterial)
    }

    private func cardOverlayColor(for account: CodexAccount, isActive: Bool) -> Color {
        if account.lastUsageStatus == .accountIssue {
            return Color.red.opacity(0.08)
        }
        if isActive {
            return Color.green.opacity(0.12)
        }
        return .clear
    }

    private func cardBorderColor(for account: CodexAccount, isActive: Bool) -> Color {
        if account.lastUsageStatus == .accountIssue {
            return Color.red.opacity(0.34)
        }
        if isActive {
            return Color.green.opacity(0.22)
        }
        return Color.white.opacity(0.12)
    }

    private func clockText(fromUnixSeconds seconds: Int64) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(seconds)))
    }

    private func usageLine(for account: CodexAccount, minutes: Int, label: String) -> String? {
        let window: RateLimitWindow?
        if account.lastUsage?.primary?.windowMinutes == minutes {
            window = account.lastUsage?.primary
        } else if account.lastUsage?.secondary?.windowMinutes == minutes {
            window = account.lastUsage?.secondary
        } else {
            window = minutes == 300 ? account.lastUsage?.primary : account.lastUsage?.secondary
        }
        return storeUsageLine(for: window, label: label)
    }

    private func storeUsageLine(for window: RateLimitWindow?, label: String) -> String? {
        guard let window else { return nil }
        let remaining = max(0, min(100, Int((100 - window.usedPercent).rounded(.down))))

        let resetText: String
        if let resetsAt = window.resetsAt {
            resetText = " · 重置于 \(clockTextForReset(resetsAt))"
        } else {
            resetText = ""
        }

        return "\(label) 剩余 \(remaining)%\(resetText)"
    }

    private func clockTextForReset(_ unixSeconds: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(unixSeconds))
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")

        if calendar.isDateInToday(date) {
            formatter.dateFormat = "今天 HH:mm"
            return formatter.string(from: date)
        }

        if calendar.isDateInTomorrow(date) {
            formatter.dateFormat = "明天 HH:mm"
            return formatter.string(from: date)
        }

        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
    }

    private func usageBadge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12), in: Capsule())
    }

    private func planTag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.07), in: Capsule())
    }

    private func displayPlan(for account: CodexAccount) -> String? {
        if let plan = account.lastUsage?.planType ?? account.plan {
            return plan.capitalized
        }
        return nil
    }

    private func usageStatusLine(for account: CodexAccount) -> (text: String, tint: Color)? {
        switch account.lastUsageStatus {
        case .accountIssue:
            return (account.lastUsageErrorMessage ?? "认证失效，请重新登录", .red)
        case .unknown:
            return (account.lastUsageErrorMessage ?? "用量接口暂时不可用", .orange)
        default:
            return nil
        }
    }

    private func deleteButton(for account: CodexAccount, isActive: Bool) -> some View {
        Button(role: .destructive) {
            pendingAction = .deleteAccount(account)
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.red)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .help(isActive ? "删除当前激活账号后，将清空当前激活状态" : "删除本地账号快照")
    }

    private func confirmPendingAction(_ action: PendingAction) {
        pendingAction = nil
        DispatchQueue.main.async {
            switch action {
            case .switchAccount(let account):
                store.switchAccount(account)
            case .deleteAccount(let account):
                store.deleteAccount(account)
            }
        }
    }

    private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .medium))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }
}

private enum PendingAction {
    case switchAccount(CodexAccount)
    case deleteAccount(CodexAccount)

    var confirmTitle: String {
        switch self {
        case .switchAccount:
            return "确认切换"
        case .deleteAccount:
            return "确认删除"
        }
    }

    var buttonRole: ButtonRole? {
        switch self {
        case .switchAccount:
            return nil
        case .deleteAccount:
            return .destructive
        }
    }

    var backgroundColor: Color {
        switch self {
        case .switchAccount:
            return .blue
        case .deleteAccount:
            return .red
        }
    }

    func title(store: CodexAccountsStore) -> String {
        switch self {
        case .switchAccount:
            return "确认切换账号"
        case .deleteAccount:
            return "确认删除账号"
        }
    }

    @MainActor
    func message(store: CodexAccountsStore) -> String {
        switch self {
        case .switchAccount(let account):
            return "将切换到 \(account.email)。"
        case .deleteAccount(let account):
            return "将删除 \(account.email) 的本地快照，此操作不会删除远端账号。"
        }
    }
}
