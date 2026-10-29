import Foundation
import Testing
@testable import AutoMAA

@Suite("Window feedback")
@MainActor
struct ApplicationFeedbackTests {
    @Test("a notice stays with one window when focus changes")
    func windowOwnership() throws {
        let center = ApplicationFeedbackCenter()
        center.activeWindow = .settings
        center.post("已复制")
        let notice = try #require(center.notice)
        center.activeWindow = .workspace
        #expect(center.notice?.window == .settings)
        #expect(center.notice?.id == notice.id)
        center.post("已保存")
        #expect(center.notice?.window == .workspace)
    }

    @Test("an old dismissal cannot remove a newer notice with identical text")
    func repeatedMessageIdentity() throws {
        let center = ApplicationFeedbackCenter()
        center.post("已复制")
        let oldID = try #require(center.notice?.id)
        center.post("已复制")
        let currentID = try #require(center.notice?.id)
        #expect(currentID != oldID)
        center.dismiss(id: oldID)
        #expect(center.notice?.id == currentID)
        center.dismiss(id: currentID)
        #expect(center.notice == nil)
    }

    @Test("informational feedback expires while actionable warnings remain", arguments: [
        ApplicationFeedback.Tone.information, .success, .warning, .error
    ])
    func dismissalPolicy(tone: ApplicationFeedback.Tone) async throws {
        let center = ApplicationFeedbackCenter(dismissalDelay: .milliseconds(10))
        center.post("状态提示", tone: tone)
        for _ in 0..<100 {
            if center.notice == nil { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect((center.notice != nil) == (tone == .warning || tone == .error))
        center.dismiss()
    }

    @Test("replacing a transient message with an error cancels its old expiration")
    func errorSurvivesPreviousTimer() async throws {
        let center = ApplicationFeedbackCenter(dismissalDelay: .milliseconds(10))
        center.post("已复制")
        await Task.yield()
        center.post("保存失败", tone: .error)
        try await Task.sleep(for: .milliseconds(30))
        #expect(center.notice?.message == "保存失败")
        center.dismiss()
    }
}
