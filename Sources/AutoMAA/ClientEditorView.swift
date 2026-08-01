import AppKit
import AutoMAAKit
import SwiftUI

struct ClientEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var client: ClientConfiguration
    @State private var confirmDeleteClient = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                connectionPanel
                accountsPanel
                lifecyclePanel
                deletePanel
            }
            .padding(28)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(client.name)
        .confirmationDialog("删除 \(client.name)？", isPresented: $confirmDeleteClient) {
            Button("删除客户端", role: .destructive) {
                model.deleteClient(client.id)
            }
        } message: {
            Text("该客户端及其全部账号配置会从 AutoMAA 中移除，不会影响游戏本身。")
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.maaAccent.opacity(0.12))
                Image(systemName: client.kind.symbol)
                    .font(.system(size: 29))
                    .foregroundStyle(Color.maaAccent)
            }
            .frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 5) {
                TextField("客户端名称", text: $client.name)
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.bold))
                Text("MAA · \(client.kind.maaClientType)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 4) {
                Button { model.moveClient(client.id, by: -1) } label: {
                    Image(systemName: "arrow.up")
                }
                .disabled(clientIndex == 0)
                Button { model.moveClient(client.id, by: 1) } label: {
                    Image(systemName: "arrow.down")
                }
                .disabled(clientIndex == model.configuration.clients.count - 1)
            }
            .buttonStyle(.borderless)
            .help("调整客户端执行顺序")
            Toggle("启用客户端", isOn: $client.enabled)
                .toggleStyle(.switch)
        }
    }

    private var connectionPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                Label("客户端与连接", systemImage: "cable.connector")
                    .font(.headline)
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                    GridRow {
                        Text("服务器")
                            .foregroundStyle(.secondary)
                        Picker("", selection: kindBinding) {
                            ForEach(ClientKind.allCases) { kind in
                                Text(kind.title).tag(kind)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                    }
                    GridRow {
                        Text("应用路径")
                            .foregroundStyle(.secondary)
                        HStack {
                            TextField(".app 路径", text: $client.appPath)
                                .textFieldStyle(.roundedBorder)
                            Button("选择…") { chooseApplication() }
                        }
                    }
                    GridRow {
                        Text("MaaTools")
                            .foregroundStyle(.secondary)
                        TextField("localhost:1717", text: $client.address)
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("Bundle ID")
                            .foregroundStyle(.secondary)
                        TextField("选择应用后自动读取", text: $client.bundleIdentifier)
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("MAA Profile")
                            .foregroundStyle(.secondary)
                        TextField("例如 client-1", text: $client.profileName)
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
                    Label("账号队列", systemImage: "person.2.fill")
                        .font(.headline)
                    Spacer()
                    Button {
                        model.addAccount(to: client.id)
                    } label: {
                        Label("添加账号", systemImage: "plus")
                    }
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
                                Text(account.name)
                                    .font(.callout.weight(.semibold))
                                Text(account.enabled ? "\(account.stepOrder.filter { account.isEnabled($0) }.count) 个步骤" : "已停用")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if client.accounts.filter(\.enabled).count > 1 && account.accountSelector.isEmpty {
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
                        HStack(spacing: 3) {
                            Button { model.moveAccount(clientID: client.id, accountID: account.id, by: -1) } label: {
                                Image(systemName: "arrow.up")
                            }
                            .disabled(index == 0)
                            Button { model.moveAccount(clientID: client.id, accountID: account.id, by: 1) } label: {
                                Image(systemName: "arrow.down")
                            }
                            .disabled(index == client.accounts.count - 1)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(11)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private var deletePanel: some View {
        HStack {
            Spacer()
            Button("删除这个客户端", role: .destructive) { confirmDeleteClient = true }
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
                Label("生命周期保护", systemImage: "shield.lefthalf.filled")
                    .font(.headline)
                Label("启动后等待 MaaTools 端口就绪", systemImage: "checkmark.circle.fill")
                Label("账号按上方顺序串行执行", systemImage: "checkmark.circle.fill")
                Label("结束后关闭客户端并确认端口释放", systemImage: "checkmark.circle.fill")
                Text("端口被未知进程占用、账号片段为空或客户端关闭失败时，流程会立即停止在安全位置。")
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
