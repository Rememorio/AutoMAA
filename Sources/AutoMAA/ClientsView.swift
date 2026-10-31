import AutoMAAKit
import SwiftUI

struct ClientsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var deletion: EntityEditorRequest?

    var body: some View {
        Group {
            if model.configuration.clients.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 28)).foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("还没有客户端").font(.headline)
                    Text("添加游戏应用后，再配置执行账号。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("添加客户端") { model.entityEditor = .newClient }
                        .buttonStyle(.borderedProminent).tint(.maaAction)
                        .controlSize(.small).fixedSize()
                        .disabled(model.isWorkflowRunning)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                clientList
            }
        }
        .workspaceToolbar(title: "客户端与账号") {
            if !model.configuration.clients.isEmpty {
                Button { model.entityEditor = .newClient } label: {
                    Label("添加客户端", systemImage: "plus")
                }
                .help("添加客户端")
                .disabled(model.isWorkflowRunning)
            }
        } detail: {
            EmptyView()
        }
        .confirmationDialog("\(deletionAction)？", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } })) {
            Button(deletionAction, role: .destructive, action: delete)
            Button("取消", role: .cancel) { deletion = nil }
        } message: {
            Text(deletionMessage)
        }
    }

    private var clientList: some View {
        AppPage(width: PageLayout.listWidth) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(model.configuration.clients.count) 个客户端 · 已启用 \(model.activeAccountCount) 个账号")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 20)
                ForEach(Array(model.configuration.clients.enumerated()), id: \.element.id) { index, client in
                    if index > 0 { Divider().padding(.vertical, 24) }
                    clientSection(client, index: index)
                }
            }
            .padding(.vertical, 12)
        }
    }

    private func clientSection(_ client: ClientConfiguration, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 22)).foregroundStyle(.secondary)
                    .frame(width: 28).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(client.displayName).font(.system(size: 16, weight: .semibold))
                        .lineLimit(2).help(client.displayName)
                    Text("\(client.kind.title) · \(client.accounts.count) 个账号\(client.enabled ? "" : " · 已停用")")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 4) {
                    ActionTextButton(title: "添加账号", symbol: "person.badge.plus", help: "为「\(client.displayName)」添加账号…") {
                        model.entityEditor = .newAccount(client.id)
                    }
                    ActionIconButton(title: "编辑客户端「\(client.displayName)」…", symbol: "pencil") {
                        model.entityEditor = .client(client.id)
                    }
                    clientMenu(client, index: index)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                if client.appPath.isEmpty {
                    Label("尚未选择游戏应用", systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.orange)
                        .padding(.bottom, 10)
                }
                if client.accounts.isEmpty {
                    Text("还没有账号，点击“添加账号”开始配置。")
                        .font(.callout).foregroundStyle(.secondary)
                        .padding(.vertical, 10)
                } else {
                    ForEach(Array(client.accounts.enumerated()), id: \.element.id) { accountIndex, account in
                        if accountIndex > 0 { Divider().padding(.leading, 32) }
                        accountRow(account, client: client, index: accountIndex)
                    }
                }
            }
            .padding(.leading, 40)
        }
        .disabled(model.isWorkflowRunning)
    }

    private func accountRow(_ account: AccountConfiguration, client: ClientConfiguration, index: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 16)).foregroundStyle(.secondary)
                .frame(width: 22).accessibilityHidden(true)
            Text(account.displayName).font(.callout)
                .lineLimit(2).help(account.displayName)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !account.enabled { Text("已停用").font(.caption).foregroundStyle(.secondary) }
            HStack(spacing: 4) {
                ActionIconButton(title: "编辑账号「\(account.displayName)」…", symbol: "pencil") {
                    model.entityEditor = .account(client.id, account.id)
                }
                ActionIconMenu(title: "账号「\(account.displayName)」的更多操作") {
                    Button("上移") { model.moveAccount(clientID: client.id, accountID: account.id, by: -1) }
                        .disabled(index == 0)
                    Button("下移") { model.moveAccount(clientID: client.id, accountID: account.id, by: 1) }
                        .disabled(index == client.accounts.count - 1)
                    Divider()
                    Button("删除账号…", role: .destructive) { deletion = .account(client.id, account.id) }
                }
            }
        }
        .frame(minHeight: 40)
        .padding(.vertical, 2)
    }

    private func clientMenu(_ client: ClientConfiguration, index: Int) -> some View {
        ActionIconMenu(title: "客户端「\(client.displayName)」的更多操作") {
            Button("上移") { model.moveClient(client.id, by: -1) }.disabled(index == 0)
            Button("下移") { model.moveClient(client.id, by: 1) }.disabled(index == model.configuration.clients.count - 1)
            Divider()
            Button("删除客户端…", role: .destructive) { deletion = .client(client.id) }
        }
    }

    private var deletionAction: String {
        deletion?.isClient == true ? "删除客户端" : "删除账号"
    }

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
        model.selection = .clients
        deletion = nil
    }
}
