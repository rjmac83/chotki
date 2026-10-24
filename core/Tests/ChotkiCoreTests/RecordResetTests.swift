import Testing
import Foundation
@testable import ChotkiCore

private func day(_ y: Int, _ m: Int, _ d: Int) -> CalendarDate {
    CalendarDate(year: y, month: m, day: d)!
}

/// A reset must never turn a long record into a long list of misses.
@Suite("Starting the record again")
struct RecordResetTests {

    private let today = day(2026, 10, 24)

    private func rule(_ title: String = "Morning prayers") -> Rule {
        Rule(title: title, recurrence: .daily)
    }

    @Test("a rule in force begins again today, and its earlier stretches go")
    func ruleInForceRestarts() {
        let r = rule()
        let old = Activation(ruleID: r.id, from: day(2026, 1, 1), to: day(2026, 3, 1))
        let current = Activation(ruleID: r.id, from: day(2026, 4, 1))
        let plan = RecordReset().plan(
            rules: [r], activations: [old, current], pausedRuleIDs: [], today: today
        )
        #expect(plan.updatedActivations.map(\.id) == [current.id])
        #expect(plan.updatedActivations.first?.from == today)
        #expect(plan.updatedActivations.first?.to == nil)
        #expect(plan.removedActivationIDs == [old.id])
    }

    @Test("a paused rule stays paused, as one stood-down day")
    func pausedRuleStaysPaused() {
        let r = rule()
        let pausedOn = day(2026, 9, 10)
        let stretch = Activation(ruleID: r.id, from: day(2026, 1, 1), to: pausedOn)
        let plan = RecordReset().plan(
            rules: [r], activations: [stretch], pausedRuleIDs: [r.id], today: today
        )
        #expect(plan.updatedActivations.first?.from == pausedOn)
        #expect(plan.updatedActivations.first?.to == pausedOn)
        #expect(plan.newOccurrences.map(\.status) == [.skipped])
        #expect(plan.newOccurrences.first?.date == pausedOn)
    }

    @Test("a rule that only ended has nothing left to hold")
    func endedRuleIsDropped() {
        let r = rule()
        let stretch = Activation(ruleID: r.id, from: day(2026, 1, 1), to: day(2026, 8, 1))
        let plan = RecordReset().plan(
            rules: [r], activations: [stretch], pausedRuleIDs: [], today: today
        )
        #expect(plan.removedActivationIDs == [stretch.id])
        #expect(plan.updatedActivations.isEmpty)
    }

    @Test("after a reset, nothing in the past can be missed")
    func nothingBecomesAMiss() {
        let inForce = rule("Morning prayers")
        let paused = rule("Evening prayers")
        let ended = rule("Almsgiving")
        let pausedOn = day(2026, 9, 10)
        let activations = [
            Activation(ruleID: inForce.id, from: day(2026, 1, 1)),
            Activation(ruleID: paused.id, from: day(2026, 1, 1), to: pausedOn),
            Activation(ruleID: ended.id, from: day(2026, 1, 1), to: day(2026, 8, 1)),
        ]
        let plan = RecordReset().plan(
            rules: [inForce, paused, ended], activations: activations,
            pausedRuleIDs: [paused.id], today: today
        )
        // Apply it the way the platform does: stretches first, then the history
        // goes, and the one stand-down the plan asks for is written back.
        var after = activations.filter { !plan.removedActivationIDs.contains($0.id) }
        for updated in plan.updatedActivations {
            if let index = after.firstIndex(where: { $0.id == updated.id }) { after[index] = updated }
        }
        var settings = AppSettings.default
        settings.pausedRuleIDs = [paused.id]
        let practice = Practice(
            rules: [inForce, paused, ended], activations: after,
            occurrences: plan.newOccurrences, settings: settings
        )
        let report = practice.report(days: 90, today: today, now: Date())   // judges up to yesterday only
        #expect(report.perRule.allSatisfy { $0.missed == 0 })
        #expect(report.overall == nil, "nothing has come due yet, so there is no figure")
        #expect(practice.isOnPause(paused, on: pausedOn.adding(days: 1)),
                "the paused rule is still shown as paused")
        #expect(practice.entries(on: today).map(\.rule.id) == [inForce.id])
    }
}
