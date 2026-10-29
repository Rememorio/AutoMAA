import AutoMAAKit
import SwiftUI

enum EntityEditorRequest: Identifiable, Equatable {
    case newClient
    case client(UUID)
    case newAccount(UUID)
    case account(UUID, UUID)

    var id: String {
        switch self {
        case .newClient: "new-client"
        case let .client(id): "client-\(id)"
        case let .newAccount(id): "new-account-\(id)"
        case let .account(client, account): "account-\(client)-\(account)"
        }
    }
    var isNew: Bool {
        switch self { case .newClient, .newAccount: true; default: false }
    }
    var isClient: Bool {
        switch self { case .newClient, .client: true; default: false }
    }
    var title: String { (isNew ? "添加" : "编辑") + (isClient ? "客户端" : "账号") }
}

struct EntityEditorSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let request: EntityEditorRequest
    @State private var client: ClientConfiguration?
    @State private var account: AccountConfiguration?
    @State private var planIDs: Set<UUID> = []
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(request.title).font(.headline)
                Spacer()
                if model.isWorkflowRunning { Text("运行中只读").font(.caption).foregroundStyle(.secondary) }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            Divider()
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let error {
                            Label(error, systemImage: "exclamationmark.circle")
                                .foregroundStyle(.red).font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if request.isClient, let binding = Binding($client) {
                            ClientEditorView(client: binding)
                        } else if let client, let binding = Binding($account) {
                            AccountEditorView(client: client, account: binding, planIDs: $planIDs)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
                    .id("formContent")
                    .disabled(model.isWorkflowRunning)
                }
                .onChange(of: error) { _, message in
                    if message != nil { reader.scrollTo("formContent", anchor: .top) }
                }
            }
            Divider()
            HStack(spacing: 12) {
                Spacer()
                Button { dismiss() } label: {
                    Text(model.isWorkflowRunning ? "关闭" : "取消").frame(minWidth: 56)
                }.keyboardShortcut(.cancelAction)
                Button(action: save) {
                    Text(request.isNew ? "添加" : "保存").frame(minWidth: 56)
                }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(.maaAction)
                    .disabled(model.isWorkflowRunning || client == nil || (!request.isClient && account == nil))
            }.padding(.horizontal, 24).padding(.vertical, 16)
        }
        .frame(width: 520, height: 480)
        .focusedSceneValue(\.workspaceActive, false)
        .disclosureGroupStyle(FullWidthDisclosureStyle())
        .onAppear(perform: loadDraft)
    }

    private func loadDraft() {
        guard client == nil else { return }
        switch request {
        case .newClient: client = model.newClientDraft()
        case let .client(id): client = model.configuration.clients.first { $0.id == id }
        case let .newAccount(clientID):
            client = model.configuration.clients.first { $0.id == clientID }
            account = model.newAccountDraft(clientID: clientID)
        case let .account(clientID, accountID):
            client = model.configuration.clients.first { $0.id == clientID }
            account = client?.accounts.first { $0.id == accountID }
        }
        if let account {
            planIDs = Set(model.configuration.plans.filter { $0.includesAllEnabledAccounts || $0.accountIDs.contains(account.id) }.map(\.id))
        }
        if client == nil || (!request.isClient && account == nil) { error = "配置已被移除，请关闭后重新选择。" }
    }

    private func save() {
        guard let client else { return }
        if request.isClient {
            error = model.saveClientDraft(client, isNew: request.isNew)
        } else if let account {
            error = model.saveAccountDraft(account, clientID: client.id, isNew: request.isNew, planIDs: planIDs)
        } else { return }
        if error == nil { dismiss() }
    }
}
