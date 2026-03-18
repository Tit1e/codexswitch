//
//  MenuContentView.swift
//  codexswitch
//
//  Created by Codex on 2026/3/18.
//

import SwiftUI

struct MenuContentView: View {
    @ObservedObject var store: CodexAccountsStore
    @State private var editingAccountKey: String?
    @State private var aliasDraft = ""
    @FocusState private var focusedAccountKey: String?

    var body: some View {
        VStack(spacing: 14) {
            header

            actionBar

            if store.accounts.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(store.groupedAccounts(), id: \.email) { group in
                        Text(group.email)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        ForEach(group.accounts) { account in
                            accountCard(for: account)
                        }
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
                    Text("当前：\(store.workspaceName(for: active))")
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

            Button("退出应用", role: .destructive) {
                store.quit()
            }
        }
    }

    private func accountCard(for account: CodexAccount) -> some View {
        let isEditing = editingAccountKey == account.accountKey
        let isActive = store.activeAccountKey == account.accountKey
        let isTeamAccount = isTeam(account)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 8) {
                        titleView(for: account, isEditing: isEditing, isTeamAccount: isTeamAccount)

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
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    if !isEditing {
                        store.switchAccount(account)
                    }
                }
            }

        }
        .padding(12)
        .background(cardBackground(isActive: isActive), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isActive ? Color.green.opacity(0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(cardBorderColor(isActive: isActive), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func titleView(for account: CodexAccount, isEditing: Bool, isTeamAccount: Bool) -> some View {
        if isTeamAccount {
            workspaceTitle(for: account, isEditing: isEditing)
                .onTapGesture {
                    if !isEditing {
                        editingAccountKey = account.accountKey
                        aliasDraft = account.alias.isEmpty ? "" : account.alias
                        focusedAccountKey = account.accountKey
                    }
                }
        } else {
            HStack(spacing: 6) {
                Text(account.email)
                    .font(.system(size: 13, weight: .semibold))
                    .multilineTextAlignment(.leading)
                if let plan = displayPlan(for: account) {
                    planTag(plan)
                }
            }
        }
    }

    @ViewBuilder
    private func workspaceTitle(for account: CodexAccount, isEditing: Bool) -> some View {
        if isEditing {
            TextField("工作区名称", text: $aliasDraft)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, weight: .semibold))
                .focused($focusedAccountKey, equals: account.accountKey)
                .onSubmit {
                    store.saveWorkspaceAlias(aliasDraft, for: account)
                    editingAccountKey = nil
                    focusedAccountKey = nil
                }
        } else {
            Text(store.workspaceName(for: account))
                .font(.system(size: 13, weight: .semibold))
                .multilineTextAlignment(.leading)
        }
    }

    private func cardBackground(isActive: Bool) -> some ShapeStyle {
        if isActive {
            return AnyShapeStyle(.ultraThinMaterial)
        }
        return AnyShapeStyle(.thinMaterial)
    }

    private func cardBorderColor(isActive: Bool) -> Color {
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

    private func isTeam(_ account: CodexAccount) -> Bool {
        guard let plan = displayPlan(for: account)?.lowercased() else { return false }
        return plan == "team"
    }

    private func displayPlan(for account: CodexAccount) -> String? {
        if let plan = account.lastUsage?.planType ?? account.plan {
            return plan.capitalized
        }
        return nil
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
