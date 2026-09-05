import AppKit
import AutoMAAKit
import SwiftUI

struct ClientEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var client: ClientConfiguration
    @State private var confirmDeleteClient = false

    var body: some View {
        AppPage(width: PageLayout.readingWidth) {
            header
            connectionPanel
            accountsPanel
            lifecyclePanel
            deletePanel
        }
        .navigationTitle(client.displayName)
        .confirmationDialog("删除 \(client.displayName)？", isPresented: $confirmDeleteClient) {
            Button("删除客户端", role: .destructive) {
                model.deleteClient(client.id)
            }
        } message: {
            Text("该客户端及其全部账号配置会从 AutoMAA 中移除，不会影响游戏本身。")
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            EntityIcon(symbol: client.kind.symbol)
            VStack(alignment: .leading, spacing: 5) {
                EditableDisplayNameField(label: "客户端名称", placeholder: "例如：晚间官服", text: $client.name)
                Text("\(client.kind.title) · MAA \(client.kind.maaClientType)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ReorderButtons(name: client.displayName, index: clientIndex, count: model.configuration.clients.count) {
                model.moveClient(client.id, by: $0)
            }
            Toggle("启用客户端", isOn: $client.enabled)
                .toggleStyle(.switch)
        }
    }

    private var connectionPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading(title: "客户端与连接", symbol: "cable.connector")
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                    GridRow {
                        Text("服务器")
                            .foregroundStyle(.secondary)
                        Picker("服务器", selection: kindBinding) {
                            ForEach(ClientKind.allCases) { kind in
                                Text(kind.title).tag(kind)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GridRow {
                        Text("应用路径")
                            .foregroundStyle(.secondary)
                        HStack {
                            TextField(".app 路径", text: $client.appPath)
                                .accessibilityLabel("应用路径")
                                .textFieldStyle(.roundedBorder)
                            Button("选择…") { chooseApplication() }
                        }
                    }
                    GridRow {
                        Text("MaaTools")
                            .foregroundStyle(.secondary)
                        TextField("127.0.0.1:1717", text: $client.address)
                            .accessibilityLabel("MaaTools 地址")
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("Bundle ID")
                            .foregroundStyle(.secondary)
                        TextField("选择应用后自动读取", text: $client.bundleIdentifier)
                            .accessibilityLabel("Bundle ID")
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("MAA Profile")
                            .foregroundStyle(.secondary)
                        TextField("例如 client-1", text: $client.profileName)
                            .accessibilityLabel("MAA Profile")
                            .textFieldStyle(.roundedBorder)
                    }
                }
                Text("每个客户端使用独立 Profile。多个客户端可以共用端口，因为流程会在启动下一项前确认当前连接已经释放。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var accountsPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionHeading(title: "账号队列", symbol: "person.2.fill")
                    Spacer()
                    Button {
                        model.addAccount(to: client.id)
                    } label: {
                        Label("添加账号", systemImage: "plus")
                    }
                }
                if client.accounts.isEmpty {
                    Text("还没有账号。添加后可在自动化方案中安排任务。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                }
                ForEach(Array(client.accounts.enumerated()), id: \.element.id) { index, account in
                    HStack(spacing: 8) {
                        Button {
                            model.selection = .account(client.id, account.id)
                        } label: {
                            HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.caption.bold().monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 22, height: 22)
                                .background(Color.primary.opacity(0.05), in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(account.displayName)
                                    .font(.callout.weight(.semibold))
                                Text(account.enabled ? "由自动化方案安排" : "已停用")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if !client.kind.supportsAccountSwitching,
                               client.accounts.filter(\.enabled).count > 1 {
                                Text("不支持多账号切换")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            } else if client.kind.supportsAccountSwitching,
                                      client.accounts.filter(\.enabled).count > 1,
                                      account.accountSelector.isEmpty {
                                Text("缺少账号片段")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        ReorderButtons(name: account.displayName, index: index, count: client.accounts.count) {
                            model.moveAccount(clientID: client.id, accountID: account.id, by: $0)
                        }
                    }
                    .padding(11)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                }
                if !client.kind.supportsAccountSwitching {
                    Text("MAA 当前不支持\(client.kind.title)自动切换账号；请只启用一个账号，并在游戏中保持该账号已登录。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var deletePanel: some View {
        HStack {
            Spacer()
            Button("删除客户端", role: .destructive) { confirmDeleteClient = true }
        }
        .padding(.top, 4)
    }

    private var clientIndex: Int {
        model.configuration.clients.firstIndex(where: { $0.id == client.id }) ?? 0
    }

    private var kindBinding: Binding<ClientKind> {
        Binding(
            get: { client.kind },
            set: { newKind in
                let oldDefault = client.kind.defaultBundleIdentifier
                if client.bundleIdentifier.isEmpty || client.bundleIdentifier == oldDefault {
                    client.bundleIdentifier = newKind.defaultBundleIdentifier
                }
                client.kind = newKind
            }
        )
    }

    private var lifecyclePanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 9) {
                SectionHeading(title: "生命周期保护", symbol: "shield.lefthalf.filled")
                Label("启动后等待 MaaTools 端口就绪", systemImage: "checkmark.circle.fill")
                Label(client.kind.supportsAccountSwitching ? "账号按上方顺序串行执行" : "使用游戏当前已登录的单个账号", systemImage: "checkmark.circle.fill")
                Label("结束后关闭客户端并确认端口释放", systemImage: "checkmark.circle.fill")
                Text(client.kind.supportsAccountSwitching
                     ? "端口被未知进程占用、账号片段为空或客户端关闭失败时，流程会立即停止在安全位置。"
                     : "启用多个账号、填写账号片段、端口被未知进程占用或客户端关闭失败时，流程会在安全位置停止。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 3)
            }
            .font(.callout)
        }
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(filePath: client.appPath).deletingLastPathComponent()
        if panel.runModal() == .OK, let url = panel.url {
            client.appPath = url.path
            if let identifier = Bundle(url: url)?.bundleIdentifier {
                client.bundleIdentifier = identifier
            }
        }
    }
}
