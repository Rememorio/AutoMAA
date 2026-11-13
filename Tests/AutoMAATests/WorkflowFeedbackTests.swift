import AutoMAAKit
import Foundation
import Testing
@testable import AutoMAA

@MainActor
@Suite("Workflow feedback")
struct WorkflowFeedbackTests {
    @Test("a result shown in its own activity page does not create duplicate feedback")
    func visibleResultIsInline() {
        let fixture = Fixture()
        defer { fixture.remove() }
        let planID = fixture.model.configuration.plans[0].id
        fixture.model.selection = .activity
        fixture.model.activitySelection = .plan(planID)
        let runID = UUID()
        let firstView = UUID()
        let secondView = UUID()
        fixture.model.setActivityResultVisible(runID, viewID: firstView)
        fixture.model.setActivityResultVisible(runID, viewID: secondView)
        fixture.model.setActivityResultVisible(nil, viewID: firstView)
        fixture.model.notifyWorkflowResult(.init(failedSteps: 1, totalSteps: 1), planID: planID, runID: runID)
        #expect(fixture.model.feedback.notices.isEmpty)
        fixture.model.setActivityResultVisible(nil, viewID: secondView)
        fixture.model.notifyWorkflowResult(.init(failedSteps: 1, totalSteps: 1), planID: planID, runID: runID)
        #expect(fixture.model.feedback.notice(for: .workspace, style: .toast)?.action == .activity(runID))
    }

    @Test("an off-page failed run links to its durable result in the workspace")
    func offPageResultHasAction() throws {
        let fixture = Fixture()
        defer { fixture.remove() }
        let planID = fixture.model.configuration.plans[0].id
        let runID = UUID()
        fixture.model.selection = .clients
        fixture.model.showSettings(.general)
        fixture.model.notifyWorkflowResult(.init(failedSteps: 1, totalSteps: 1), planID: planID, runID: runID)
        let notice = try #require(fixture.model.feedback.notice(for: .workspace, style: .toast))
        #expect(notice.action == .activity(runID))
        #expect(notice.tone == .error)
        #expect(fixture.model.feedback.notice(for: .settings(.general), style: .toast) == nil)
    }

    @Test("a failure before any run record exists remains actionable in the workspace")
    func unrecordedFailurePersists() {
        let fixture = Fixture()
        defer { fixture.remove() }
        fixture.model.notifyWorkflowResult(.init(fatalError: "运行前校验失败"),
                                          planID: fixture.model.configuration.plans[0].id, runID: nil)
        #expect(fixture.model.feedback.notice(for: .workspace, style: .banner)?.message == "运行前校验失败")
    }

    @Test("field validation returns a local error without creating a second global message")
    func stageValidationStaysInForm() {
        let fixture = Fixture()
        defer { fixture.remove() }
        #expect(fixture.model.saveFightRecoveryStage("", clientID: UUID(), accountID: UUID()) != nil)
        #expect(fixture.model.feedback.notices.isEmpty)
    }

    @MainActor
    private final class Fixture {
        let root = FileManager.default.temporaryDirectory.appending(path: "automaa-workflow-feedback-\(UUID())")
        let model: AppModel

        init() {
            model = AppModel(directories: AppDirectories(root: root),
                             launchAgentsDirectory: root.appending(path: "LaunchAgents"),
                             managesSystemLaunchAgents: false, checksForUpdatesAutomatically: false,
                             allowsAutomaticMAAMaintenance: false)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
