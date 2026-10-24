package org.chotki.core

import java.time.Instant
import java.time.ZoneId

/** What is due, what has become of it, and what the record says. */
class Practice(
    private val rules: List<Rule>,
    private val activations: List<Activation>,
    private val occurrences: List<Occurrence>,
    val settings: AppSettings = AppSettings.DEFAULT,
    liturgical: LiturgicalDayProvider = NoLiturgicalData,
) {
    private val engine = RecurrenceEngine(liturgical, settings.observances)

    // MARK: what is on a day

    /**
     * The rules that fall on a day, in the order they are shown: timed first, by
     * hour; then those that run all day.
     *
     * A rule the Church has lifted is included rather than omitted — with the
     * reason — because a rule that simply vanished would look like a fault and
     * teach nothing.
     */
    fun entries(on: CalendarDate): List<DayEntry> {
        val byRule = occurrences.filter { it.date == on }.associateBy { it.ruleID }

        return rules.mapNotNull { rule ->
            val due = engine.dueDates(rule, activations, on, on)
            if (due.isNotEmpty()) {
                DayEntry(rule, on, byRule[rule.id], dispensation = null)
            } else {
                engine.dispensations(rule, activations, on, on).firstOrNull()?.let { (_, reason) ->
                    DayEntry(rule, on, occurrence = null, dispensation = reason)
                }
            }
        }.sortedWith { a, b -> shownBefore(a, b) }
    }

    /**
     * Every rule for the day accounted for, with at least one actually kept.
     *
     * A rule stood down counts as settled: standing down is a legitimate act,
     * and treating it as unfinished would quietly punish pausing. Standing
     * everything down settles nothing, because nothing was kept.
     */
    fun isSettled(on: CalendarDate): Boolean {
        val items = entries(on)
        if (items.isEmpty()) return false
        if (items.none { it.isKept }) return false
        // A rule paused today is set aside like one stood down: nothing more is
        // asked of it, so it must not keep the day from being settled.
        return items.all { it.showsAsSatisfied || it.isStoodDown || isOnPause(it.rule, on) }
    }

    fun isPaused(rule: Rule): Boolean =
        activations.none { it.ruleID == rule.id && it.isOpen }

    // MARK: paused rules

    /**
     * The day a rule the person paused was paused — inclusive, so it is the
     * last day the rule counted. Null when the rule is in force, was never
     * paused on purpose, or has been removed.
     *
     * "No open stretch" is not enough. Editing a rule from today on, or
     * removing the rest of a series, also closes a stretch, and neither is a
     * pause; the marker in settings is what says the person paused it.
     */
    fun pauseDay(rule: Rule): CalendarDate? {
        if (rule.id !in settings.pausedRuleIDs || rule.isArchived) return null
        val mine = activations.filter { it.ruleID == rule.id }
        if (mine.isEmpty() || mine.any { it.isOpen }) return null
        return mine.mapNotNull { it.to }.maxOrNull()
    }

    /**
     * Whether a rule is on pause as seen from a day.
     *
     * Paused now: the day it was paused and every day after. Paused and since
     * taken back: the days in between, and the day it was paused if pausing
     * set that day aside. Days before the pause were kept as usual and are
     * shown as they were, and the day it is taken back is an ordinary day.
     */
    fun isOnPause(rule: Rule, on: CalendarDate): Boolean {
        if (rule.isArchived) return false
        val paused = pauseDay(rule)
        if (paused != null) return on >= paused

        val mine = activations.filter { it.ruleID == rule.id }
        if (mine.none { it.from > on }) return false
        if (isCovered(rule, on)) {
            return mine.any { it.to == on } && occurrences.any {
                it.ruleID == rule.id && it.date == on && it.status == OccurrenceStatus.SKIPPED
            }
        }
        return mine.any { stretch -> stretch.to?.let { it < on } ?: false }
    }

    /**
     * Whether a day of a rule is set aside and outside every stretch: the days
     * a pause leaves without a card, and not a day anything was asked of.
     */
    fun isPausedAndNotAsked(rule: Rule, on: CalendarDate): Boolean =
        isOnPause(rule, on) && !isCovered(rule, on)

    private fun isCovered(rule: Rule, on: CalendarDate): Boolean =
        activations.any { it.ruleID == rule.id && it.covers(on) }

    /**
     * Pausing a rule as of a day, as a plan to apply.
     *
     * The day it is paused still counts if it was kept. If it was due and
     * nothing was recorded, the day is stood down instead, so pausing first
     * and keeping nothing never reads as a miss. The stand-down stays after
     * the rule is taken back.
     */
    fun pausePlan(rule: Rule, on: CalendarDate): EditPlan {
        val plan = EditPlanner().pause(rule, activations, on)
        val unrecordedAndDue = entries(on).any {
            it.rule.id == rule.id && it.occurrence == null && it.dispensation == null
        }
        if (!unrecordedAndDue) return plan
        return plan.copy(
            newOccurrences = plan.newOccurrences + Occurrence(
                ruleID = rule.id,
                date = on,
                status = OccurrenceStatus.SKIPPED,
            ),
        )
    }

    /**
     * A rule paused and taken back on the same day was never really set aside,
     * so the stand-down the pause wrote for that day goes with it. Null on any
     * other day, and when the person stood the day down themselves earlier.
     */
    fun standDownLiftedOnResume(rule: Rule, on: CalendarDate): Occurrence? {
        if (pauseDay(rule) != on) return null
        return occurrences.firstOrNull {
            it.ruleID == rule.id && it.date == on && it.status == OccurrenceStatus.SKIPPED
        }
    }

    /**
     * Paused rules on the days after the pause on which they would have fallen.
     *
     * Home lists what is due, so a paused rule would otherwise vanish the day
     * after it was paused. These are shown greyed. They stay out of [entries]:
     * nothing was asked, so they must never settle a day, raise a reminder, or
     * change a score.
     */
    fun pausedEntries(on: CalendarDate): List<DayEntry> =
        rules.mapNotNull { rule ->
            if (!isPausedAndNotAsked(rule, on)) return@mapNotNull null
            val hypothetical = listOf(Activation(ruleID = rule.id, from = on, to = on))
            if (engine.dueDates(rule, hypothetical, on, on).isEmpty()) return@mapNotNull null
            DayEntry(rule, on, occurrence = null, dispensation = null)
        }.sortedWith { a, b -> shownBefore(a, b) }

    /** Rules that may still be reminded of: all but those the person has paused. */
    fun rulesNotOnPause(on: CalendarDate): List<Rule> =
        rules.filterNot { isOnPause(it, on) }

    /** What Home shows: the rules that are due, then the paused rules that would have been. */
    fun entriesIncludingPaused(on: CalendarDate): List<DayEntry> =
        (entries(on) + pausedEntries(on)).sortedWith { a, b -> shownBefore(a, b) }

    // MARK: repairs

    /**
     * Observances that must be turned on because a rule depends on them.
     *
     * A rule tied to the church calendar can never come due while its observance
     * is merely shown — it sits on the list and is invisible. That happens to a
     * rule taken on before this was handled, or restored from an older backup,
     * so it is repaired on load rather than only when taken on.
     */
    fun observancesNeeded(): List<LiturgicalTrigger> =
        rules.filterNot { it.isArchived }
            .mapNotNull { rule ->
                val recurrence = rule.recurrence as? Recurrence.Liturgical ?: return@mapNotNull null
                if (activations.none { it.ruleID == rule.id && it.isOpen }) return@mapNotNull null
                if (settings.observances.settingFor(recurrence.trigger).drivesRules) {
                    return@mapNotNull null
                }
                recurrence.trigger
            }

    /**
     * Someone who already has rules has plainly been here before, whatever the
     * stored flag says. Showing them the first-run screen would be absurd.
     */
    val shouldMarkFirstRunComplete: Boolean
        get() = !settings.hasCompletedFirstRun && rules.isNotEmpty()

    // MARK: progress

    fun report(
        days: Int = 30,
        today: CalendarDate,
        zone: ZoneId = ZoneId.systemDefault(),
        now: Instant = Instant.now(),
    ): ProgressReport {
        val through = progressThrough(today)
        return ScoringEngine(engine, zone).report(
            rules = rules,
            activations = activations,
            occurrences = occurrences,
            from = through.plusDays(-(days - 1)),
            through = through,
            now = now,
            liturgicalHistoryFrom = settings.reckoningChangedOn,
        )
    }

    companion object {
        /**
         * Timed first and in order; untimed after, among themselves by title.
         * Two rules at the same time keep the order they came in.
         */
        private fun shownBefore(a: DayEntry, b: DayEntry): Int {
            val x = a.rule.timeOfDay
            val y = b.rule.timeOfDay
            return when {
                x != null && y != null -> x.compareTo(y)
                x == null && y != null -> 1
                x != null && y == null -> -1
                else -> a.rule.title.compareTo(b.rule.title)
            }
        }

        /**
         * The last day progress speaks about: yesterday.
         *
         * Today is deliberately outside it. A day still in progress is not a
         * verdict — a rule added this morning and not yet kept would otherwise
         * count against someone before they had the chance.
         */
        fun progressThrough(today: CalendarDate): CalendarDate = today.plusDays(-1)
    }
}
