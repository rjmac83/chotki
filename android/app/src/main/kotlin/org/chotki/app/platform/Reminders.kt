package org.chotki.app.platform

import android.content.Context
import org.chotki.core.AppSettings
import org.chotki.core.CalendarDate
import org.chotki.core.RecurrenceEngine
import org.chotki.core.scheduling.Scheduler
import org.chotki.core.store.SqliteStore
import java.time.Instant
import java.time.ZoneId

/**
 * The one place the app turns a stored rule into an armed alarm.
 *
 * Everything here is bookkeeping: what to remind about, and when, is decided by
 * `Scheduler` in `:core`, which knows nothing about Android.
 */
object Reminders {

    fun rearm(context: Context, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()) {
        val db = AndroidDb.open(context)
        try {
            val store = SqliteStore(db)
            val settings = store.loadSettings() ?: AppSettings.DEFAULT
            val today = CalendarDate.from(now, zone)

            val scheduler = Scheduler(
                engine = RecurrenceEngine(observances = settings.observances),
                policy = settings.reminders,
                zone = zone,
            )

            val tomorrow = today.plusDays(1)
            val rules = store.rules()
            val activations = store.activations()
            val occurrences = store.occurrences(from = today, through = tomorrow)

            // Today and tomorrow, not today alone.
            //
            // Two things were wrong with one day. Nothing re-arms unless the app
            // is opened, so a day it was not opened had no reminders at all. And
            // "the evening before" fires at 20:00 the day *before* the rule is
            // due, so planning only today could never arm it — that lead has
            // never once worked on this platform.
            //
            // Only what is still ahead: arming an alarm for a moment that has
            // passed fires it immediately, which is how a reboot at lunchtime
            // would deliver the whole morning at once.
            val practice = org.chotki.core.Practice(rules, activations, occurrences, settings)
            val pending = listOf(today, tomorrow).flatMap { day ->
                scheduler.pending(
                    rules = practice.rulesNotOnPause(day),
                    activations = activations,
                    occurrences = occurrences,
                    on = day,
                    after = now,
                )
            }
            ReminderAlarms(context).arm(pending)

            // What is already on screen has to come down too. A notification
            // shown at 06:20 for a rule kept at 06:25 sat there until it was
            // swiped away; core has always had `cancellationIDs` for this and
            // nothing on Android called it.
            val wanted = pending.map { it.request.id }.toSet()
            val todayPractice = org.chotki.core.Practice(rules, activations, emptyList(), settings)
            val stale = scheduler.plan(todayPractice.rulesNotOnPause(today), activations, emptyList(), today)
                .map { it.request.id }
                .filterNot { it in wanted }
            if (stale.isNotEmpty()) AndroidNotifier(context).cancel(stale)
        } finally {
            db.close()
        }
    }
}
