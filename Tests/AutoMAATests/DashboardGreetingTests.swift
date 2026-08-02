import Testing
@testable import AutoMAA

@Suite("Dashboard greeting")
struct DashboardGreetingTests {
    @Test("time periods use distinct greetings and late-night care")
    func greetingBoundaries() {
        #expect(DashboardGreeting.resolve(hour: 0).title == "夜深了，博士")
        #expect(DashboardGreeting.resolve(hour: 4).title == "夜深了，博士")
        #expect(DashboardGreeting.resolve(hour: 5).title == "清晨好，博士")
        #expect(DashboardGreeting.resolve(hour: 8).title == "早上好，博士")
        #expect(DashboardGreeting.resolve(hour: 12).title == "中午好，博士")
        #expect(DashboardGreeting.resolve(hour: 14).title == "下午好，博士")
        #expect(DashboardGreeting.resolve(hour: 18).title == "晚上好，博士")
        #expect(DashboardGreeting.resolve(hour: 23).title == "已经很晚了，博士")
        #expect(DashboardGreeting.resolve(hour: 23).detail.contains("休息"))
    }
}
