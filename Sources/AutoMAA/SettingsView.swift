import AppKit
import AutoMAAKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                applicationUpdatePanel
                maaPanel
                storagePanel
            }
            .padding(28)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("全局设置")
    }

    private var applicationUpdatePanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("AutoMAA 更新", systemImage: "arrow.down.app.fill")
                        .font(.headline)
                    Spacer()
                    Text("当前版本 v\(model.currentApplicationVersion)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                switch model.applicationUpdateState {
                case .idle:
                    updateRow(
                        message: "启动时自动检查 GitHub Release，也可以随时手动检查。",
                        buttonTitle: "检查更新",
                        action: { model.checkForApplicationUpdate() }
                    )
                case .checking:
                    progressRow("正在检查 GitHub Release…")
                case .upToDate:
                    updateRow(
                        message: "当前已经是最新版本。",
                        symbol: "checkmark.circle.fill",
                        color: .green,
                        buttonTitle: "再次检查",
                        action: { model.checkForApplicationUpdate() }
                    )
                case let .available(release):
                    VStack(alignment: .leading, spacing: 10) {
                        Label("发现 v\(release.version.description)", systemImage: "sparkles")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.maaAccent)
                        if !release.releaseNotes.isEmpty {
                            Text(releaseSummary(release.releaseNotes))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                        HStack {
                            Link("查看发布说明", destination: release.pageURL)
                            Spacer()
                            Button("下载并校验") { model.downloadApplicationUpdate(release) }
                                .buttonStyle(.borderedProminent)
                                .disabled(model.isRunning)
                        }
                    }
                case let .downloading(release):
                    progressRow("正在下载并校验 v\(release.version)…")
                case let .ready(prepared):
                    VStack(alignment: .leading, spacing: 10) {
                        Label("v\(prepared.release.version.description) 已准备好", systemImage: "checkmark.shield.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.green)
                        Text("更新包已通过 SHA-256、Bundle ID、架构和代码签名校验。重启后会替换当前 App；失败时自动恢复旧版本。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Link("查看发布说明", destination: prepared.release.pageURL)
                            Spacer()
                            Button("重启并立即更新") { model.restartAndInstallApplicationUpdate(prepared) }
                                .buttonStyle(.borderedProminent)
                                .disabled(model.isRunning)
                        }
                    }
                case let .installing(release):
                    progressRow("正在退出并安装 v\(release.version)…")
                case let .failed(message):
                    VStack(alignment: .leading, spacing: 10) {
                        Label("更新未完成", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        HStack {
                            Spacer()
                            Button("重新检查") { model.checkForApplicationUpdate() }
                                .disabled(model.isRunning)
                        }
                    }
                }

                Text("仅从 \(model.applicationUpdateRepository) 的正式 Release 下载，不会更新游戏包体或 MAA 资源。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func updateRow(
        message: String,
        symbol: String? = nil,
        color: Color = .secondary,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            if let symbol {
                Image(systemName: symbol)
                    .foregroundStyle(color)
            }
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(buttonTitle, action: action)
                .disabled(model.isRunning)
        }
    }

    private func progressRow(_ message: String) -> some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func releaseSummary(_ notes: String) -> String {
        let lines = notes
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("本项目遵循") }
        return lines.prefix(3).joined(separator: " ")
    }

    private var maaPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                Label("MAA", systemImage: "terminal.fill")
                    .font(.headline)
                LabeledContent("maa-cli 路径") {
                    TextField("/opt/homebrew/bin/maa", text: $model.configuration.cliPath)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 390)
                }
                HStack {
                    Text("资源与核心由本机 maa-cli 管理。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        model.hotUpdate()
                    } label: {
                        Label("立即更新资源", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(model.isRunning)
                }
            }
        }
    }

    private var storagePanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                Label("数据与恢复", systemImage: "externaldrive.fill")
                    .font(.headline)
                LabeledContent("配置目录") {
                    Text(model.directories.root.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
                HStack {
                    Button("打开配置目录") { NSWorkspace.shared.open(model.directories.root) }
                    Button("重置今日完成记录") { model.resetToday() }
                        .disabled(model.isRunning)
                    Spacer()
                    Button("立即保存") { model.saveNow() }
                }
            }
        }
    }
}
