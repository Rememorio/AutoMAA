import AutoMAAKit
import SwiftUI

struct AccountEditorView: View {
    @EnvironmentObject private var model: AppModel
    let client: ClientConfiguration
    @Binding var account: AccountConfiguration
    @Binding var planIDs: Set<UUID>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            EditorFieldRow(title: "客户端") {
                Text(client.displayName).textSelection(.enabled)
            }
            EditorFieldRow(title: "名称") {
                TextField("账号名称", text: $account.name)
                    .textFieldStyle(.roundedBorder).accessibilityLabel("账号名称")
                    .frame(maxWidth: FormWidth.shortText)
            }
            EditorFieldRow(title: "") {
                Toggle("启用账号", isOn: $account.enabled)
            }
            Divider()
            if client.kind.supportsAccountSwitching {
                EditorFieldRow(title: "匹配片段") {
                    TextField("登录页中的唯一片段", text: $account.accountSelector)
                        .textFieldStyle(.roundedBorder).accessibilityLabel("账号匹配片段")
                        .frame(maxWidth: FormWidth.shortText)
                }
                Text("单账号可留空；同一客户端启用多个账号时，需要各自唯一的匹配片段。")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.leading, 92)
            } else {
                Text("使用游戏当前已登录账号；该客户端只能启用一个账号。")
                    .font(.callout).foregroundStyle(.secondary)
                if !account.accountSelector.isEmpty {
                    Button("清空账号片段") { account.accountSelector = "" }
                }
            }
            Divider()
            Text("参与的自动化方案")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            if model.configuration.plans.isEmpty {
                Text("尚未创建自动化方案").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(model.configuration.plans) { plan in
                Toggle(isOn: Binding(get: { plan.includesAllEnabledAccounts || planIDs.contains(plan.id) }, set: {
                    if $0 { planIDs.insert(plan.id) } else { planIDs.remove(plan.id) }
                })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plan.displayName)
                        if plan.includesAllEnabledAccounts {
                            Text("自动包含所有已启用账号").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }.disabled(plan.includesAllEnabledAccounts)
            }
        }
        .toggleStyle(.checkbox)
    }
}
