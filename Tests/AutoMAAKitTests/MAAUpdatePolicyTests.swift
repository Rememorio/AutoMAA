import Testing
@testable import AutoMAAKit

@Suite("MAA update time budgets")
struct MAAUpdatePolicyTests {
    @Test("manual downloads allow slow connections without extending pre-run or app updates")
    func budgets() {
        #expect(MAAUpdateContext.manual.timeout(for: .core(.stable)) == 7_200)
        #expect(MAAUpdateContext.manual.timeout(for: .core(.beta)) == 7_200)
        #expect(MAAUpdateContext.manual.timeout(for: .resources) == 1_200)
        #expect(MAAUpdateContext.beforeRun.timeout(for: .resources) == 180)
        #expect(UpdatePolicy.packageTimeout == 900)
        #expect(UpdatePolicy.checkTimeout == 30)
    }

    @Test("automatic core updates fit within the scheduled-run safety window")
    func automaticBudget() {
        let timeout = MAAUpdateContext.automatic.timeout(for: .core(.stable))
        #expect(timeout == 1_800)
        #expect(timeout < AutomaticMAAUpdatePolicy.scheduledRunSafetyWindow)
    }
}
