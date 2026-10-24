package org.chotki.app.platform

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import kotlinx.serialization.json.Json
import org.chotki.core.NotificationRequest

/**
 * What happens when an alarm goes off, and when a button on a reminder is
 * pressed.
 *
 * The alarm carries the whole notification with it rather than an id to look up.
 * A reminder that fires an hour after the app was last killed must not depend on
 * anything still being in memory, and re-deriving it would mean opening the
 * database on the main thread of a broadcast.
 */
class ReminderReceiver : BroadcastReceiver() {

    companion object {
        const val ACTION_FIRE = "org.chotki.FIRE"
        const val EXTRA_RULE_ID = "rule"
        const val EXTRA_DATE = "date"
        const val ACTION_BUTTON = "org.chotki.BUTTON"
        const val EXTRA_REQUEST = "org.chotki.request_json"

        private val json = Json { ignoreUnknownKeys = true }

        fun encode(request: NotificationRequest): String =
            json.encodeToString(NotificationRequest.serializer(), request)

        fun decode(text: String): NotificationRequest =
            json.decodeFromString(NotificationRequest.serializer(), text)
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_FIRE -> {
                val payload = intent.getStringExtra(EXTRA_REQUEST) ?: return
                val ruleID = intent.getStringExtra(EXTRA_RULE_ID)
                val date = intent.getStringExtra(EXTRA_DATE)

                // Asked again at the moment of firing, not only when armed.
                // Cancelling covers the ordinary case, but an alarm held back by
                // Doze can arrive hours late — after the rule was kept, stood
                // down, or removed — and showing it then is the complaint that
                // started this.
                if (ruleID != null && date != null) {
                    val result = goAsync()
                    Thread {
                        try {
                            if (stillWanted(context, ruleID, date)) {
                                AndroidNotifier(context).show(decode(payload))
                            }
                        } finally {
                            result.finish()
                        }
                    }.start()
                } else {
                    AndroidNotifier(context).show(decode(payload))
                }
            }

            ACTION_BUTTON -> {
                val requestID = intent.getStringExtra(AndroidNotifier.EXTRA_REQUEST_ID) ?: return
                val actionID = intent.getStringExtra(AndroidNotifier.EXTRA_ACTION_ID) ?: return
                // Taken down as soon as it is acted on, whichever button it was.
                AndroidNotifier(context).cancel(listOf(requestID))
                PendingActions.record(requestID, actionID)
            }
        }
    }
}

/**
 * Button presses, held until something is awake to apply them.
 *
 * A broadcast receiver has a few milliseconds and no business opening a
 * database. Marking a rule kept is a decision `:core` makes against the store,
 * so the press is recorded here and applied when the app next runs.
 */
object PendingActions {
    private val lock = Any()
    private val recorded = mutableListOf<Pair<String, String>>()

    fun record(requestID: String, actionID: String) {
        synchronized(lock) { recorded.add(requestID to actionID) }
    }

    /** Returns what has accumulated and clears it. */
    fun drain(): List<Pair<String, String>> = synchronized(lock) {
        val out = recorded.toList()
        recorded.clear()
        out
    }
}

/**
 * Whether a reminder should still be shown, asked of the record itself.
 *
 * A receiver has a few milliseconds on the main thread, so this runs on
 * `goAsync` — it opens the database, which is exactly what a receiver must not
 * do inline.
 */
private fun stillWanted(context: android.content.Context, ruleID: String, date: String): Boolean {
    val db = AndroidDb.open(context)
    return try {
        val store = org.chotki.core.store.SqliteStore(db)
        val settings = store.loadSettings() ?: org.chotki.core.AppSettings.DEFAULT
        val on = org.chotki.core.CalendarDate.parse(date) ?: return false
        val id = runCatching { java.util.UUID.fromString(ruleID) }.getOrNull() ?: return false

        val scheduler = org.chotki.core.scheduling.Scheduler(
            engine = org.chotki.core.RecurrenceEngine(observances = settings.observances),
            policy = settings.reminders,
        )
        val rules = store.rules()
        val activations = store.activations()
        val occurrences = store.occurrences(from = on, through = on)
        val practice = org.chotki.core.Practice(rules, activations, occurrences, settings)
        scheduler.plan(
            rules = practice.rulesNotOnPause(on),
            activations = activations,
            occurrences = occurrences,
            on = on,
        ).any { it.ruleID == id }
    } catch (e: Exception) {
        // If the record cannot be read, show it. A reminder that arrives when
        // it need not is a smaller failure than one that never arrives.
        true
    } finally {
        db.close()
    }
}
