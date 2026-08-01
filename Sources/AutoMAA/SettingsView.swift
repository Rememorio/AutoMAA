import AppKit
import AutoMAAKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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
