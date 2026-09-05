import AutoMAAKit
import SwiftUI

struct AccountEditorView: View {
    @EnvironmentObject private var model: AppModel
    let client: ClientConfiguration
    @Binding var account: AccountConfiguration
    @State private var confirmDelete = false

    var body: some View {
        AppPage(width: PageLayout.readingWidth) {
            accountHeader
            selectorPanel
            planPanel
            deletePanel
        }
        .navigationTitle(account.displayName)
        .confirmationDialog("删除 \(account.displayName)？", isPresented: $confirmDelete) {
            Button("删除账号", role: .destructive) {
                model.deleteAccount(clientID: client.id, accountID: account.id)
            }
        } message: {
            Text("只会删除 AutoMAA 中的配置，不会影响游戏账号。")
        }
    }

    private var accountHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            EntityIcon(symbol: "person.crop.circle")
            VStack(alignment: .leading, spacing: 5) {
                EditableDisplayNameField(label: "账号名称", placeholder: "例如：主账号", text: $account.name)
                Text("所属客户端 · \(client.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("启用账号", isOn: $account.enabled)
                .toggleStyle(.switch)
        }
    }

    private var selectorPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    SectionHeading(title: "账号切换", symbol: "person.text.rectangle")
                    Spacer()
                    if !client.kind.supportsAccountSwitching {
                        Text("不支持")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    } else if requiresSelector && account.accountSelector.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Label("必填", systemImage: "exclamationmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                    } else if !requiresSelector {
                        Text("可选")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                if client.kind.supportsAccountSwitching {
                    TextField("填写登录页能唯一匹配该账号的片段", text: $account.accountSelector)
                        .accessibilityLabel("账号匹配片段")
                        .textFieldStyle(.roundedBorder)
                    Text(requiresSelector
                         ? "同一客户端启用了多个账号，每个账号都必须填写不同且唯一的匹配片段。"
                         : "单账号可以留空；填写后 MAA 会在已登录账号中按该片段进行匹配。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("MAA 当前不支持\(client.kind.title)自动切换账号。请只启用一个账号，AutoMAA 会使用游戏当前已登录账号。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !account.accountSelector.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button("清空账号片段") {
                            account.accountSelector = ""
                        }
                    }
                }
            }
        }
    }

    private var planPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(title: "参与的自动化方案", symbol: "square.stack.3d.up.fill")
                Text("任务顺序和参数在方案中统一维护，账号这里只决定是否参与指定方案。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Divider()
                if model.configuration.plans.isEmpty {
                    Text("尚未创建自动化方案")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.configuration.plans) { plan in
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(Color.maaAccent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(plan.displayName)
                                    .font(.callout.weight(.medium))
                                Text(plan.includesAllEnabledAccounts ? "自动包含所有已启用账号" : "仅包含选中的账号")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: membershipBinding(plan.id))
                                .labelsHidden()
                                .accessibilityLabel("参与\(plan.displayName)")
                                .disabled(plan.includesAllEnabledAccounts)
                        }
                    }
                }
            }
        }
    }

    private var deletePanel: some View {
        HStack {
            Spacer()
            Button("删除账号", role: .destructive) { confirmDelete = true }
        }
        .padding(.top, 4)
    }

    private var requiresSelector: Bool {
        client.kind.supportsAccountSwitching && client.accounts.filter(\.enabled).count > 1
    }

    private func membershipBinding(_ planID: UUID) -> Binding<Bool> {
        Binding {
            guard let plan = model.configuration.plans.first(where: { $0.id == planID }) else { return false }
            return plan.includesAllEnabledAccounts || plan.accountIDs.contains(account.id)
        } set: { included in
            guard let index = model.configuration.plans.firstIndex(where: { $0.id == planID }),
                  !model.configuration.plans[index].includesAllEnabledAccounts
            else { return }
            if included {
                model.configuration.plans[index].accountIDs.insert(account.id)
            } else {
                model.configuration.plans[index].accountIDs.remove(account.id)
            }
        }
    }
}
