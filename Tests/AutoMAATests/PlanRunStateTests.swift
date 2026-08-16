import Foundation
import Testing
@testable import AutoMAA

@Suite("Plan run state")
struct PlanRunStateTests {
    @Test("an active run takes precedence over readiness errors")
    func runningStateTakesPrecedenceOverReadiness() {
        let planID = UUID()

        #expect(PlanRunState.resolve(
            planID: planID,
            isRunning: true,
            runningPlanID: planID,
            hasReadinessError: true
        ) == .running)
    }

    @Test("busy states identify other work without reporting invalid configuration")
    func busyStatesAreDistinct() {
        let planID = UUID()

        #expect(PlanRunState.resolve(
            planID: planID,
            isRunning: true,
            runningPlanID: UUID(),
            hasReadinessError: false
        ) == .anotherPlanRunning)
        #expect(PlanRunState.resolve(
            planID: planID,
            isRunning: true,
            runningPlanID: nil,
            hasReadinessError: false
        ) == .maintenanceRunning)
    }

    @Test("idle plans distinguish ready and incomplete configurations")
    func idleStatesReflectReadiness() {
        let planID = UUID()

        #expect(PlanRunState.resolve(
            planID: planID,
            isRunning: false,
            runningPlanID: nil,
            hasReadinessError: false
        ) == .ready)
        #expect(PlanRunState.resolve(
            planID: planID,
            isRunning: false,
            runningPlanID: nil,
            hasReadinessError: true
        ) == .configurationIncomplete)
    }

    @Test("plan readiness separates direct issues from other plan blockers")
    func readinessSeparatesIssueScopes() {
        let planID = UUID()
        let otherPlanID = UUID()
        let issues = [
            ReadinessIssue(
                id: "warning",
                severity: .warning,
                message: "提醒",
                scope: .plan(planID)
            ),
            ReadinessIssue(
                id: "other-error",
                severity: .error,
                message: "其他方案错误",
                scope: .plan(otherPlanID)
            ),
        ]

        let readiness = PlanReadiness(planID: planID, issues: issues)

        #expect(readiness.directIssues.map(\.id) == ["warning"])
        #expect(readiness.externalBlockers.map(\.id) == ["other-error"])
        #expect(readiness.state == .blockedByOtherPlan(1))
        #expect(readiness.hasBlockingErrors)
    }

    @Test("direct errors take precedence and include every blocker in the count")
    func readinessPrioritizesDirectErrors() {
        let planID = UUID()
        let issues = [
            ReadinessIssue(id: "shared", severity: .error, message: "共享错误"),
            ReadinessIssue(
                id: "other",
                severity: .error,
                message: "其他方案错误",
                scope: .plan(UUID())
            ),
        ]

        let readiness = PlanReadiness(planID: planID, issues: issues)

        #expect(readiness.state == .errors(2))
    }

    @Test("ready and warning states remain runnable")
    func readinessKeepsWarningsNonBlocking() {
        let planID = UUID()
        let ready = PlanReadiness(planID: planID, issues: [])
        let warning = PlanReadiness(
            planID: planID,
            issues: [ReadinessIssue(id: "warning", severity: .warning, message: "提醒")]
        )

        #expect(ready.state == .ready)
        #expect(!ready.hasBlockingErrors)
        #expect(warning.state == .warnings(1))
        #expect(!warning.hasBlockingErrors)
    }
}
