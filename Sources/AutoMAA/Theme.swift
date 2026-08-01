import AutoMAAKit
import SwiftUI

extension Color {
    static let maaAccent = Color(red: 0.08, green: 0.69, blue: 0.68)
    static let maaBlue = Color(red: 0.13, green: 0.48, blue: 0.94)
    static let panelStroke = Color.primary.opacity(0.09)
}

struct Panel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.panelStroke, lineWidth: 1)
            }
    }
}

struct StatusDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .shadow(color: color.opacity(0.55), radius: 3)
    }
}

struct TaskIcon: View {
    let task: TaskKind
    var enabled = true

    var body: some View {
        Image(systemName: task.symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(enabled ? Color.maaAccent : Color.secondary)
            .frame(width: 32, height: 32)
            .background((enabled ? Color.maaAccent : Color.secondary).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

extension LogLevel {
    var color: Color {
        switch self {
        case .info: .secondary
        case .success: .green
        case .warning: .orange
        case .error: .red
        }
    }
}

extension RunnerPhase {
    var displayName: String {
        switch self {
        case .idle: "空闲"
        case .preparing: "准备中"
        case .updating: "更新资源"
        case .launching: "启动客户端"
        case .switchingAccount: "切换账号"
        case .runningTask: "执行任务"
        case .closing: "关闭客户端"
        case .attention: "需要手动处理"
        case .cancelled: "已停止"
        case .completed: "已完成"
        case .failed: "发生错误"
        }
    }
}
