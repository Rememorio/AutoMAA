import AutoMAAKit
import SwiftUI

struct ClientsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var deletion: EntityEditorRequest?

    private var selectedClient: ClientConfiguration? {
        guard let selection = model.clientsSelection else { return nil }
        return model.configuration.clients.first { $0.id == selection.clientID }
    }

    private var selectedAccount: AccountConfiguration? {
        guard case let .account(_, accountID) = model.clientsSelection else { return nil }
        return selectedClient?.accounts.first { $0.id == accountID }
    }

    var body: some View {
        WorkspaceColumns {
            clientList
        } detail: {
            if let client = selectedClient {
                ClientWorkspaceDetail(client: client, account: selectedAccount,
                                      plans: model.configuration.plans)
            } else {
                emptyDetail
            }
        }
        .workspaceToolbar(title: "客户端与账号", actions: [
            .init(id: "clients.add", title: "添加客户端", symbol: "plus", isEnabled: !model.isWorkflowRunning,
                  handler: { openEditor(.newClient) })
        ], detailActions: detailActions)
        .confirmationDialog("\(deletionAction)？", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } })) {
            Button(deletionAction, role: .destructive, action: delete)
            Button("取消", role: .cancel) { deletion = nil }
        } message: {
            Text(deletionMessage)
        }
    }

    private var clientList: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("客户端与账号").font(.subheadline.weight(.medium))
                Text("\(model.configuration.clients.count) 个客户端 · \(model.activeAccountCount) 个账号已启用")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18).padding(.vertical, 12)
            Divider()
            List(selection: Binding(get: { model.clientsSelection }, set: { selection in
                if let selection { model.clientsSelection = selection }
            })) {
                ForEach(Array(model.configuration.clients.enumerated()), id: \.element.id) { index, client in
                    Section {
                        clientRow(client)
                            .tag(ClientWorkspaceSelection.client(client.id))
                            .contextMenu { clientMenu(client, index: index) }
                        ForEach(Array(client.accounts.enumerated()), id: \.element.id) { index, account in
                            accountRow(account, client: client)
                                .tag(ClientWorkspaceSelection.account(clientID: client.id, accountID: account.id))
                                .contextMenu { accountMenu(account, client: client, index: index) }
                        }
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .overlay {
                if model.configuration.clients.isEmpty {
                    Text("添加客户端后，账号会显示在这里。")
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(18)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, 12).allowsHitTesting(false)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func clientRow(_ client: ClientConfiguration) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "desktopcomputer")
                .foregroundStyle(client.enabled ? Color.maaAccent : .secondary)
                .frame(width: 18).padding(.top, 2).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(client.displayName).font(.callout.weight(.semibold)).lineLimit(2)
                Text(client.enabled ? "\(client.kind.title) · \(client.accounts.count) 个账号" : "已停用 · \(client.kind.title)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .help(client.displayName)
    }

    private func accountRow(_ account: AccountConfiguration, client: ClientConfiguration) -> some View {
        HStack(spacing: 8) {
            Image(systemName: account.enabled ? "person.crop.circle" : "person.crop.circle.badge.xmark")
                .foregroundStyle(.secondary).frame(width: 18).accessibilityHidden(true)
            Text(account.displayName).font(.callout).lineLimit(2)
                .foregroundStyle(account.enabled && client.enabled ? .primary : .secondary)
            Spacer(minLength: 0)
        }
        .padding(.leading, 26).padding(.vertical, 6)
        .help(account.displayName + (account.enabled ? "" : " · 已停用"))
        .accessibilityLabel(account.displayName + (account.enabled ? "" : "，已停用"))
    }

    private var emptyDetail: some View {
        ContentUnavailableView(model.configuration.clients.isEmpty ? "还没有客户端" : "选择客户端或账号",
                               systemImage: "desktopcomputer",
                               description: Text(model.configuration.clients.isEmpty
                                    ? "从中列顶部添加游戏应用，再配置执行账号。" : "在中列查看客户端配置与账号信息。"))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var detailActions: [WorkspaceToolbarAction] {
        guard let client = selectedClient,
              let clientIndex = model.configuration.clients.firstIndex(where: { $0.id == client.id }) else { return [] }
        let request: EntityEditorRequest = selectedAccount.map { .account(client.id, $0.id) } ?? .client(client.id)
        let title = selectedAccount.map { "编辑账号「\($0.displayName)」…" } ?? "编辑客户端「\(client.displayName)」…"
        let menu: [WorkspaceToolbarMenuItem]
        if let account = selectedAccount, let index = client.accounts.firstIndex(where: { $0.id == account.id }) {
            menu = [
                .action("上移账号", isEnabled: !model.isWorkflowRunning && index > 0) { moveAccount(account, client: client, by: -1) },
                .action("下移账号", isEnabled: !model.isWorkflowRunning && index < client.accounts.count - 1) { moveAccount(account, client: client, by: 1) },
                .separator,
                .action("删除账号…", isEnabled: !model.isWorkflowRunning) { deletion = request }
            ]
        } else {
            menu = [
                .action("上移客户端", isEnabled: !model.isWorkflowRunning && clientIndex > 0) { moveClient(client, by: -1) },
                .action("下移客户端", isEnabled: !model.isWorkflowRunning && clientIndex < model.configuration.clients.count - 1) { moveClient(client, by: 1) },
                .separator,
                .action("删除客户端…", isEnabled: !model.isWorkflowRunning) { deletion = request }
            ]
        }
        return [
            .init(id: "clients.account.add", title: "为「\(client.displayName)」添加账号…", symbol: "person.badge.plus",
                  isEnabled: !model.isWorkflowRunning, handler: { openEditor(.newAccount(client.id)) }),
            .init(id: "clients.edit", title: title, symbol: "pencil", isEnabled: !model.isWorkflowRunning,
                  handler: { openEditor(request) }),
            .init(id: "clients.more", title: selectedAccount == nil ? "客户端操作" : "账号操作", symbol: "ellipsis",
                  isEnabled: !model.isWorkflowRunning, menu: menu)
        ]
    }

    @ViewBuilder
    private func clientMenu(_ client: ClientConfiguration, index: Int) -> some View {
        Group {
            Button("添加账号…") { openEditor(.newAccount(client.id)) }
            Button("编辑客户端…") { openEditor(.client(client.id)) }
            Divider()
            Button("上移客户端") { moveClient(client, by: -1) }.disabled(index == 0)
            Button("下移客户端") { moveClient(client, by: 1) }.disabled(index == model.configuration.clients.count - 1)
            Divider()
            Button("删除客户端…", role: .destructive) { deletion = .client(client.id) }
        }
        .disabled(model.isWorkflowRunning)
    }

    @ViewBuilder
    private func accountMenu(_ account: AccountConfiguration, client: ClientConfiguration, index: Int) -> some View {
        Group {
            Button("编辑账号…") { openEditor(.account(client.id, account.id)) }
            Divider()
            Button("上移账号") { moveAccount(account, client: client, by: -1) }.disabled(index == 0)
            Button("下移账号") { moveAccount(account, client: client, by: 1) }.disabled(index == client.accounts.count - 1)
            Divider()
            Button("删除账号…", role: .destructive) { deletion = .account(client.id, account.id) }
        }
        .disabled(model.isWorkflowRunning)
    }

    private func openEditor(_ request: EntityEditorRequest) {
        guard !model.isWorkflowRunning else { return }
        model.entityEditor = request
    }

    private func moveClient(_ client: ClientConfiguration, by offset: Int) {
        guard !model.isWorkflowRunning else { return }
        model.moveClient(client.id, by: offset)
    }

    private func moveAccount(_ account: AccountConfiguration, client: ClientConfiguration, by offset: Int) {
        guard !model.isWorkflowRunning else { return }
        model.moveAccount(clientID: client.id, accountID: account.id, by: offset)
    }

    private var deletionAction: String { deletion?.isClient == true ? "删除客户端" : "删除账号" }

    private var deletionMessage: String {
        switch deletion {
        case let .client(id):
            let name = model.configuration.clients.first { $0.id == id }?.displayName ?? "客户端"
            return "移除「\(name)」及其全部账号配置，不会删除游戏应用。"
        case let .account(clientID, accountID):
            let name = model.configuration.clients.first { $0.id == clientID }?.accounts.first { $0.id == accountID }?.displayName ?? "账号"
            return "移除「\(name)」的 AutoMAA 配置，不会影响游戏账号。"
        default: return "移除所选配置。"
        }
    }

    private func delete() {
        guard !model.isWorkflowRunning else { return }
        switch deletion {
        case let .client(id): model.deleteClient(id)
        case let .account(clientID, accountID): model.deleteAccount(clientID: clientID, accountID: accountID)
        default: break
        }
        deletion = nil
    }
}
