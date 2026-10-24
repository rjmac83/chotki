package org.chotki.core

import kotlinx.serialization.json.Json
import java.time.Instant
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * A paused rule stays visible, and a reset must never turn a long record into
 * a long list of misses. Translated from the Swift pause and reset suites.
 */
private fun day(y: Int, m: Int, d: Int): CalendarDate =
    CalendarDate.of(y, m, d) ?: error("$y-$m-$d is not a date")

private object PauseCalendar : LiturgicalDayProvider {
    override fun isFastDay(date: CalendarDate): Boolean =
        date.weekday == Weekday.WEDNESDAY || date.weekday == Weekday.FRIDAY
    override fun isGreatFeast(date: CalendarDate): Boolean = false
    override fun season(date: CalendarDate): FastingSeason? = null
    override fun fastFreeReason(date: CalendarDate): String? = null
}

class PauseAndResetTest {
    private val monday = day(2026, 8, 17)
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    private fun daily(title: String = "Evening prayers") =
        Rule(title = title, recurrence = Recurrence.Daily)

    private fun practice(
        rule: Rule,
        closedOn: CalendarDate?,
        markedPaused: Boolean,
        extra: List<Activation> = emptyList(),
        occurrences: List<Occurrence> = emptyList(),
    ): Practice {
        val settings = if (markedPaused) {
            AppSettings.DEFAULT.copy(pausedRuleIDs = listOf(rule.id))
        } else {
            AppSettings.DEFAULT
        }
        return Practice(
            rules = listOf(rule),
            activations = listOf(Activation(ruleID = rule.id, from = day(2026, 1, 1), to = closedOn)) + extra,
            occurrences = occurrences,
            settings = settings,
            liturgical = PauseCalendar,
        )
    }

    private fun kept(rule: Rule, dates: List<CalendarDate>) =
        dates.map { Occurrence(ruleID = rule.id, date = it, status = OccurrenceStatus.COMPLETED) }

    @Test
    fun `the day it was paused still counts, and is the first day shown as paused`() {
        val rule = daily()
        val p = practice(rule, monday, markedPaused = true)
        assertEquals(monday, p.pauseDay(rule))
        assertEquals(listOf(rule.id), p.entries(monday).map { it.rule.id })
        assertTrue(p.isOnPause(rule, monday))
        assertTrue(!p.isOnPause(rule, monday.plusDays(-1)))
    }

    @Test
    fun `later days show the paused rule, apart from the days that are due`() {
        val rule = daily()
        val p = practice(rule, monday, markedPaused = true)
        val tuesday = monday.plusDays(1)
        assertTrue(p.entries(tuesday).isEmpty())
        assertEquals(listOf(rule.id), p.pausedEntries(tuesday).map { it.rule.id })
        assertEquals(listOf(rule.id), p.entriesIncludingPaused(tuesday).map { it.rule.id })
        assertTrue(p.pausedEntries(monday).isEmpty())
        assertEquals(1, p.entriesIncludingPaused(monday).size)
    }

    @Test
    fun `a paused rule shows only on the days it would have fallen`() {
        val rule = Rule(title = "Wednesday fast", recurrence = Recurrence.Weekly(setOf(Weekday.WEDNESDAY)))
        val p = practice(rule, monday, markedPaused = true)
        assertTrue(p.pausedEntries(day(2026, 8, 18)).isEmpty())
        assertEquals(1, p.pausedEntries(day(2026, 8, 19)).size)
    }

    @Test
    fun `paused entries are never asked of anyone`() {
        val rule = daily()
        val p = practice(
            rule, monday, markedPaused = true,
            occurrences = listOf(Occurrence(ruleID = rule.id, date = monday, status = OccurrenceStatus.COMPLETED)),
        )
        val tuesday = monday.plusDays(1)
        assertTrue(p.entries(tuesday).isEmpty())
        assertTrue(!p.isSettled(tuesday))
        val report = p.report(days = 4, today = tuesday.plusDays(3), now = Instant.parse("2026-08-20T12:00:00Z"))
        assertTrue(report.perRule.all { it.missed == 0 })
    }

    @Test
    fun `a rule closed by an edit is not shown as paused`() {
        val rule = daily()
        val p = practice(rule, monday, markedPaused = false)
        assertNull(p.pauseDay(rule))
        assertTrue(!p.isOnPause(rule, monday.plusDays(3)))
        assertTrue(p.pausedEntries(monday.plusDays(1)).isEmpty())
    }

    @Test
    fun `resuming clears it, even if the marker is left behind`() {
        val rule = daily()
        val resumed = Activation(ruleID = rule.id, from = monday.plusDays(2))
        val p = practice(rule, monday, markedPaused = true, extra = listOf(resumed))
        assertNull(p.pauseDay(rule))
        assertTrue(p.pausedEntries(monday.plusDays(3)).isEmpty())
    }

    @Test
    fun `a removed rule is not shown as paused`() {
        val rule = daily().copy(archivedAt = Instant.parse("2026-08-17T12:00:00Z"))
        val p = practice(rule, monday, markedPaused = true)
        assertNull(p.pauseDay(rule))
        assertTrue(p.pausedEntries(monday.plusDays(1)).isEmpty())
    }

    @Test
    fun `a record written before pausing was recorded decodes as having none`() {
        val old = """{"displayName":""}"""
        val decoded = json.decodeFromString(AppSettings.serializer(), old)
        assertTrue(decoded.pausedRuleIDs.isEmpty())
    }

    @Test
    fun `the paused marker survives a round trip`() {
        val id = UUID.fromString("11111111-1111-1111-1111-111111111111")
        val settings = AppSettings.DEFAULT.copy(pausedRuleIDs = listOf(id))
        val back = json.decodeFromString(AppSettings.serializer(), json.encodeToString(AppSettings.serializer(), settings))
        assertEquals(listOf(id), back.pausedRuleIDs)
    }

    private fun pausedAndResumed(pauseRecorded: Boolean = true): Pair<Rule, Practice> {
        val rule = daily()
        val standDown = if (pauseRecorded) {
            listOf(Occurrence(ruleID = rule.id, date = day(2026, 8, 15), status = OccurrenceStatus.SKIPPED))
        } else {
            emptyList()
        }
        val occurrences = kept(rule, (10..14).map { day(2026, 8, it) }) +
            kept(rule, listOf(day(2026, 8, 20), day(2026, 8, 21))) +
            standDown
        val p = Practice(
            rules = listOf(rule),
            activations = listOf(
                Activation(ruleID = rule.id, from = day(2026, 1, 1), to = day(2026, 8, 15)),
                Activation(ruleID = rule.id, from = day(2026, 8, 20)),
            ),
            occurrences = occurrences,
            settings = AppSettings.DEFAULT,
            liturgical = PauseCalendar,
        )
        return rule to p
    }

    @Test
    fun `days kept before a pause stay kept`() {
        val (_, p) = pausedAndResumed()
        val score = p.report(days = 14, today = day(2026, 8, 24), now = Instant.parse("2026-08-24T12:00:00Z")).perRule[0]
        assertEquals(7, score.kept)
        assertEquals(2, score.missed)
        assertEquals(1, score.stoodDown)
        assertEquals(9, score.scoreable)
        assertEquals(listOf(day(2026, 8, 22), day(2026, 8, 23)), score.missedDates)
    }

    @Test
    fun `the day of resuming counts, and so does every day after it`() {
        val (rule, p) = pausedAndResumed()
        assertNull(p.pauseDay(rule))
        val onResume = p.entries(day(2026, 8, 20))
        assertEquals(listOf(rule.id), onResume.map { it.rule.id })
        assertTrue(onResume[0].isKept)
        assertTrue(p.entries(day(2026, 8, 17)).isEmpty())
    }

    @Test
    fun `the day it is paused counts as kept if it was kept`() {
        val rule = daily()
        val p = Practice(
            rules = listOf(rule),
            activations = listOf(Activation(ruleID = rule.id, from = day(2026, 8, 10), to = day(2026, 8, 12))),
            occurrences = kept(rule, listOf(day(2026, 8, 12))),
            settings = AppSettings.DEFAULT.copy(pausedRuleIDs = listOf(rule.id)),
            liturgical = PauseCalendar,
        )
        val score = p.report(days = 5, today = day(2026, 8, 14), now = Instant.parse("2026-08-14T12:00:00Z")).perRule[0]
        assertEquals(1, score.kept)
        assertEquals(2, score.missed)
    }

    @Test
    fun `a rule ended and taken back, with nothing written for its last day, counts that day`() {
        val (_, p) = pausedAndResumed(pauseRecorded = false)
        val score = p.report(days = 14, today = day(2026, 8, 24), now = Instant.parse("2026-08-24T12:00:00Z")).perRule[0]
        assertEquals(3, score.missed)
    }

    @Test
    fun `a day with one rule kept and another paused is settled`() {
        val morning = daily("Morning prayers")
        val evening = daily("Evening prayers")
        val today = day(2026, 8, 19)
        val p = Practice(
            rules = listOf(morning, evening),
            activations = listOf(
                Activation(ruleID = morning.id, from = day(2026, 1, 1)),
                Activation(ruleID = evening.id, from = day(2026, 1, 1), to = today),
            ),
            occurrences = kept(morning, listOf(today)),
            settings = AppSettings.DEFAULT.copy(pausedRuleIDs = listOf(evening.id)),
            liturgical = PauseCalendar,
        )
        assertTrue(p.isSettled(today))
        assertEquals(listOf(morning.id), p.rulesNotOnPause(today).map { it.id })
    }

    private fun due(rule: Rule, kept: List<CalendarDate> = emptyList()) = Practice(
        rules = listOf(rule),
        activations = listOf(Activation(ruleID = rule.id, from = day(2026, 1, 1))),
        occurrences = kept(rule, kept),
        settings = AppSettings.DEFAULT,
        liturgical = PauseCalendar,
    )

    @Test
    fun `pausing a rule that was due and not kept stands the day down`() {
        val rule = daily()
        val plan = due(rule).pausePlan(rule, monday)
        assertEquals(listOf(OccurrenceStatus.SKIPPED), plan.newOccurrences.map { it.status })
        assertEquals(monday, plan.newOccurrences.first().date)
        assertEquals(monday, plan.updatedActivations.first().to)
    }

    @Test
    fun `pausing a rule already kept that day leaves the record alone`() {
        val rule = daily()
        assertTrue(due(rule, listOf(monday)).pausePlan(rule, monday).newOccurrences.isEmpty())
    }

    @Test
    fun `pausing a rule on a day it was not due writes nothing`() {
        val rule = Rule(title = "Wednesday fast", recurrence = Recurrence.Weekly(setOf(Weekday.WEDNESDAY)))
        assertTrue(due(rule).pausePlan(rule, monday).newOccurrences.isEmpty())
    }

    @Test
    fun `pausing and taking it back the same day leaves the day as it was`() {
        val rule = daily()
        val paused = Practice(
            rules = listOf(rule),
            activations = listOf(Activation(ruleID = rule.id, from = day(2026, 1, 1), to = monday)),
            occurrences = listOf(Occurrence(ruleID = rule.id, date = monday, status = OccurrenceStatus.SKIPPED)),
            settings = AppSettings.DEFAULT.copy(pausedRuleIDs = listOf(rule.id)),
            liturgical = PauseCalendar,
        )
        assertEquals(monday, paused.standDownLiftedOnResume(rule, monday)?.date)
        assertNull(paused.standDownLiftedOnResume(rule, monday.plusDays(1)))
    }

    @Test
    fun `after a pause is undone, the days in between and the day it began stay set aside`() {
        val (rule, p) = pausedAndResumed()
        assertTrue(p.isOnPause(rule, day(2026, 8, 15)))
        assertTrue(p.isOnPause(rule, day(2026, 8, 17)))
        assertTrue(p.isPausedAndNotAsked(rule, day(2026, 8, 17)))
        assertEquals(listOf(rule.id), p.pausedEntries(day(2026, 8, 17)).map { it.rule.id })
        assertTrue(!p.isOnPause(rule, day(2026, 8, 14)))
        assertTrue(!p.isOnPause(rule, day(2026, 8, 20)))
        assertTrue(!p.isOnPause(rule, day(2026, 8, 22)))
    }

    @Test
    fun `a day paused after it was already kept is shown as it was kept`() {
        val rule = daily()
        val p = Practice(
            rules = listOf(rule),
            activations = listOf(
                Activation(ruleID = rule.id, from = day(2026, 1, 1), to = day(2026, 8, 15)),
                Activation(ruleID = rule.id, from = day(2026, 8, 20)),
            ),
            occurrences = kept(rule, listOf(day(2026, 8, 15))),
            settings = AppSettings.DEFAULT,
            liturgical = PauseCalendar,
        )
        assertTrue(!p.isOnPause(rule, day(2026, 8, 15)))
        assertTrue(p.isOnPause(rule, day(2026, 8, 16)))
    }

    @Test
    fun `a rule in force begins again today, and its earlier stretches go`() {
        val rule = daily("Morning prayers")
        val today = day(2026, 10, 24)
        val old = Activation(ruleID = rule.id, from = day(2026, 1, 1), to = day(2026, 3, 1))
        val current = Activation(ruleID = rule.id, from = day(2026, 4, 1))
        val plan = RecordReset().plan(listOf(rule), listOf(old, current), emptySet(), today)
        assertEquals(listOf(current.id), plan.updatedActivations.map { it.id })
        assertEquals(today, plan.updatedActivations.first().from)
        assertNull(plan.updatedActivations.first().to)
        assertEquals(listOf(old.id), plan.removedActivationIDs)
    }

    @Test
    fun `a paused rule stays paused, as one stood-down day`() {
        val rule = daily()
        val today = day(2026, 10, 24)
        val pausedOn = day(2026, 9, 10)
        val stretch = Activation(ruleID = rule.id, from = day(2026, 1, 1), to = pausedOn)
        val plan = RecordReset().plan(listOf(rule), listOf(stretch), setOf(rule.id), today)
        assertEquals(pausedOn, plan.updatedActivations.first().from)
        assertEquals(pausedOn, plan.updatedActivations.first().to)
        assertEquals(listOf(OccurrenceStatus.SKIPPED), plan.newOccurrences.map { it.status })
        assertEquals(pausedOn, plan.newOccurrences.first().date)
    }

    @Test
    fun `a rule that only ended has nothing left to hold`() {
        val rule = daily()
        val stretch = Activation(ruleID = rule.id, from = day(2026, 1, 1), to = day(2026, 8, 1))
        val plan = RecordReset().plan(listOf(rule), listOf(stretch), emptySet(), day(2026, 10, 24))
        assertEquals(listOf(stretch.id), plan.removedActivationIDs)
        assertTrue(plan.updatedActivations.isEmpty())
    }

    @Test
    fun `after a reset, nothing in the past can be missed`() {
        val today = day(2026, 10, 24)
        val inForce = daily("Morning prayers")
        val paused = daily("Evening prayers")
        val ended = daily("Almsgiving")
        val pausedOn = day(2026, 9, 10)
        val activations = listOf(
            Activation(ruleID = inForce.id, from = day(2026, 1, 1)),
            Activation(ruleID = paused.id, from = day(2026, 1, 1), to = pausedOn),
            Activation(ruleID = ended.id, from = day(2026, 1, 1), to = day(2026, 8, 1)),
        )
        val plan = RecordReset().plan(
            listOf(inForce, paused, ended), activations, setOf(paused.id), today,
        )
        val after = activations.filter { it.id !in plan.removedActivationIDs }.map { existing ->
            plan.updatedActivations.firstOrNull { it.id == existing.id } ?: existing
        }
        val practice = Practice(
            rules = listOf(inForce, paused, ended),
            activations = after,
            occurrences = plan.newOccurrences,
            settings = AppSettings.DEFAULT.copy(pausedRuleIDs = listOf(paused.id)),
            liturgical = PauseCalendar,
        )
        val report = practice.report(days = 90, today = today, now = Instant.parse("2026-10-24T12:00:00Z"))
        assertTrue(report.perRule.all { it.missed == 0 })
        assertNull(report.overall)
        assertTrue(practice.isOnPause(paused, pausedOn.plusDays(1)))
        assertEquals(listOf(inForce.id), practice.entries(today).map { it.rule.id })
    }
}
