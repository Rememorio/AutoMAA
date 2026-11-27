import AppKit
import AutoMAAKit
import SwiftUI

struct ClientWorkspaceDetail: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var application = ClientApplicationAppearance()
    let client: ClientConfiguration
    let account: AccountConfiguration?
    let plans: [AutomationPlan]
    let openEditor: (EntityEditorRequest) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let account { accountDetails(account) }
                    else { clientDetails }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .disclosureGroupStyle(FullWidthDisclosureStyle())
        .task(id: client.appPath) { refreshApplication() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshApplication() }
        }
    }

    private func refreshApplication() {
        if account == nil { application = ClientApplicationAppearance.read(at: client.appPath) }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if account != nil {
                Image(systemName: "person.crop.circle").font(.system(size: 28, weight: .regular))
                    .foregroundStyle(.secondary).frame(width: 32, height: 32)
                    .accessibilityHidden(true)
            } else if let icon = application.icon {
                Image(nsImage: icon).resizable().interpolation(.high).scaledToFit()
                    .frame(width: 32, height: 32)
                    .clipShape(.rect(cornerRadius: 7, style: .continuous))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(account?.displayName ?? client.displayName)
                    .font(.title3.weight(.semibold)).lineLimit(2)
                    .help(account?.displayName ?? client.displayName)
                    .accessibilityAddTraits(.isHeader)
                if account != nil {
                    Text(client.displayName == client.kind.title ? client.kind.title : "\(client.displayName) · \(client.kind.title)")
                        .font(.callout).foregroundStyle(.secondary)
                } else if client.displayName != client.kind.title {
                    Text(client.kind.title).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    @ViewBuilder private var clientDetails: some View {
        let enabledAccounts = client.accounts.filter(\.enabled)
        if !client.enabled { paused("客户端已停用，所属账号将跳过运行") }
        ClientDetailRow(title: "游戏应用") {
            if client.appPath.isEmpty {
                chooseApplicationButton("选择游戏应用…")
            } else if application.isMissing {
                VStack(alignment: .leading, spacing: 3) {
                    Text("找不到 \(URL(filePath: client.appPath).lastPathComponent)").foregroundStyle(.orange)
                    chooseApplicationButton("重新选择游戏应用…")
                }
            } else {
                Text(URL(filePath: client.appPath).lastPathComponent)
                    .textSelection(.enabled).help(client.appPath)
            }
        }
        Divider()
        ClientDetailRow(title: "启用账号") {
            if client.accounts.isEmpty {
                ActionTextButton(title: "添加账号…", symbol: "person.badge.plus") { openEditor(.newAccount(client.id)) }
                    .disabled(model.isWorkflowRunning)
            } else if enabledAccounts.isEmpty {
                Text("暂无启用账号").foregroundStyle(.secondary)
            } else {
                let names = enabledAccounts.map(\.displayName)
                let summary = names.prefix(3).joined(separator: "、") + (names.count > 3 ? " 等 \(names.count) 个" : "")
                Text(summary).help(names.joined(separator: "、")).accessibilityLabel(names.joined(separator: "、"))
            }
        }
        Divider()
        ClientDetailRow(title: "登录方式") {
            if client.kind.supportsAccountSwitching && enabledAccounts.count > 1 {
                Text("多账号按匹配片段切换")
            } else if let account = enabledAccounts.first, client.kind.maaAccountSelector(from: account.accountSelector) != nil {
                Text("按匹配片段切换账号")
            } else if client.kind.supportsAccountSwitching && enabledAccounts.isEmpty {
                Text("支持按匹配片段切换账号")
            } else {
                Text("使用游戏当前登录账号")
            }
        }
        if !client.kind.supportsAccountSwitching, enabledAccounts.count > 1 {
            Label("此服务器只支持一个已启用账号", systemImage: "exclamationmark.circle")
                .font(.callout).foregroundStyle(.orange).padding(.bottom, 8)
        }
        Divider()
        DisclosureGroup("连接详情") {
            VStack(spacing: 0) {
                if !client.appPath.isEmpty { connectionValue("应用路径", client.appPath) }
                connectionValue("MaaTools", client.address)
                connectionValue("MAA Profile", client.profileName)
                connectionValue("Bundle ID", client.bundleIdentifier.isEmpty ? "尚未设置" : client.bundleIdentifier)
            }
        }
        .padding(.vertical, 4)
    }

    private func accountDetails(_ account: AccountConfiguration) -> some View {
        let participatingPlans = plans.filter { $0.includesAllEnabledAccounts || $0.accountIDs.contains(account.id) }
        let hasSelector = !account.accountSelector.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return Group {
            if !client.enabled { paused("所属客户端已停用，启用后才能运行此账号") }
            else if !account.enabled { paused("账号已停用") }
            ClientDetailRow(title: "登录方式") {
                if client.kind.supportsAccountSwitching, hasSelector {
                    Text("按匹配片段切换账号")
                } else if client.kind.supportsAccountSwitching, account.enabled, client.accounts.count(where: \.enabled) > 1 {
                    ActionTextButton(title: "设置账号匹配片段…", symbol: "pencil",
                                     help: "多账号运行需要唯一的匹配片段") { openEditor(.account(client.id, account.id)) }
                        .disabled(model.isWorkflowRunning)
                } else {
                    Text("使用游戏当前登录账号")
                }
            }
            Divider()
            SectionHeading(title: "参与的方案").padding(.top, 16).padding(.bottom, 6)
            if plans.isEmpty {
                Text("尚未创建方案").font(.callout).foregroundStyle(.secondary)
            } else if participatingPlans.isEmpty {
                ActionTextButton(title: "选择方案…", symbol: "checklist") { openEditor(.account(client.id, account.id)) }
                    .disabled(model.isWorkflowRunning)
            } else {
                ForEach(participatingPlans) { plan in
                    Button { model.selection = .plan(plan.id) } label: {
                        HStack(spacing: 10) {
                            Text(plan.displayName).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right").font(.caption2)
                                .foregroundStyle(.secondary).accessibilityHidden(true)
                        }
                        .padding(.vertical, 9).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).help("查看方案「\(plan.displayName)」")
                    if plan.id != participatingPlans.last?.id { Divider() }
                }
            }
        }
    }

    private func chooseApplicationButton(_ title: String) -> some View {
        ActionTextButton(title: title, symbol: "folder") {
            guard !model.isWorkflowRunning, let url = GameApplicationPicker.select(currentPath: client.appPath) else { return }
            openEditor(.client(client.id, application: url))
        }
        .disabled(model.isWorkflowRunning)
    }

    private func connectionValue(_ title: String, _ value: String) -> some View {
        ClientDetailRow(title: title) { Text(value).textSelection(.enabled) }
            .font(.callout)
    }

    private func paused(_ text: String) -> some View {
        Label(text, systemImage: "pause.circle")
            .font(.callout).foregroundStyle(.secondary).padding(.top, 12)
    }
}

private struct ClientDetailRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).foregroundStyle(.secondary).frame(width: 82, alignment: .leading)
            content
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
    }
}

struct ClientApplicationAppearance {
    var icon: NSImage?
    var isMissing = false

    @MainActor static func read(at path: String) -> Self {
        guard path.hasPrefix("/") else { return Self() }
        let url = URL(filePath: path)
        let resource: URLResourceValues
        do {
            resource = try url.resourceValues(forKeys: [.isDirectoryKey, .isReadableKey])
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return Self(isMissing: true)
        } catch {
            return Self()
        }
        guard url.pathExtension.lowercased() == "app", resource.isDirectory == true, resource.isReadable == true,
              let bundle = Bundle(url: url), let info = bundle.infoDictionary, info["CFBundlePackageType"] as? String == "APPL"
        else { return Self() }
        let primaryIcons = ["CFBundleIcons", "CFBundleIcons~ipad"].compactMap { key in
            (info[key] as? [String: Any])?["CFBundlePrimaryIcon"] as? [String: Any]
        }
        let definitions = [info] + primaryIcons
        var files = [info["CFBundleIconFile"] as? String].compactMap { $0 }
        for definition in definitions {
            if let names = definition["CFBundleIconFiles"] as? [String] { files.append(contentsOf: names.reversed()) }
        }
        // Finder can superimpose launch-status badges. Prefer the game's original art when available.
        for file in files {
            if let icon = bundledIcon(named: file, in: bundle) { return Self(icon: icon) }
        }
        if let customIcon = (try? url.resourceValues(forKeys: [.customIconKey]))?.customIcon as? NSImage,
           customIcon.isValid { return Self(icon: customIcon) }
        if definitions.contains(where: { $0["CFBundleIconName"] as? String != nil }),
           let catalog = bundle.url(forResource: "Assets", withExtension: "car"),
           FileManager.default.isReadableFile(atPath: catalog.path) {
            let icon = NSWorkspace.shared.icon(forFile: path)
            if icon.isValid { return Self(icon: icon) }
        }
        return Self()
    }

    private static func bundledIcon(named name: String, in bundle: Bundle) -> NSImage? {
        guard !name.isEmpty else { return nil }
        let resource = name as NSString
        let base = resource.deletingPathExtension
        let extensions = resource.pathExtension.isEmpty ? ["icns", "png"] : [resource.pathExtension]
        let bundlePath = bundle.bundleURL.resolvingSymlinksInPath().path + "/"
        for ext in extensions {
            let variants = ext.lowercased() == "png" ? [base + "@3x", base + "@2x", base] : [base]
            for variant in variants {
                guard let url = bundle.url(forResource: variant, withExtension: ext),
                      url.resolvingSymlinksInPath().path.hasPrefix(bundlePath),
                      let image = NSImage(contentsOf: url), image.isValid else { continue }
                return image
            }
        }
        return nil
    }
}
