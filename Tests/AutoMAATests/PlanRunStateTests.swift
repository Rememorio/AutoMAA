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
}
