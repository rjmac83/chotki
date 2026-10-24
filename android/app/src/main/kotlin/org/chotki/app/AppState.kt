package org.chotki.app

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import org.chotki.app.platform.AndroidDb
import org.chotki.app.platform.AndroidHttp
import org.chotki.app.platform.Reminders
import org.chotki.core.Activation
import org.chotki.core.Akathist
import org.chotki.core.AppSettings
import org.chotki.core.CalendarDate
import org.chotki.core.ClockStyle
import org.chotki.core.CustomLibrary
import org.chotki.core.DayEntry
import org.chotki.core.DayRollover
import org.chotki.core.EditPlanner
import org.chotki.core.EditScope
import org.chotki.core.Occurrence
import org.chotki.core.OccurrenceStatus
import org.chotki.core.LiturgicalDay
import org.chotki.core.NoLiturgicalData
import org.chotki.core.Practice
import org.chotki.core.RecordReset
import org.chotki.core.PrayerScreen
import org.chotki.core.Rule
import org.chotki.core.RuleReference
import org.chotki.core.reference
import org.chotki.core.content.Content
import org.chotki.core.content.model
import org.chotki.core.content.modelCategory
import org.chotki.core.content.modelReminders
import org.chotki.core.content.modelTimeOfDay
import org.chotki.core.liturgical.LiturgicalService
import org.chotki.core.liturgical.OrthocalClient
import org.chotki.core.store.SqliteStore
import org.chotki.core.Weekday
import org.chotki.core.store.Store
import org.chotki.core.store.exportJson
import org.chotki.core.store.importJson
import java.time.Instant
import java.time.ZoneId
import java.util.UUID

/**
 * What the screens read, and the only thing that writes.
 *
 * Deliberately thin. Everything it is asked — what is due today, whether a day
 * is settled, what the progress says — is answered by `Practice` in `:core`.
 * The macOS app learned this the hard way: decisions that lived in its view
 * model were the ones a port would have had to rewrite, and the ones every bug
 * found by hand was in.
 */
class AppState(
    private val store: Store,
    private val zone: ZoneId = ZoneId.systemDefault(),
    /**
     * The church calendar. Null in tests that have no business reaching a
     * network, which answers "no" to every question rather than pretending.
     */
    val liturgical: LiturgicalService? = null,
) {

    companion object {
        fun open(context: Context): AppState {
            val store = SqliteStore(AndroidDb.open(context))
            return AppState(
                store = store,
                liturgical = LiturgicalService(store, OrthocalClient(AndroidHttp())),
            ).also { it.appContext = context.applicationContext }
        }
    }

    /**
     * Set only when the real app opens the state, so a change to a rule can
     * reschedule its alarms there and then.
     *
     * Null under test, which is deliberate: no test may reach the device's
     * alarm manager. It also means a test that wanted to check rescheduling
     * would have to say so, rather than doing it by accident.
     */
    private var appContext: Context? = null

    /**
     * Alarms follow the rules. Called after anything that changes when a rule
     * is due — until now this happened only in `onResume`, so a reminder set in
     * the editor did not schedule until the app had been backgrounded and
     * reopened, which looks exactly like reminders not working.
     */
    private fun rescheduleReminders() {
        appContext?.let { Reminders.rearm(it, zone = zone) }
    }

    var settings by mutableStateOf(AppSettings.DEFAULT)
        private set
    var rules by mutableStateOf<List<Rule>>(emptyList())
        private set
    var activations by mutableStateOf<List<Activation>>(emptyList())
        private set
    var occurrences by mutableStateOf<List<Occurrence>>(emptyList())
        private set
    /**
     * What the prayers screen is showing, and where the count has got to.
     *
     * Here rather than remembered inside `RopeScreen`, because a composition
     * dies when you leave it: switching to the Reading and coming back lost a
     * hundred-knot count, and so did following a word into the glossary. Held
     * as the `MutableState` itself so the screen can keep writing through
     * `by`, which is how core's `PrayerScreen` wants to be used.
     */
    val prayers = mutableStateOf(PrayerScreen())

    /**
     * Chooses the prayer the rope should be counting, before the screen opens.
     *
     * "Ready to begin immediately" is the whole of the request, so the choice
     * is made here rather than left to the chooser at the top of the rope.
     * `choose` is a no-op when the prayer is already selected, which is what
     * lets someone step away and come back to a count still running.
     */
    fun countOnTheRope(prayerID: String) {
        prayers.value = prayers.value.choosing(prayerID)
    }

    var selectedDate by mutableStateOf(CalendarDate.from(Instant.now(), zone))
    var visibleMonth by mutableStateOf(CalendarDate.from(Instant.now(), zone))

    /**
     * The day this state last believed was today.
     *
     * Not a "follow today" flag: comparing the selection against this is what
     * tells [DayRollover] whether the view was on today, and it means tapping
     * back onto today resumes following with nothing to keep in step.
     */
    private var lastKnownToday: CalendarDate = CalendarDate.from(Instant.now(), zone)

    val today: CalendarDate get() = CalendarDate.from(Instant.now(), zone)

    private val practice: Practice
        get() {
            // The four lists below are snapshot state, so a screen reading
            // through Practice redraws when a rule is taken up or a box ticked.
            // The calendar is not — the service holds it in a plain map — so
            // read the counter here, once, on behalf of every screen. A rule
            // that is due only because of the church calendar (the Dormition
            // Fast) would otherwise not appear until the app was restarted,
            // and no screen author would think to ask for it.
            calendarVersion
            return Practice(
                rules, activations, occurrences, settings,
                liturgical ?: NoLiturgicalData,
            )
        }

    /** The church calendar for a day, if it has been fetched. */
    fun liturgicalDay(date: CalendarDate): LiturgicalDay? {
        calendarVersion
        return liturgical?.cachedDay(date)
    }

    /**
     * Load a stretch of the calendar into memory before a strip is dragged
     * across it. Does not redraw by itself: the days were already absent.
     */
    fun warmCalendar(from: CalendarDate, through: CalendarDate) {
        liturgical?.absorb(from, through)
    }

    /**
     * Fetch the church day when the selection has moved away from the
     * fortnight already kept. The Akathist does not wait on this — its Friday
     * comes from Pascha — but the fast, the feast and the readings do.
     */
    fun ensureChurchDay(around: CalendarDate) {
        val service = liturgical ?: return
        val far = kotlin.math.abs(today.daysUntil(around)) > 7
        val missing = service.cachedDay(around) == null
        if (!far && !missing) return
        Thread {
            runCatching { service.refresh(from = around.plusDays(-7), days = 15) }
            calendarVersion += 1
        }
    }

    /**
     * Whether this day is on screen from the cache because the network could not be reached. A day
     * inside the calendar that ships with the app never is.
     */
    fun isOffline(date: CalendarDate): Boolean = liturgical?.isOffline(date) ?: false

    fun load() {
        settings = store.loadSettings() ?: AppSettings.DEFAULT
        // A record that finished the welcome before this date existed would
        // otherwise be asked for a spiritual father on the first launch.
        if (settings.hasCompletedFirstRun && settings.firstRunOn == null) {
            val stamped = settings.copy(firstRunOn = today)
            store.saveSettings(stamped)
            settings = stamped
        }
        rules = store.rules()
        restoreAkathistAppointment()
        activations = store.activations()
        occurrences = store.occurrences()
        // Idempotent, and it fills a gap rather than overwriting, so a question
        // changed here survives every launch.
        liturgical?.let { service ->
            service.setJurisdiction(settings.jurisdiction, around = today, window = 21)
        }
        calendarVersion += 1
    }

    /**
     * An Akathist still set for every Saturday is given the church's Fridays.
     * Which of them it is comes from the selected church, through the same
     * Pascha count the day list already uses. The old calendar and the new
     * share those Fridays.
     */
    private fun restoreAkathistAppointment() {
        val repaired = rules.mapNotNull { Akathist.restoredAppointment(it) }
        if (repaired.isEmpty()) return
        repaired.forEach { store.save(it) }
        rules = store.rules()
    }

    /**
     * Bumped whenever the calendar changes, so screens reading through
     * [liturgicalDay] recompose. The service holds its snapshot in a plain map
     * for the sake of the recurrence engine, which asks about forty-two days on
     * every redraw and cannot afford to suspend — so Compose needs telling.
     */
    var calendarVersion by mutableStateOf(0)
        private set

    /**
     * Fills in the fortnight ahead, off the main thread.
     *
     * Never throws and never blocks the interface: a failed refresh is a state
     * the app reflects — "cached" — rather than an error shown where text should
     * be. Opening on a plane shows the day it already has.
     */
    fun refreshCalendar(onDone: () -> Unit = {}) {
        val service = liturgical ?: return
        Thread {
            runCatching { service.refresh(from = today.plusDays(-7), days = 28) }
            runCatching { service.loadSnapshot(around = today, window = 21) }
            // Snapshot state is safe to write from any thread, and this is what
            // tells the screens the fortnight has arrived. Without it the days
            // were fetched and stored and nothing redrew.
            calendarVersion += 1
            onDone()
        }.start()
    }

    /**
     * True when the calendar has never been fetched at all.
     *
     * Distinguished from "not fetched *this* day" so the empty reading can say
     * which it is. A permission that was never declared and a network that is
     * merely down look identical from here, and both looked like "it will fill
     * in shortly" — which was a promise the app could not keep.
     */
    val hasNoCalendarAtAll: Boolean
        get() = liturgical?.let { service ->
            calendarVersion
            (0..3).none { service.cachedDay(today.plusDays(it)) != null }
        } ?: true

    /**
     * The record, as a file that outlives the app.
     *
     * Android is given no permission to back this app up — a record of
     * someone's prayer life is not something to hand to Google — so this is the
     * only way it reaches a new phone. See [org.chotki.app.ui.Keeping].
     */
    fun exportJson(): String = store.exportJson()

    /** Merges a backup in and reloads. Nothing already here is removed. */
    fun restoreFrom(text: String) {
        store.importJson(text)
        load()
    }

    /**
     * Any change to the settings, with the consequences that follow it.
     *
     * The reckoning is the one that bites. Moving it shifts every fast and
     * feast by thirteen days, and without [AppSettings.reckoningChangedOn] the
     * scoring re-derives the past from the new calendar — turning a fortnight
     * someone actually kept into a fortnight of misses. Stamping the date stops
     * scoring reaching back past it.
     */
    fun updateSettings(change: (AppSettings) -> AppSettings) {
        val before = settings
        val updated = change(before)
        val reckoningChanged =
            updated.jurisdiction.reckoning != before.jurisdiction.reckoning
        val settled = if (reckoningChanged) updated.copy(reckoningChangedOn = today) else updated

        store.saveSettings(settled)
        settings = settled

        if (updated.jurisdiction != before.jurisdiction) {
            // The calendar itself has to be refetched: the same civil day is a
            // different church day under the other reckoning.
            liturgical?.let { runCatching { it.setJurisdiction(settled.jurisdiction, around = today, window = 21) } }
            refreshCalendar()
        }
        // Silence, and the lead, are the policy. The alarms have to hear it
        // now, not the next time the app is opened.
        if (settled.reminders != before.reminders) rescheduleReminders()
        calendarVersion += 1
    }

    /** How times are written, everywhere at once. */
    fun setClockStyle(style: ClockStyle) = updateSettings { it.copy(clockStyle = style) }

    fun entries(on: CalendarDate): List<DayEntry> = practice.entries(on)

    /** Home's list: what is due, and the paused rules that would have been. */
    fun entriesIncludingPaused(on: CalendarDate): List<DayEntry> = practice.entriesIncludingPaused(on)

    fun isSettled(on: CalendarDate): Boolean = practice.isSettled(on)

    fun isPausedOnPurpose(rule: Rule): Boolean = practice.pauseDay(rule) != null

    fun isOnPause(rule: Rule, on: CalendarDate): Boolean = practice.isOnPause(rule, on)

    fun isPausedAndNotAsked(rule: Rule, on: CalendarDate): Boolean =
        practice.isPausedAndNotAsked(rule, on)

    fun report(days: Int = 30) = practice.report(days = days, today = today, zone = zone)

    /**
     * Marking kept and un-marking it.
     *
     * Un-ticking removes the record rather than writing "skipped": absence is
     * the default state, and skipped means something else entirely — a day
     * deliberately stood down, which leaves both sides of the score.
     */
    /**
     * Marking a day settled changes what should be armed, so it reschedules.
     *
     * It did not, and that is half of why a rule went on buzzing after it had
     * been kept — the plan stopped including it and nothing acted on that.
     */
    /**
     * Mark kept, and leave it kept. Scrolling a reading to its end, or finishing
     * the Jesus Prayer, must not clear a mark that is already there.
     *
     * The record is what counts, not the entry a screen happened to be holding.
     * That entry can still say "not yet" after the circle has already been
     * filled, and trusting it would write the mark again instead of leaving it.
     */
    fun markKept(entry: DayEntry) {
        if (entry.isDispensed || keptNow(entry)) return
        toggleKept(entry)
    }

    /**
     * The circle. On, then off, then on again, as many times as it is tapped.
     *
     * Same rule as [markKept]: decide from the record. A tap that still carries
     * the entry from before the check appeared must take the mark off, not
     * put it on a second time.
     */
    fun toggleKept(entry: DayEntry) {
        if (entry.isDispensed) return
        if (keptNow(entry)) {
            store.removeOccurrence(entry.rule.id, entry.date)
        } else {
            val late = entry.date < today
            store.save(
                Occurrence(
                    ruleID = entry.rule.id,
                    date = entry.date,
                    status = if (late) OccurrenceStatus.COMPLETED_LATE else OccurrenceStatus.COMPLETED,
                    completedAt = Instant.now(),
                ),
            )
        }
        load()
        rescheduleReminders()
    }

    private fun keptNow(entry: DayEntry): Boolean =
        occurrences.any {
            it.ruleID == entry.rule.id &&
                it.date == entry.date &&
                (it.status == OccurrenceStatus.COMPLETED ||
                    it.status == OccurrenceStatus.COMPLETED_LATE)
        }

    /**
     * Kept, but after its moment had passed.
     *
     * Deliberately a thing you say rather than a thing the app works out.
     * Someone who kept a rule and only remembered to tick it afterwards has not
     * done anything late; only choosing this means it.
     */
    fun markKeptLate(entry: DayEntry) {
        store.save(
            Occurrence(
                ruleID = entry.rule.id,
                date = entry.date,
                status = OccurrenceStatus.COMPLETED_LATE,
                completedAt = Instant.now(),
            ),
        )
        load()
        rescheduleReminders()
    }

    fun isPaused(rule: Rule): Boolean = practice.isPaused(rule)

    /**
     * Stops a rule from today, keeping everything it has kept.
     *
     * Pausing removes days from the record rather than counting them against
     * anyone — the whole point of it, and the reason it is not "give up".
     */
    fun pause(rule: Rule) {
        // Only a rule that is in force can be paused. The plan is taken before
        // the marker is written, while the stretch is still open.
        if (practice.isPaused(rule)) return
        val plan = practice.pausePlan(rule, today)
        markPaused(rule, true)
        store.apply(plan)
        load()
        rescheduleReminders()
    }

    fun resume(rule: Rule) {
        // Same day: the stand-down the pause wrote goes with it, while the
        // marker is still set. Then the marker is cleared, then the stretch opens.
        val lifted = practice.standDownLiftedOnResume(rule, today)
        if (lifted != null) store.removeOccurrence(lifted.ruleID, lifted.date)
        markPaused(rule, false)
        store.apply(EditPlanner().resume(rule, today))
        load()
        rescheduleReminders()
    }

    /** Remembers that the person paused a rule, or took it back. */
    private fun markPaused(rule: Rule, paused: Boolean) {
        if ((rule.id in settings.pausedRuleIDs) == paused) return
        val ids = settings.pausedRuleIDs.filterNot { it == rule.id }
        val updated = settings.copy(pausedRuleIDs = if (paused) ids + rule.id else ids)
        store.saveSettings(updated)
        settings = updated
    }

    fun standDown(entry: DayEntry) {
        store.save(
            Occurrence(
                ruleID = entry.rule.id,
                date = entry.date,
                status = OccurrenceStatus.SKIPPED,
            ),
        )
        load()
        rescheduleReminders()
    }

    /** Lifts a stand-down. Absence is the day as it was, not a second status. */
    fun clearOccurrence(entry: DayEntry) {
        store.removeOccurrence(entry.rule.id, entry.date)
        load()
        rescheduleReminders()
    }

    /**
     * Starts the record again from today. Stretches are cut before the history
     * is erased, so a failure part-way cannot turn the past into misses. A
     * backup the person exported themselves is left where they put it. This
     * port has no separate automatic-backup folder to clear.
     */
    fun resetRecord() {
        val plan = RecordReset().plan(
            rules = rules,
            activations = activations,
            pausedRuleIDs = settings.pausedRuleIDs.toSet(),
            today = today,
        )
        store.apply(plan.copy(newOccurrences = emptyList()))
        for (occurrence in store.occurrences()) {
            store.removeOccurrence(occurrence.ruleID, occurrence.date)
        }
        for (standDown in plan.newOccurrences) store.save(standDown)
        load()
        notice = "Your record has been cleared. Counting begins today."
        rescheduleReminders()
    }

    /** Takes a rule on from the library, from today. */
    /**
     * The rule a library template would make, without saving it.
     *
     * So the editor can be shown first, filled in — taking something on is a
     * decision about how often, and asking afterwards meant finding the rule on
     * the day and opening the pencil.
     */
    fun ruleFrom(templateID: String): Rule? {
        val template = Content.ruleLibrary.firstOrNull { it.id == templateID } ?: return null
        return Rule(
            title = template.title,
            note = template.note,
            source = "the library",
            recurrence = template.recurrence.model,
            timeOfDay = template.modelTimeOfDay,
            category = template.modelCategory,
            reminders = template.modelReminders,
            prayerIDs = template.prayerIDs.ifEmpty { null },
        )
    }

    fun take(templateID: String) {
        val rule = ruleFrom(templateID) ?: return
        store.save(rule)
        store.save(Activation(ruleID = rule.id, from = today))
        turnOnNeededObservances()
        load()
        rescheduleReminders()
    }

    /**
     * A rule tied to the church calendar is a clear statement of intent, so the
     * observance it depends on is turned on rather than the rule silently never
     * coming due.
     *
     * Called from [save] as well as [take]: a rule written by hand on fast days
     * has exactly the same problem, and only the library path was covered.
     */
    private fun turnOnNeededObservances() {
        val needed = Practice(
            store.rules(), store.activations(), store.occurrences(), settings,
        ).observancesNeeded()
        if (needed.isEmpty()) return
        var updated = settings
        for (trigger in needed) updated = updated.copy(
            observances = updated.observances.observing(trigger),
        )
        store.saveSettings(updated)
    }

    /**
     * Whether this template is on the rule right now.
     *
     * "On the rule" and "a rule with this title exists" are not the same
     * question, and asking the second one was a bug the Mac had first: removing
     * a rule closes its activation and leaves the row, because the days it kept
     * are still true and deleting them would rewrite the record. So the library
     * went on saying "On your rule" about a rule taken off, and since that
     * label replaces the button there was no way to take it on again.
     */
    fun isTaken(templateID: String): Boolean {
        val title = Content.ruleLibrary.firstOrNull { it.id == templateID }?.title ?: return false
        return rules.any { it.title == title && isOnTheRule(it) }
    }

    // MARK: rules of one's own

    /** The Custom section: rules he wrote, whether or not they are in force. */
    val customEntries: List<Rule>
        get() = CustomLibrary.entries(store.rules(includeArchived = true))

    /** Not archived, and with an open stretch. */
    fun isOnTheRule(rule: Rule): Boolean = !rule.isArchived && !practice.isPaused(rule)

    var notice by mutableStateOf<String?>(null)

    fun save(rule: Rule, from: CalendarDate = today) {
        val existing = store.rule(rule.id)
        store.save(rule)
        if (existing == null) store.save(Activation(ruleID = rule.id, from = from))
        turnOnNeededObservances()
        load()
        rescheduleReminders()
    }

    /**
     * Puts a rule of his own back on the rule, from today.
     *
     * The same rule, not a copy: its history follows it, and the gap shows as a
     * gap rather than as two unrelated rules with the record split between them.
     */
    fun takeUp(rule: Rule) {
        store.save(CustomLibrary.takingUp(rule))
        if (practice.isPaused(rule)) {
            store.save(Activation(ruleID = rule.id, from = today))
        }
        // A stale pause marker would make a later edit look like a pause.
        markPaused(rule, false)
        load()
        rescheduleReminders()
    }

    /** Out of the Custom list. The rule and its history are untouched. */
    fun setAside(rule: Rule) {
        store.save(CustomLibrary.settingAside(rule))
        load()
        rescheduleReminders()
    }

    /** Stops a rule from today onwards, keeping everything it has kept. */
    fun remove(rule: Rule) {
        store.apply(
            EditPlanner().delete(
                rule = rule,
                activations = activations,
                date = today,
                scope = EditScope.WHOLE_SERIES,
            ),
        )
        load()
        rescheduleReminders()
    }

    /**
     * Moves the view on when the day has changed under it.
     *
     * Chotki was opened on the 28th, closed, and opened again on the 29th
     * still showing the 28th — so the rules on screen were yesterday's, and
     * ticking one wrote to the wrong day. A phone is the worst case: the app
     * is rarely quit, so without a check on coming back to the foreground the
     * view can sit on a stale day for a week.
     *
     * Whether to move is [DayRollover]'s decision, not this one. [now] is
     * injectable so the move can be tested without waiting for midnight.
     */
    fun advanceDayIfNeeded(now: CalendarDate = CalendarDate.from(Instant.now(), zone)) {
        if (now == lastKnownToday) return

        val next = DayRollover.selection(
            showing = selectedDate,
            wasToday = lastKnownToday,
            isToday = now,
        )
        lastKnownToday = now

        if (next == selectedDate) return
        selectedDate = next
        // Show the month the day is actually in, or the selection lands
        // off-screen in a grid still displaying somewhere else.
        visibleMonth = next
        load()
    }

    fun rearmReminders(context: Context) = Reminders.rearm(context, zone = zone)

    fun rule(id: UUID): Rule? = rules.firstOrNull { it.id == id }
}
