import Testing
import Foundation
@testable import ChotkiCore

private func day(_ y: Int, _ m: Int, _ d: Int) -> CalendarDate {
    CalendarDate(year: y, month: m, day: d)!
}

/// Wednesdays and Fridays fast; Bright Week is lifted.
private struct Calendar2026: LiturgicalDayProvider {
    func isFastDay(_ date: CalendarDate) -> Bool {
        date.weekday == .wednesday || date.weekday == .friday
    }
    func isGreatFeast(_ date: CalendarDate) -> Bool { false }
    func season(_ date: CalendarDate) -> FastingSeason? { nil }
    func fastFreeReason(_ date: CalendarDate) -> String? {
        date.month == 4 && (13...18).contains(date.day) ? "Bright Week" : nil
    }
}

/// The decisions that used to live in the macOS view model, where a port would
/// have had to rewrite them — and where every bug found by hand has been.
@Suite("A rule as it stands")
struct PracticeTests {

    private let today = day(2026, 8, 19)   // a Wednesday

    private func practice(
        _ rules: [Rule], occurrences: [Occurrence] = [],
        settings: AppSettings = .default, from: CalendarDate? = nil
    ) -> Practice {
        Practice(
            rules: rules,
            activations: rules.map {
                Activation(ruleID: $0.id, from: from ?? day(2026, 1, 1))
            },
            occurrences: occurrences,
            settings: settings,
            liturgical: Calendar2026()
        )
    }

    private func rule(
        _ title: String, at time: TimeOfDay? = nil,
        _ recurrence: Recurrence = .daily, category: RuleCategory? = nil
    ) -> Rule {
        Rule(title: title, recurrence: recurrence, timeOfDay: time, category: category?.rawValue)
    }

    // MARK: what is on a day

    @Test("timed rules come first, in order, then those that run all day")
    func ordering() {
        let p = practice([
            rule("Jesus prayer"),
            rule("Evening prayers", at: TimeOfDay(hour: 21, minute: 30)),
            rule("Morning prayers", at: TimeOfDay(hour: 6, minute: 30)),
            rule("Almsgiving")
        ])
        #expect(p.entries(on: today).map(\.rule.title)
                == ["Morning prayers", "Evening prayers", "Almsgiving", "Jesus prayer"])
    }

    @Test("a rule not due that day is absent")
    func notDue() {
        let p = practice([rule("Sunday Liturgy", .weekly(days: [.sunday]))])
        #expect(p.entries(on: today).isEmpty)
    }

    // A rule that simply vanished would look like a fault and teach nothing.
    @Test("a rule the Church has lifted is shown, with the reason")
    func dispensedIsShown() {
        let p = practice(
            [rule("The Wednesday and Friday fast", .weekly(days: [.wednesday, .friday]),
                  category: .fasting)],
            settings: AppSettings(observances: ObservanceSettings(fasting: .observed))
        )
        let brightWednesday = day(2026, 4, 15)
        let entry = p.entries(on: brightWednesday).first
        #expect(entry?.dispensation == "Bright Week")
        #expect(entry?.showsAsSatisfied == true)
        #expect(entry?.isKept == false, "nothing was asked, so nothing was done")
    }

    @Test("a rule taken on later invents no earlier days")
    func noRetroactiveDays() {
        let p = practice([rule("Morning prayers")], from: today)
        #expect(p.entries(on: today.adding(days: -1)).isEmpty)
        #expect(!p.entries(on: today).isEmpty)
    }

    // MARK: settled

    @Test("a day with something outstanding is not settled")
    func notSettled() {
        let rules = [rule("Morning prayers"), rule("Evening prayers")]
        let kept = [Occurrence(ruleID: rules[0].id, date: today, status: .completed)]
        #expect(!practice(rules, occurrences: kept).isSettled(on: today))
    }

    @Test("a day with everything kept is settled")
    func settled() {
        let rules = [rule("Morning prayers"), rule("Evening prayers")]
        let kept = rules.map { Occurrence(ruleID: $0.id, date: today, status: .completed) }
        #expect(practice(rules, occurrences: kept).isSettled(on: today))
    }

    // Standing down is legitimate; treating it as unfinished would quietly
    // punish pausing.
    @Test("a rule stood down still leaves the day settled")
    func stoodDownSettles() {
        let rules = [rule("Morning prayers"), rule("Jesus prayer")]
        let occurrences = [
            Occurrence(ruleID: rules[0].id, date: today, status: .completed),
            Occurrence(ruleID: rules[1].id, date: today, status: .skipped)
        ]
        #expect(practice(rules, occurrences: occurrences).isSettled(on: today))
    }

    @Test("standing everything down settles nothing")
    func nothingKept() {
        let rules = [rule("Morning prayers"), rule("Evening prayers")]
        let stood = rules.map { Occurrence(ruleID: $0.id, date: today, status: .skipped) }
        #expect(!practice(rules, occurrences: stood).isSettled(on: today))
    }

    @Test("a day with nothing on it is not settled")
    func emptyDay() {
        #expect(!practice([]).isSettled(on: today))
    }

    // MARK: pausing

    @Test("a rule with no open stretch is paused")
    func pausing() {
        let r = rule("Evening prayers")
        let open = Practice(
            rules: [r], activations: [Activation(ruleID: r.id, from: day(2026, 1, 1))],
            occurrences: [], settings: .default
        )
        let closed = Practice(
            rules: [r],
            activations: [Activation(ruleID: r.id, from: day(2026, 1, 1), to: day(2026, 5, 1))],
            occurrences: [], settings: .default
        )
        #expect(!open.isPaused(r))
        #expect(closed.isPaused(r))
    }

    // MARK: repairs

    // A rule that can never come due sits on the list and is invisible.
    @Test("a fasting rule with fasting merely shown needs the observance turned on")
    func strandedRuleIsFound() {
        let p = practice([rule("Great Lent", .liturgical(.season(.greatLent)))])
        #expect(p.settings.observances.fasting == .shown)
        #expect(p.observancesNeeded() == [.season(.greatLent)])
    }

    @Test("nothing is needed when the observance is already kept")
    func nothingStranded() {
        let p = practice(
            [rule("Great Lent", .liturgical(.season(.greatLent)))],
            settings: AppSettings(observances: ObservanceSettings(fasting: .observed))
        )
        #expect(p.observancesNeeded().isEmpty)
    }

    @Test("a paused rule is left alone")
    func pausedRuleNotRepaired() {
        let r = rule("Great Lent", .liturgical(.season(.greatLent)))
        let p = Practice(
            rules: [r],
            activations: [Activation(ruleID: r.id, from: day(2026, 1, 1), to: day(2026, 2, 1))],
            occurrences: [], settings: .default, liturgical: Calendar2026()
        )
        #expect(p.observancesNeeded().isEmpty, "nothing is stranded, so nothing needs changing")
    }

    @Test("someone with rules has been here before")
    func firstRunAlreadyDone() {
        #expect(practice([rule("Morning prayers")]).shouldMarkFirstRunComplete)
        #expect(!practice([]).shouldMarkFirstRunComplete)

        var done = AppSettings.default
        done.hasCompletedFirstRun = true
        #expect(!practice([rule("Morning prayers")], settings: done).shouldMarkFirstRunComplete)
    }

    // MARK: progress

    @Test("progress speaks only about finished days")
    func progressEndsYesterday() {
        #expect(Practice.progressThrough(today: today) == day(2026, 8, 18))
    }
}

/// Paused rules stay on Home, greyed, so the person can take one back from the
/// place they paused it. Nothing here may change what is due, settled or scored.
@Suite("A rule that has been paused")
struct PausedRuleTests {

    private let monday = day(2026, 8, 17)

    private func daily(_ title: String = "Evening prayers") -> Rule {
        Rule(title: title, recurrence: .daily)
    }

    /// A rule that was in force from the start of the year and closed on `end`.
    private func practice(
        _ rule: Rule, closedOn end: CalendarDate?, markedPaused: Bool,
        extra: [Activation] = [], occurrences: [Occurrence] = []
    ) -> Practice {
        var settings = AppSettings.default
        if markedPaused { settings.pausedRuleIDs = [rule.id] }
        return Practice(
            rules: [rule],
            activations: [Activation(ruleID: rule.id, from: day(2026, 1, 1), to: end)] + extra,
            occurrences: occurrences,
            settings: settings,
            liturgical: Calendar2026()
        )
    }

    @Test("the day it was paused still counts, and is the first day shown as paused")
    func pauseDayIsInclusive() {
        let rule = daily()
        let p = practice(rule, closedOn: monday, markedPaused: true)
        #expect(p.pauseDay(of: rule) == monday)
        #expect(p.entries(on: monday).map(\.rule.id) == [rule.id])
        #expect(p.isOnPause(rule, on: monday))
        #expect(!p.isOnPause(rule, on: monday.adding(days: -1)))
    }

    @Test("later days show the paused rule, apart from the days that are due")
    func laterDaysShowIt() {
        let rule = daily()
        let p = practice(rule, closedOn: monday, markedPaused: true)
        let tuesday = monday.adding(days: 1)
        #expect(p.entries(on: tuesday).isEmpty)
        #expect(p.pausedEntries(on: tuesday).map(\.rule.id) == [rule.id])
        #expect(p.entriesIncludingPaused(on: tuesday).map(\.rule.id) == [rule.id])
        // Not on the pause day itself: that is an ordinary entry, shown once.
        #expect(p.pausedEntries(on: monday).isEmpty)
        #expect(p.entriesIncludingPaused(on: monday).count == 1)
    }

    @Test("a paused rule shows only on the days it would have fallen")
    func followsItsPattern() {
        let rule = Rule(title: "Wednesday fast", recurrence: .weekly(days: [.wednesday]))
        let p = practice(rule, closedOn: monday, markedPaused: true)
        #expect(p.pausedEntries(on: day(2026, 8, 18)).isEmpty)          // Tuesday
        #expect(p.pausedEntries(on: day(2026, 8, 19)).count == 1)       // Wednesday
    }

    @Test("paused entries are never asked of anyone")
    func neverCountedAsDue() {
        let rule = daily()
        // Monday was kept; the rule was paused that evening.
        let p = practice(
            rule, closedOn: monday, markedPaused: true,
            occurrences: [Occurrence(ruleID: rule.id, date: monday, status: .completed)]
        )
        let tuesday = monday.adding(days: 1)
        #expect(p.entries(on: tuesday).isEmpty)
        #expect(!p.isSettled(on: tuesday))
        // Days after the pause are neither kept nor missed.
        let report = p.report(days: 4, today: tuesday.adding(days: 3), now: Date())
        #expect(report.perRule.allSatisfy { $0.missed == 0 })
    }

    @Test("a rule closed by an edit or by ending the series is not shown as paused")
    func onlyAnActualPauseCounts() {
        let rule = daily()
        // The same closed stretch, but the person never paused it.
        let p = practice(rule, closedOn: monday, markedPaused: false)
        #expect(p.pauseDay(of: rule) == nil)
        #expect(!p.isOnPause(rule, on: monday.adding(days: 3)))
        #expect(p.pausedEntries(on: monday.adding(days: 1)).isEmpty)
    }

    @Test("resuming clears it, even if the marker is left behind")
    func resumedIsNotPaused() {
        let rule = daily()
        let resumed = Activation(ruleID: rule.id, from: monday.adding(days: 2))
        let p = practice(rule, closedOn: monday, markedPaused: true, extra: [resumed])
        #expect(p.pauseDay(of: rule) == nil)
        #expect(p.pausedEntries(on: monday.adding(days: 3)).isEmpty)
    }

    @Test("a removed rule is not shown as paused")
    func archivedRuleIsGone() {
        var rule = daily()
        rule.archivedAt = Date()
        let p = practice(rule, closedOn: monday, markedPaused: true)
        #expect(p.pauseDay(of: rule) == nil)
        #expect(p.pausedEntries(on: monday.adding(days: 1)).isEmpty)
    }

    @Test("a record written before pausing was recorded decodes as having none")
    func oldSettingsDecode() throws {
        let old = try JSONEncoder().encode(AppSettings.default)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: old)
        #expect(decoded.pausedRuleIDs.isEmpty)
        // And a settings value that has never paused anything writes nothing new.
        #expect(!String(decoding: old, as: UTF8.self).contains("pausedRuleIDs"))
    }

    @Test("the paused marker survives a round trip")
    func markerRoundTrips() throws {
        var settings = AppSettings.default
        let id = UUID()
        settings.pausedRuleIDs = [id]
        let back = try JSONDecoder().decode(
            AppSettings.self, from: JSONEncoder().encode(settings)
        )
        #expect(back.pausedRuleIDs == [id])
    }

    // MARK: what a pause does to the record

    private func kept(_ rule: Rule, _ dates: [CalendarDate]) -> [Occurrence] {
        dates.map { Occurrence(ruleID: rule.id, date: $0, status: .completed) }
    }

    /// Kept 10-14 August; paused on the 15th, which was not kept; taken back on
    /// the 20th and kept on the 20th and 21st; not kept on the 22nd and 23rd.
    private func pausedAndResumed(pauseRecorded: Bool = true) -> (Rule, Practice) {
        let rule = daily()
        let settings = AppSettings.default     // taken back, so no longer marked paused
        // What pausing wrote for the 15th, which had not been kept.
        let standDown = pauseRecorded
            ? [Occurrence(ruleID: rule.id, date: day(2026, 8, 15), status: .skipped)] : []
        let occurrences = kept(rule, (10...14).map { day(2026, 8, $0) })
            + kept(rule, [day(2026, 8, 20), day(2026, 8, 21)]) + standDown
        let p = Practice(
            rules: [rule],
            activations: [
                Activation(ruleID: rule.id, from: day(2026, 1, 1), to: day(2026, 8, 15)),
                Activation(ruleID: rule.id, from: day(2026, 8, 20)),
            ],
            occurrences: occurrences, settings: settings, liturgical: Calendar2026()
        )
        return (rule, p)
    }

    @Test("days kept before a pause stay kept; the paused days and the pause day itself leave the record")
    func pausedDaysAreNotCounted() {
        let (_, p) = pausedAndResumed()
        let score = p.report(days: 14, today: day(2026, 8, 24), now: Date()).perRule[0]
        // 10-14 kept (5) + 20-21 kept (2) = 7 kept; 22-23 not kept = 2 missed.
        // The 15th (paused, not kept, stood down) and the 16th-19th (paused)
        // are not counted.
        #expect(score.kept == 7)
        #expect(score.missed == 2)
        #expect(score.stoodDown == 1)
        #expect(score.scoreable == 9)
        #expect(score.missedDates == [day(2026, 8, 22), day(2026, 8, 23)])
    }

    @Test("the day of resuming counts, and so does every day after it")
    func resumeDayCounts() {
        let (rule, p) = pausedAndResumed()
        #expect(p.pauseDay(of: rule) == nil, "back in force: no longer the current pause")
        let onResume = p.entries(on: day(2026, 8, 20))
        #expect(onResume.map(\.rule.id) == [rule.id])
        #expect(onResume[0].isKept)
        // The days in between are no longer on Home as due; they are not asked of anyone.
        #expect(p.entries(on: day(2026, 8, 17)).isEmpty)
    }

    @Test("the day it is paused counts as kept if it was kept")
    func pauseDayKeptStaysKept() {
        let rule = daily()
        var settings = AppSettings.default
        settings.pausedRuleIDs = [rule.id]
        let p = Practice(
            rules: [rule],
            activations: [Activation(ruleID: rule.id, from: day(2026, 8, 10), to: day(2026, 8, 12))],
            occurrences: kept(rule, [day(2026, 8, 12)]),
            settings: settings, liturgical: Calendar2026()
        )
        let score = p.report(days: 5, today: day(2026, 8, 14), now: Date()).perRule[0]
        #expect(score.kept == 1)
        #expect(score.missed == 2, "10th and 11th unkept, before the pause; the 12th was kept")
    }

    @Test("a rule ended and taken back, with nothing written for its last day, counts that day")
    func endedRulesAreUnchanged() {
        let (_, p) = pausedAndResumed(pauseRecorded: false)
        let score = p.report(days: 14, today: day(2026, 8, 24), now: Date()).perRule[0]
        #expect(score.missed == 3, "the 15th was an ordinary day of a rule that was still in force")
    }

    @Test("a day with one rule kept and another paused is settled")
    func pausedRuleDoesNotUnsettleTheDay() {
        let morning = daily("Morning prayers")
        let evening = daily("Evening prayers")
        let today = day(2026, 8, 19)
        var settings = AppSettings.default
        settings.pausedRuleIDs = [evening.id]
        let p = Practice(
            rules: [morning, evening],
            activations: [
                Activation(ruleID: morning.id, from: day(2026, 1, 1)),
                Activation(ruleID: evening.id, from: day(2026, 1, 1), to: today),
            ],
            occurrences: kept(morning, [today]),
            settings: settings, liturgical: Calendar2026()
        )
        #expect(p.isSettled(on: today))
        #expect(p.rulesNotOnPause(on: today).map(\.id) == [morning.id],
                "a paused rule is not reminded of")
    }

    // MARK: pausing writes what it needs to

    private func due(_ rule: Rule, markedPaused: Bool = false, kept dates: [CalendarDate] = []) -> Practice {
        var settings = AppSettings.default
        if markedPaused { settings.pausedRuleIDs = [rule.id] }
        return Practice(
            rules: [rule],
            activations: [Activation(ruleID: rule.id, from: day(2026, 1, 1))],
            occurrences: kept(rule, dates), settings: settings, liturgical: Calendar2026()
        )
    }

    @Test("pausing a rule that was due and not kept stands the day down")
    func pausingWritesAStandDown() {
        let rule = daily()
        let plan = due(rule).pausePlan(for: rule, on: monday)
        #expect(plan.newOccurrences.map(\.status) == [.skipped])
        #expect(plan.newOccurrences.first?.date == monday)
        #expect(plan.updatedActivations.first?.to == monday, "the stretch still closes on the day")
    }

    @Test("pausing a rule already kept that day leaves the record alone")
    func pausingAfterKeepingWritesNothing() {
        let rule = daily()
        let plan = due(rule, kept: [monday]).pausePlan(for: rule, on: monday)
        #expect(plan.newOccurrences.isEmpty)
    }

    @Test("pausing a rule on a day it was not due writes nothing")
    func pausingWhenNotDueWritesNothing() {
        let rule = Rule(title: "Wednesday fast", recurrence: .weekly(days: [.wednesday]))
        #expect(due(rule).pausePlan(for: rule, on: monday).newOccurrences.isEmpty)
    }

    @Test("pausing and taking it back the same day leaves the day as it was")
    func sameDayUndo() {
        let rule = daily()
        let paused = Practice(
            rules: [rule],
            activations: [Activation(ruleID: rule.id, from: day(2026, 1, 1), to: monday)],
            occurrences: [Occurrence(ruleID: rule.id, date: monday, status: .skipped)],
            settings: { var s = AppSettings.default; s.pausedRuleIDs = [rule.id]; return s }(),
            liturgical: Calendar2026()
        )
        #expect(paused.standDownLiftedOnResume(for: rule, on: monday)?.date == monday)
        #expect(paused.standDownLiftedOnResume(for: rule, on: monday.adding(days: 1)) == nil,
                "only on the day itself")
    }

    @Test("after a pause is undone, the days in between and the day it began stay set aside")
    func pastPauseStaysSetAside() {
        let (rule, p) = pausedAndResumed()
        #expect(p.isOnPause(rule, on: day(2026, 8, 15)), "the day it was paused")
        #expect(p.isOnPause(rule, on: day(2026, 8, 17)), "a day in between")
        #expect(p.isPausedAndNotAsked(rule, on: day(2026, 8, 17)))
        #expect(p.pausedEntries(on: day(2026, 8, 17)).map(\.rule.id) == [rule.id],
                "shown greyed, and not counted")
        #expect(!p.isOnPause(rule, on: day(2026, 8, 14)), "before the pause, as it was")
        #expect(!p.isOnPause(rule, on: day(2026, 8, 20)), "the day it was taken back is ordinary")
        #expect(!p.isOnPause(rule, on: day(2026, 8, 22)))
    }

    @Test("a day paused after it was already kept is shown as it was kept")
    func keptPauseDayIsNotGreyedAfterwards() {
        let rule = daily()
        let p = Practice(
            rules: [rule],
            activations: [
                Activation(ruleID: rule.id, from: day(2026, 1, 1), to: day(2026, 8, 15)),
                Activation(ruleID: rule.id, from: day(2026, 8, 20)),
            ],
            occurrences: kept(rule, [day(2026, 8, 15)]),
            settings: .default, liturgical: Calendar2026()
        )
        #expect(!p.isOnPause(rule, on: day(2026, 8, 15)))
        #expect(p.isOnPause(rule, on: day(2026, 8, 16)))
    }
}

