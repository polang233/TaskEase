import Foundation
import Testing
@testable import TaskEase

struct TaskEaseTests {
    @Test func foregroundAlwaysRestores() {
        for mode in [ControlMode.gentle, .budget] {
            let status = Policy.status(rule: AppRule(mode: mode, cpuPercent: 20, delaySeconds: 0),
                                       enabled: true, controllable: true,
                                       isForeground: true, isHidden: false, backgroundSeconds: 100)
            #expect(status == .foreground)
            #expect(!Policy.shouldControl(status))
        }
    }
    @Test func backgroundGraceAndRapidReturn() {
        let rule = AppRule(mode: .budget, cpuPercent: 20, delaySeconds: 3)
        #expect(Policy.status(rule: rule, enabled: true, controllable: true,
            isForeground: false, isHidden: false, backgroundSeconds: 2.99) == .waiting)
        #expect(Policy.status(rule: rule, enabled: true, controllable: true,
            isForeground: false, isHidden: false, backgroundSeconds: 3) == .budget)
        #expect(Policy.status(rule: rule, enabled: true, controllable: true,
            isForeground: true, isHidden: false, backgroundSeconds: 3) == .foreground)
    }
    @Test func disabledAndProtectedAppsNeverControl() {
        let rule = AppRule(mode: .gentle)
        #expect(Policy.status(rule: rule, enabled: false, controllable: true,
            isForeground: false, isHidden: false, backgroundSeconds: 10) == .paused)
        #expect(Policy.status(rule: rule, enabled: true, controllable: false,
            isForeground: false, isHidden: false, backgroundSeconds: 10) == .unavailable)
        #expect(!Policy.shouldControl(.unavailable))
        #expect(!Policy.shouldControl(.paused))
    }
    @Test func hiddenApplicationCanBecomeBackground() {
        #expect(Policy.status(rule: AppRule(mode: .gentle, delaySeconds: 0),
            enabled: true, controllable: true, isForeground: true,
            isHidden: true, backgroundSeconds: 1) == .gentle)
    }
    @Test func aReusedPIDIsADifferentProcess() {
        let first = ProcessIdentity(pid: 101, uid: 501, startSeconds: 1, startMicroseconds: 1)
        let second = ProcessIdentity(pid: 101, uid: 501, startSeconds: 2, startMicroseconds: 1)
        #expect(first != second)
        #expect(Set([first, second]).count == 2)
    }
    @Test func budgetTracksAggregateCPUAndRepaysOvershoot() {
        var budget = BudgetCredit()
        let overBudget = budget.update(elapsedTicks: 100, usedTicks: 40, fraction: 0.2, burstTicks: 10)
        #expect(overBudget)
        #expect(budget.credit == -20)
        let repaid = budget.update(elapsedTicks: 100, usedTicks: 0, fraction: 0.2, burstTicks: 10)
        #expect(!repaid)
        #expect(budget.credit == 0)
    }
    @Test func idleTimeDoesNotAccumulateAnUnlimitedBurst() {
        var budget = BudgetCredit()
        _ = budget.update(elapsedTicks: 100_000, usedTicks: 0, fraction: 0.2, burstTicks: 10)
        #expect(budget.credit == 10)
        let overBudget = budget.update(elapsedTicks: 10, usedTicks: 30, fraction: 0.2, burstTicks: 10)
        #expect(overBudget)
    }
    @Test func storedRulesClampValuesAndRejectCorruption() throws {
        let data = Data(#"{"app":{"mode":"budget","cpuPercent":900,"delaySeconds":-10}}"#.utf8)
        let rules = try StoredRules.decode(data)
        #expect(rules["app"]?.cpuPercent == 200)
        #expect(rules["app"]?.delaySeconds == 0)
        #expect(throws: (any Error).self) { try StoredRules.decode(Data("invalid".utf8)) }
        let encoded = try StoredRules.encode(rules)
        #expect(try StoredRules.decode(encoded) == rules)
    }
    @Test func inactiveRuleStaysUnmanaged() {
        #expect(Policy.status(rule: AppRule(), enabled: true, controllable: true,
            isForeground: false, isHidden: false, backgroundSeconds: 100) == .unmanaged)
    }
}
