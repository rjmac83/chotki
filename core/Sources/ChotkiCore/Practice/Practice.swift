import Foundation

/// A person's rule, as it stands, and the questions worth asking of it.
///
/// Pure: it holds a snapshot and answers questions about it. No store, no
/// platform, no observation. Every decision here — what is due today, whether a
/// day is settled, whether a rule is paused, which repairs a loaded record
/// needs — is behaviour any version of this app must reproduce, so it lives
/// where it can be tested once and reused rather than rewritten per platform.
public struct Practice: Sendable {

    public let rules: [Rule]
    public let activations: [Activation]
    public let occurrences: [Occurrence]
    public let settings: AppSettings
    private let engine: RecurrenceEngine

    public init(
        rules: [Rule],
        activations: [Activation],
        occurrences: [Occurrence],
        settings: AppSettings,
        liturgical: any LiturgicalDayProvider = NoLiturgicalData()
    ) {
        self.rules = rules
        self.activations = activations
        self.occurrences = occurrences
        self.settings = settings
        self.engine = RecurrenceEngine(
            liturgical: liturgical, observances: settings.observances
        )
    }

    // MARK: what is on a day

    /// The rules that fall on a day, in the order they are shown: timed first,
    /// by hour; then those that run all day.
    ///
    /// A rule the Church has lifted is included rather than omitted — with the
    /// reason — because a rule that simply vanished would look like a fault and
    /// teach nothing.
    public func entries(on date: CalendarDate) -> [DayEntry] {
        let byRule = Dictionary(
            occurrences.filter { $0.date == date }.map { ($0.ruleID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return rules.compactMap { rule -> DayEntry? in
            let due = engine.dueDates(
                rule: rule, activations: activations, from: date, through: date
            )
            if !due.isEmpty {
                return DayEntry(
                    rule: rule, date: date, occurrence: byRule[rule.id], dispensation: nil
                )
            }
            if let lifted = engine.dispensations(
                rule: rule, activations: activations, from: date, through: date
            ).first {
                return DayEntry(
                    rule: rule, date: date, occurrence: nil, dispensation: lifted.reason
                )
            }
            return nil
        }
        .sorted(by: Practice.isShownBefore)
    }

    /// Timed rules by hour, then those that run all day by title.
    private static func isShownBefore(_ a: DayEntry, _ b: DayEntry) -> Bool {
        switch (a.rule.timeOfDay, b.rule.timeOfDay) {
        case let (x?, y?): return x < y
        case (nil, _?): return false
        case (_?, nil): return true
        case (nil, nil): return a.rule.title < b.rule.title
        }
    }

    /// Every rule for the day accounted for, with at least one actually kept.
    ///
    /// A rule stood down counts as settled: standing down is a legitimate act,
    /// and treating it as unfinished would quietly punish pausing. Standing
    /// everything down settles nothing, because nothing was kept.
    public func isSettled(on date: CalendarDate) -> Bool {
        let items = entries(on: date)
        guard !items.isEmpty else { return false }
        guard items.contains(where: \.isKept) else { return false }
        // A rule paused today is set aside like one stood down: nothing more is
        // asked of it, so it must not keep the day from being settled.
        return items.allSatisfy {
            $0.showsAsSatisfied || $0.isStoodDown || isOnPause($0.rule, on: date)
        }
    }

    public func isPaused(_ rule: Rule) -> Bool {
        !activations.contains { $0.ruleID == rule.id && $0.isOpen }
    }

    // MARK: paused rules

    /// The day a rule the person paused was paused — inclusive, so it is the
    /// last day the rule counted. Nil when the rule is in force, was never
    /// paused on purpose, or has been removed.
    ///
    /// "No open stretch" is not enough. Editing a rule from today on, or
    /// removing the rest of a series, also closes a stretch, and neither is a
    /// pause; the marker in settings is what says the person paused it.
    public func pauseDay(of rule: Rule) -> CalendarDate? {
        guard settings.pausedRuleIDs.contains(rule.id), !rule.isArchived else { return nil }
        let mine = activations.filter { $0.ruleID == rule.id }
        guard !mine.isEmpty, !mine.contains(where: \.isOpen) else { return nil }
        return mine.compactMap(\.to).max()
    }

    /// Whether a rule is on pause as seen from a day.
    ///
    /// Paused now: the day it was paused and every day after. Paused and since
    /// taken back: the days in between, and the day it was paused if pausing
    /// set that day aside. Days before the pause were kept as usual and are
    /// shown as they were, and the day it is taken back is an ordinary day.
    public func isOnPause(_ rule: Rule, on date: CalendarDate) -> Bool {
        guard !rule.isArchived else { return false }
        if let paused = pauseDay(of: rule) { return date >= paused }

        let mine = activations.filter { $0.ruleID == rule.id }
        // Only a rule that was taken back later has a past pause to show.
        guard mine.contains(where: { $0.from > date }) else { return false }
        if isCovered(rule, on: date) {
            // The last day of a stretch, if the pause stood it down.
            return mine.contains { $0.to == date } && occurrences.contains {
                $0.ruleID == rule.id && $0.date == date && $0.status == .skipped
            }
        }
        return mine.contains { stretch in stretch.to.map { $0 < date } ?? false }
    }

    /// Whether a day of a rule is set aside *and* outside every stretch: the
    /// days a pause leaves without a card, and not a day anything was asked of.
    public func isPausedAndNotAsked(_ rule: Rule, on date: CalendarDate) -> Bool {
        isOnPause(rule, on: date) && !isCovered(rule, on: date)
    }

    private func isCovered(_ rule: Rule, on date: CalendarDate) -> Bool {
        activations.contains { $0.ruleID == rule.id && $0.covers(date) }
    }

    /// Pausing a rule as of a day, as a plan to apply.
    ///
    /// The day it is paused still counts if it was kept, which is what someone
    /// means who keeps a rule in the morning and pauses in the evening. If it was
    /// due and nothing was recorded, the day is stood down instead, so pausing
    /// first and keeping nothing never reads as a miss. The stand-down is a
    /// record like any other, so it stays true after the rule is taken back.
    public func pausePlan(for rule: Rule, on date: CalendarDate) -> EditPlan {
        var plan = EditPlanner().pause(rule: rule, activations: activations, on: date)
        let unrecordedAndDue = entries(on: date).contains {
            $0.rule.id == rule.id && $0.occurrence == nil && $0.dispensation == nil
        }
        if unrecordedAndDue {
            plan.newOccurrences.append(Occurrence(ruleID: rule.id, date: date, status: .skipped))
        }
        return plan
    }

    /// A rule paused and taken back on the same day was never really set aside,
    /// so the stand-down the pause wrote for that day goes with it. Nil on any
    /// other day, and when the person stood the day down themselves earlier.
    public func standDownLiftedOnResume(for rule: Rule, on date: CalendarDate) -> Occurrence? {
        guard pauseDay(of: rule) == date else { return nil }
        return occurrences.first {
            $0.ruleID == rule.id && $0.date == date && $0.status == .skipped
        }
    }

    /// Paused rules on the days after the pause on which they would have fallen.
    ///
    /// Home lists what is due, so a paused rule would otherwise vanish the day
    /// after it was paused, and with it the one place the person could take it
    /// back. These are shown greyed. They are kept apart from `entries` on
    /// purpose: nothing was asked of anyone on these days, so they must never
    /// count towards a settled day, a reminder, or a score.
    public func pausedEntries(on date: CalendarDate) -> [DayEntry] {
        rules.compactMap { rule -> DayEntry? in
            guard isPausedAndNotAsked(rule, on: date) else { return nil }
            // Would it fall today, had it been in force? Asked of a stretch that
            // covers only this day, so the rule's own pattern decides.
            let hypothetical = [Activation(ruleID: rule.id, from: date, to: date)]
            guard !engine.dueDates(
                rule: rule, activations: hypothetical, from: date, through: date
            ).isEmpty else { return nil }
            return DayEntry(rule: rule, date: date, occurrence: nil, dispensation: nil)
        }
        .sorted(by: Practice.isShownBefore)
    }

    /// The rules that may still be reminded of on a day: all but those the person
    /// has paused. A card greyed as Paused must not go on asking.
    public func rulesNotOnPause(on date: CalendarDate) -> [Rule] {
        rules.filter { !isOnPause($0, on: date) }
    }

    /// What Home shows for a day: the rules that are due, then the paused rules
    /// that would have been, in one list in the usual order.
    public func entriesIncludingPaused(on date: CalendarDate) -> [DayEntry] {
        (entries(on: date) + pausedEntries(on: date)).sorted(by: Practice.isShownBefore)
    }

    // MARK: repairs

    /// Observances that must be turned on because a rule depends on them.
    ///
    /// A rule tied to the church calendar can never come due while its
    /// observance is merely shown — it sits on the list and is invisible. That
    /// happens to a rule taken on before this was handled, or restored from an
    /// older backup, so it is repaired on load rather than only when taken on.
    public func observancesNeeded() -> [LiturgicalTrigger] {
        var wanted: [LiturgicalTrigger] = []
        for rule in rules where !rule.isArchived {
            guard case .liturgical(let trigger) = rule.recurrence else { continue }
            guard activations.contains(where: { $0.ruleID == rule.id && $0.isOpen }) else { continue }
            guard !settings.observances.setting(for: trigger).drivesRules else { continue }
            wanted.append(trigger)
        }
        return wanted
    }

    /// Someone who already has rules has plainly been here before, whatever the
    /// stored flag says. Showing them the first-run screen would be absurd.
    public var shouldMarkFirstRunComplete: Bool {
        !settings.hasCompletedFirstRun && !rules.isEmpty
    }

    // MARK: progress

    /// The last day progress speaks about: yesterday.
    ///
    /// Today is deliberately outside it. A day still in progress is not a
    /// verdict — a rule added this morning and not yet kept would otherwise
    /// count against someone before they had the chance.
    public static func progressThrough(today: CalendarDate) -> CalendarDate {
        today.adding(days: -1)
    }

    public func report(
        days: Int = 30, today: CalendarDate, timeZone: TimeZone = .current, now: Date = Date()
    ) -> ProgressReport {
        let through = Practice.progressThrough(today: today)
        return ScoringEngine(engine: engine, timeZone: timeZone).report(
            rules: rules, activations: activations, occurrences: occurrences,
            from: through.adding(days: -(days - 1)), through: through, now: now,
            liturgicalHistoryFrom: settings.reckoningChangedOn
        )
    }
}
