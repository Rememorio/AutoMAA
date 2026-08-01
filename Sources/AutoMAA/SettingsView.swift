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
                schedulePanel
                reliabilityPanel
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

    private var schedulePanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("每日自动运行", systemImage: "clock.badge.checkmark.fill")
                        .font(.headline)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { model.configuration.schedule.enabled },
                        set: { model.setScheduleEnabled($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(model.isRunning)
                }
                HStack(spacing: 20) {
                    Stepper("小时：\(String(format: "%02d", model.configuration.schedule.hour))", value: $model.configuration.schedule.hour, in: 0...23)
                    Stepper("分钟：\(String(format: "%02d", model.configuration.schedule.minute))", value: $model.configuration.schedule.minute, in: 0...59)
                    Spacer()
                    if model.configuration.schedule.enabled {
                        Button("应用时间") { model.setScheduleEnabled(true) }
                            .disabled(model.isRunning)
                    }
                }
                HStack(spacing: 8) {
                    StatusDot(color: model.scheduleInstalled ? .green : .secondary)
                    Text(model.scheduleInstalled ? "系统定时任务已安装" : "系统定时任务未安装")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("使用 macOS LaunchAgent；需要用户已登录。运行器会持有进程锁和 caffeinate，避免重复执行与中途休眠。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var reliabilityPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                Label("执行策略", systemImage: "arrow.clockwise.circle.fill")
                    .font(.headline)
                Toggle("运行前热更新 MAA 资源", isOn: $model.configuration.schedule.hotUpdateBeforeRun)
                Stepper(
                    "单步骤失败重试：\(model.configuration.schedule.maxRetries) 次",
                    value: $model.configuration.schedule.maxRetries,
                    in: 0...3
                )
                Toggle("某一步失败后继续后续步骤", isOn: $model.configuration.schedule.continueAfterStepFailure)
                Text("每个日常任务独立调用 maa-cli。已成功步骤按日期记录，再次运行时自动跳过。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
