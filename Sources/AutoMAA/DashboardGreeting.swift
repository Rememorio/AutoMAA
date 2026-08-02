import Foundation

struct DashboardGreeting: Equatable, Sendable {
    let title: String
    let detail: String

    static func resolve(at date: Date = .now, calendar: Calendar = .current) -> Self {
        resolve(hour: calendar.component(.hour, from: date))
    }

    static func resolve(hour: Int) -> Self {
        switch hour {
        case 0..<5:
            .init(
                title: "夜深了，博士",
                detail: "罗德岛仍有值班干员守夜，你也该为下一次行动保留精力。"
            )
        case 5..<8:
            .init(
                title: "清晨好，博士",
                detail: "新一班值勤已经开始，先看看今天的安排吧。"
            )
        case 8..<12:
            .init(
                title: "早上好，博士",
                detail: "终端已就绪，今天的日常行动可以从容安排。"
            )
        case 12..<14:
            .init(
                title: "中午好，博士",
                detail: "午间补给时间到了，稍作休整再继续处理事务吧。"
            )
        case 14..<18:
            .init(
                title: "下午好，博士",
                detail: "行动记录已整理好，看看今天还剩哪些安排。"
            )
        case 18..<23:
            .init(
                title: "晚上好，博士",
                detail: "今日值勤接近尾声，剩下的日常会按方案有序完成。"
            )
        default:
            .init(
                title: "已经很晚了，博士",
                detail: "罗德岛仍有人守夜，你也别忘了休息。"
            )
        }
    }
}
