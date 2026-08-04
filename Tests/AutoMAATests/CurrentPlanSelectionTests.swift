import AutoMAAKit
import Foundation
import Testing
@testable import AutoMAA

@Suite("Current plan selection")
struct CurrentPlanSelectionTests {
    @Test("returning to overview preserves the plan chosen for editing")
    @MainActor
    func navigationPreservesCurrentPlan() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "automaa-current-plan-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root)
        let completeID = try #require(model.configuration.plans.last?.id)

        model.selection = .plan(completeID)
        #expect(model.currentPlanID == completeID)

        model.selection = .overview
        #expect(model.currentPlanID == completeID)
        #expect(model.currentPlan?.id == completeID)
    }

    @Test("the current plan picker does not change navigation")
    @MainActor
    func currentPlanPickerIsIndependent() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "automaa-current-plan-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root)
        let completeID = try #require(model.configuration.plans.last?.id)

        model.selectCurrentPlan(completeID)

        #expect(model.selection == .overview)
        #expect(model.currentPlanID == completeID)
    }

    @Test("deleting the current plan chooses the next available plan")
    @MainActor
    func deletingCurrentPlanRepairsSelection() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "automaa-current-plan-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root)
        let lightID = try #require(model.configuration.plans.first?.id)
        let completeID = try #require(model.configuration.plans.last?.id)

        model.selectCurrentPlan(lightID)
        model.deletePlan(lightID)

        #expect(model.currentPlanID == completeID)
        #expect(model.currentPlan?.id == completeID)
    }

    @MainActor
    private func makeModel(root: URL) -> AppModel {
        AppModel(
            directories: AppDirectories(root: root),
            launchAgentsDirectory: root.appending(path: "LaunchAgents", directoryHint: .isDirectory),
            managesSystemLaunchAgents: false,
            checksForUpdatesAutomatically: false
        )
    }
}
