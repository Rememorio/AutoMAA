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
                                      plans: model.configuration.plans, openEditor: openEditor)
                    .id(model.clientsSelection)
            } else {
                emptyDetail
            }
        }
        .workspaceToolbar(for: .clients, title: "客户端与账号", actions: [
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
        List(selection: Binding(get: { model.clientsSelection }, set: { selection in
            if let selection { model.clientsSelection = selection }
        })) {
            ForEach(Array(model.configuration.clients.enumerated()), id: \.element.id) { index, client in
                clientRow(client)
                    .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
                    .tag(ClientWorkspaceSelection.client(client.id))
                    .contextMenu { clientMenu(client, index: index) }
                ForEach(Array(client.accounts.enumerated()), id: \.element.id) { index, account in
                    accountRow(account, client: client)
                        .listRowInsets(EdgeInsets(top: 6, leading: 28, bottom: 6, trailing: 14))
                        .tag(ClientWorkspaceSelection.account(clientID: client.id, accountID: account.id))
                        .contextMenu { accountMenu(account, client: client, index: index) }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .accessibilityLabel("客户端与账号")
    }

    private func clientRow(_ client: ClientConfiguration) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(client.displayName).font(.body.weight(.semibold)).lineLimit(2)
                if client.displayName != client.kind.title {
                    Text(client.kind.title).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if !client.enabled { Image(systemName: "pause.circle").foregroundStyle(.secondary) }
        }
        .contentShape(Rectangle())
        .help(client.displayName)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(client.displayName)
        .accessibilityValue([client.displayName != client.kind.title ? client.kind.title : "",
                             client.enabled ? "" : "已停用"].filter { !$0.isEmpty }.joined(separator: "，"))
    }

    private func accountRow(_ account: AccountConfiguration, client: ClientConfiguration) -> some View {
        let active = client.enabled && account.enabled
        let state = client.enabled ? (account.enabled ? "" : "账号已停用") : "所属客户端已停用"
        return HStack(spacing: 7) {
            Image(systemName: "person").foregroundStyle(.secondary)
                .frame(width: 16).accessibilityHidden(true)
            Text(account.displayName).font(.body).lineLimit(2)
                .foregroundStyle(active ? .primary : .secondary)
            Spacer(minLength: 0)
            if !active { Image(systemName: "pause.circle").foregroundStyle(.secondary) }
        }
        .contentShape(Rectangle())
        .help([account.displayName, state].filter { !$0.isEmpty }.joined(separator: " · "))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(account.displayName)
        .accessibilityValue(state)
    }

    @ViewBuilder
    private var emptyDetail: some View {
        if model.configuration.clients.isEmpty {
            ContentUnavailableView {
                Label("还没有客户端", systemImage: "desktopcomputer")
            } actions: {
                Button("添加客户端…") { openEditor(.newClient) }
                    .disabled(model.isWorkflowRunning)
            }
        } else {
            ContentUnavailableView("选择客户端或账号", systemImage: "desktopcomputer")
        }
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
        case let .client(id, _):
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
        case let .client(id, _): model.deleteClient(id)
        case let .account(clientID, accountID): model.deleteAccount(clientID: clientID, accountID: accountID)
        default: break
        }
        deletion = nil
    }
}
