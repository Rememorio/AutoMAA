import AutoMAAKit
import SwiftUI

struct ClientWorkspaceDetail: View {
    let client: ClientConfiguration
    let account: AccountConfiguration?
    let plans: [AutomationPlan]

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Label(account?.displayName ?? client.displayName,
                      systemImage: account == nil ? "desktopcomputer" : "person.crop.circle")
                    .font(.headline).lineLimit(1)
                    .help(account?.displayName ?? client.displayName)
                Text(account == nil ? "\(client.kind.title) · \(client.accounts.count) 个账号" : client.displayName)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    .help(client.displayName)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 14)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let account { accountDetails(account) }
                    else { clientDetails }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var clientDetails: some View {
        Group {
            ClientDetailSection(title: "运行配置") {
                ClientDetailValue(title: "启用状态", value: client.enabled ? "已启用" : "已停用")
                ClientDetailValue(title: "账号切换", value: client.kind.supportsAccountSwitching ? "自动切换账号" : "使用游戏当前登录账号")
                if client.accounts.isEmpty {
                    Text("还没有账号，点击顶部的添加账号按钮开始配置。")
                        .font(.caption).foregroundStyle(.secondary)
                } else if !client.kind.supportsAccountSwitching {
                    Text("该服务器仅支持一个已启用账号。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            ClientDetailSection(title: "游戏应用") {
                if client.appPath.isEmpty {
                    Label("尚未选择游戏应用", systemImage: "exclamationmark.circle")
                        .font(.callout).foregroundStyle(.orange)
                    Text("点击顶部的编辑按钮，选择要运行的游戏应用。")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(client.appPath).font(.callout).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ClientDetailSection(title: "连接详情") {
                ClientDetailValue(title: "MaaTools", value: client.address)
                ClientDetailValue(title: "MAA Profile", value: client.profileName)
                ClientDetailValue(title: "Bundle ID", value: client.bundleIdentifier.isEmpty ? "尚未设置" : client.bundleIdentifier)
            }
        }
    }

    private func accountDetails(_ account: AccountConfiguration) -> some View {
        let participatingPlans = plans.filter { $0.includesAllEnabledAccounts || $0.accountIDs.contains(account.id) }
        let hasSelector = !account.accountSelector.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return Group {
            ClientDetailSection(title: "运行配置") {
                ClientDetailValue(title: "启用状态", value: account.enabled ? "已启用" : "已停用")
                ClientDetailValue(title: "服务器", value: client.kind.title)
                if !client.enabled {
                    Text("所属客户端已停用，启用客户端后才会执行此账号。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            ClientDetailSection(title: "登录方式") {
                if client.kind.supportsAccountSwitching {
                    ClientDetailValue(title: "账号匹配", value: hasSelector ? "已设置匹配片段" : "未设置匹配片段")
                    Text(!hasSelector
                         ? "单账号可使用当前登录状态；启用多个账号时需分别设置唯一匹配片段。"
                         : "运行时通过游戏登录页中的唯一片段识别账号，片段仅在编辑时显示。")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("使用游戏当前已登录账号，不自动切换账号。")
                        .font(.callout)
                }
            }
            ClientDetailSection(title: "参与的自动化方案") {
                if participatingPlans.isEmpty {
                    Text("尚未加入方案，可通过顶部编辑按钮调整。")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(participatingPlans) { plan in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "checklist").foregroundStyle(.secondary).accessibilityHidden(true)
                            Text(plan.displayName).font(.callout).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !account.enabled {
                        Text("启用账号后参与以上方案。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct ClientDetailSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            content
        }
    }
}

private struct ClientDetailValue: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).font(.callout).foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)
            Text(value).font(.callout).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
