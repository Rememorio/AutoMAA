import Foundation
import Testing
@testable import AutoMAA

@Suite("Application feedback")
@MainActor
struct ApplicationFeedbackTests {
    @Test("a successful acknowledgement cannot replace an unresolved error")
    func successPreservesError() {
        let center = ApplicationFeedbackCenter()
        center.post("保存失败", tone: .error)
        center.post("操作完成", tone: .success)
        #expect(center.notice(for: .workspace, style: .banner)?.message == "保存失败")
        #expect(center.notice(for: .workspace, style: .toast)?.message == "操作完成")
    }

    @Test("each business destination retains its own feedback")
    func destinationOwnership() throws {
        let center = ApplicationFeedbackCenter()
        center.post("本轮完成")
        center.post("通知权限不可用", tone: .error, destination: .settings(.general))
        center.post("维护失败", tone: .error, destination: .settings(.environment))
        #expect(center.notice(for: .workspace, style: .toast)?.message == "本轮完成")
        #expect(center.notice(for: .settings(.general), style: .banner)?.message == "通知权限不可用")
        #expect(center.notice(for: .settings(.environment), style: .banner)?.message == "维护失败")
        #expect(center.notice(for: .applicationUpdate, style: .banner) == nil)
    }

    @Test("repeating a toast replaces it and an old dismissal cannot remove the new one")
    func repeatedMessageIdentity() throws {
        let center = ApplicationFeedbackCenter()
        let oldID = center.post("已保存")
        let currentID = center.post("已保存")
        #expect(currentID != oldID)
        center.dismiss(id: oldID)
        #expect(center.notices.count == 1)
        #expect(center.notice(for: .workspace, style: .toast)?.id == currentID)
        center.dismiss(id: currentID)
        #expect(center.notices.isEmpty)
    }

    @Test("brief feedback expires while actionable problems remain", arguments: [
        ApplicationFeedback.Tone.information, .success, .warning, .error
    ])
    func dismissalPolicy(tone: ApplicationFeedback.Tone) async throws {
        let center = ApplicationFeedbackCenter(dismissalDelay: .milliseconds(20))
        let id = center.post("状态提示", tone: tone)
        if tone == .information || tone == .success { try await waitForToast(center) }
        else { try await Task.sleep(for: .milliseconds(70)) }
        #expect(center.notices.contains { $0.id == id } == (tone == .warning || tone == .error))
        center.dismiss(id: id)
    }

    @Test("toast expiration cannot clear a persistent error at the same destination")
    func errorSurvivesPreviousTimer() async throws {
        let center = ApplicationFeedbackCenter(dismissalDelay: .milliseconds(20))
        center.post("已保存")
        center.post("同步失败", tone: .error)
        try await waitForToast(center)
        #expect(center.notice(for: .workspace, style: .toast) == nil)
        #expect(center.notice(for: .workspace, style: .banner)?.message == "同步失败")
    }

    @Test("hover and keyboard focus independently pause expiration")
    func independentPauses() async throws {
        let center = ApplicationFeedbackCenter(dismissalDelay: .milliseconds(80))
        let id = center.post("本轮完成")
        center.setPaused(true, id: id, reason: .hover)
        center.setPaused(true, id: id, reason: .focus)
        try await Task.sleep(for: .milliseconds(120))
        #expect(center.notice(for: .workspace, style: .toast)?.id == id)
        center.setPaused(false, id: id, reason: .hover)
        try await Task.sleep(for: .milliseconds(120))
        #expect(center.notice(for: .workspace, style: .toast)?.id == id)
        center.setPaused(false, id: id, reason: .focus)
        for _ in 0..<200 where center.notice(for: .workspace, style: .toast) != nil {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(center.notice(for: .workspace, style: .toast) == nil)
    }

    @Test("a run result can expire because its action points to a durable record")
    func resultAction() async throws {
        let center = ApplicationFeedbackCenter(dismissalDelay: .milliseconds(20))
        let runID = UUID()
        center.post("本轮部分完成", tone: .warning, style: .toast, action: .activity(runID))
        #expect(center.notice(for: .workspace, style: .toast)?.action == .activity(runID))
        #expect(center.notice(for: .workspace, style: .banner) == nil)
        try await waitForToast(center)
        #expect(center.notices.isEmpty)
    }
    private func waitForToast(_ center: ApplicationFeedbackCenter) async throws {
        for _ in 0..<200 where center.notice(for: .workspace, style: .toast) != nil {
            try await Task.sleep(for: .milliseconds(5))
        }
    }

}
