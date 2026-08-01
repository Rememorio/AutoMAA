import AutoMAAKit
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                metrics
                workflow
                readiness
                recentActivity
            }
            .padding(28)
            .frame(maxWidth: 1_060, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("今日总览")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text(greeting)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(model.isRunning ? model.statusMessage : "按你的配置调度 MAA，依次完成每个客户端和账号的日常任务。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                Button {
                    if model.isRunning {
                        model.cancelRun()
                    } else {
                        model.runAll()
                    }
                } label: {
                    Label(model.isRunning ? "安全停止" : "开始今日任务", systemImage: model.isRunning ? "stop.fill" : "play.fill")
                        .font(.headline)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(model.isRunning ? .red : .maaAccent)
                .disabled(!model.isRunning && !model.canRun)
                if model.isRunning {
                    ProgressView(value: model.progress)
                        .frame(width: 180)
                }
            }
        }
    }

    private var metrics: some View {
        HStack(spacing: 12) {
            metric(title: "客户端", value: "\(model.activeClientCount)", symbol: "macwindow", color: .maaBlue)
            metric(title: "账号", value: "\(model.activeAccountCount)", symbol: "person.2.fill", color: .maaAccent)
            metric(title: "日常步骤", value: "\(model.activeTaskCount)", symbol: "checklist", color: .orange)
            metric(
                title: "自动运行",
                value: model.configuration.schedule.enabled ? String(format: "%02d:%02d", model.configuration.schedule.hour, model.configuration.schedule.minute) : "关闭",
                symbol: "clock.fill",
                color: .purple
            )
        }
    }

    private func metric(title: String, value: String, symbol: String, color: Color) -> some View {
        Panel {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 36, height: 36)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(.title3.weight(.bold).monospacedDigit())
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var workflow: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("执行顺序", detail: "客户端严格串行；关闭并确认当前连接释放后，才会启动下一项。")
            Panel {
                if model.configuration.clients.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "square.stack.3d.up.badge.plus")
                            .font(.system(size: 34))
                            .foregroundStyle(Color.maaAccent)
                        VStack(spacing: 4) {
                            Text("创建你的第一个客户端")
                                .font(.headline)
                            Text("选择服务器和游戏应用，再添加一个或多个账号。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            model.addClient()
                        } label: {
                            Label("添加客户端", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                } else {
                    HStack(spacing: 10) {
                        ForEach(Array(model.configuration.clients.filter(\.enabled).enumerated()), id: \.element.id) { index, client in
                            clientNode(client)
                            if index < model.configuration.clients.filter(\.enabled).count - 1 {
                                VStack(spacing: 4) {
                                    Image(systemName: "arrow.right")
                                        .foregroundStyle(Color.maaAccent)
                                    Text("释放端口")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(width: 64)
                            }
                        }
                    }
                }
            }
        }
    }

    private func clientNode(_ client: ClientConfiguration) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: client.kind.symbol)
                    .font(.title2)
                    .foregroundStyle(Color.maaAccent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(client.name)
                        .font(.subheadline.weight(.semibold))
                    Text(client.address)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 6) {
                ForEach(client.accounts.filter(\.enabled)) { account in
                    Text(account.name)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.maaAccent.opacity(0.09), in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var readiness: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("运行检查", detail: "关键条件不满足时会拒绝启动，避免跑错账号或连错客户端。")
            Panel {
                if model.readinessIssues.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("配置已就绪")
                                .font(.headline)
                            Text("可以安全执行完整工作流")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(model.readinessIssues) { issue in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: issue.severity == .error ? "exclamationmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(issue.severity == .error ? Color.red : Color.orange)
                                Text(issue.message)
                                    .font(.callout)
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
    }

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("最近活动", detail: nil)
            Panel {
                if model.logs.isEmpty {
                    Text("还没有运行记录")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 10) {
                        ForEach(model.logs.suffix(4).reversed()) { log in
                            HStack(spacing: 10) {
                                StatusDot(color: log.level.color)
                                Text(log.message)
                                    .font(.callout)
                                    .lineLimit(1)
                                Spacer()
                                Text(log.timestamp, style: .time)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func sectionTitle(_ title: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 11 { return "早上好，博士" }
        if hour < 18 { return "下午好，博士" }
        return "晚上好，博士"
    }
}
