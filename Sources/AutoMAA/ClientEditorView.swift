import AppKit
import AutoMAAKit
import SwiftUI

struct ClientEditorView: View {
    @Binding var client: ClientConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            EditorFieldRow(title: "名称") {
                TextField("客户端名称", text: $client.name).accessibilityLabel("客户端名称")
                    .frame(maxWidth: FormWidth.shortText)
            }
            EditorFieldRow(title: "服务器") {
                Picker("服务器", selection: kindBinding) {
                    ForEach(ClientKind.allCases) { kind in Text(kind.title).tag(kind) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize(horizontal: true, vertical: false)
            }
            EditorFieldRow(title: "游戏应用") {
                HStack(spacing: 8) {
                    TextField("选择 .app", text: $client.appPath)
                        .accessibilityLabel("应用路径")
                        .help(client.appPath.isEmpty ? "选择要运行的游戏应用" : client.appPath)
                    ActionTextButton(title: "选择应用…", symbol: "folder", help: "选择游戏应用…", action: chooseApplication)
                }
            }
            EditorFieldRow(title: "") {
                Toggle("启用客户端", isOn: $client.enabled)
            }
            Divider()
            DisclosureGroup("连接详情") {
                VStack(alignment: .leading, spacing: 12) {
                    EditorFieldRow(title: "MaaTools") {
                        TextField("连接地址", text: $client.address).accessibilityLabel("MaaTools 地址")
                            .frame(maxWidth: FormWidth.shortText)
                    }
                    EditorFieldRow(title: "Bundle ID") {
                        TextField("选择应用后自动读取", text: $client.bundleIdentifier).accessibilityLabel("Bundle ID")
                    }
                    EditorFieldRow(title: "MAA Profile") {
                        TextField("独立 Profile 名称", text: $client.profileName).accessibilityLabel("MAA Profile")
                            .frame(maxWidth: FormWidth.shortText)
                    }
                }.textFieldStyle(.roundedBorder).padding(.top, 4)
            }
            if !client.kind.supportsAccountSwitching {
                Text("该服务器仅支持游戏当前已登录的单个账号。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .textFieldStyle(.roundedBorder)
        .toggleStyle(.checkbox)
    }

    private var kindBinding: Binding<ClientKind> {
        Binding(get: { client.kind }, set: { kind in
            let previous = client.kind.defaultBundleIdentifier
            if client.bundleIdentifier.isEmpty || client.bundleIdentifier == previous {
                client.bundleIdentifier = kind.defaultBundleIdentifier
            }
            client.kind = kind
        })
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if !client.appPath.isEmpty { panel.directoryURL = URL(filePath: client.appPath).deletingLastPathComponent() }
        if panel.runModal() == .OK, let url = panel.url {
            client.appPath = url.path
            if let identifier = Bundle(url: url)?.bundleIdentifier { client.bundleIdentifier = identifier }
        }
    }
}
