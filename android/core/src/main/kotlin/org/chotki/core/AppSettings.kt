package org.chotki.core

import kotlinx.serialization.Serializable

/**
 * Whether a person has named a church.
 *
 * Written on every new save. A missing key, or a JSON null, on an older record
 * is not this: it means the stored jurisdiction is the church they already chose.
 * [declared] with no name means they said they have no church yet, and the app
 * follows the OCA without showing that name.
 */
@Serializable
data class Affiliation(
    val declared: Boolean = true,
    val name: String? = null,
)

/**
 * Everything the user can change, in one serialisable value.
 *
 * Lives in core so the settings someone has chosen move with their data rather
 * than being tied to one platform's preferences system.
 *
 * Every field has a default, which is the property that matters: the Swift version threw on a missing key, so each new setting made
 * every record written before it unreadable, and this app has already lost
 * someone's settings once.
 */
@Serializable
data class AppSettings(
    val jurisdiction: Jurisdiction = Jurisdiction.DEFAULT,
    val observances: ObservanceSettings = ObservanceSettings.DEFAULT,
    val reminders: org.chotki.core.scheduling.ReminderPolicy =
        org.chotki.core.scheduling.ReminderPolicy.DEFAULT,
    /** Cleared once the first rules have been taken on. */
    val hasCompletedFirstRun: Boolean = false,
    val clockStyle: ClockStyle = ClockStyle.TWENTY_FOUR_HOUR,
    /** The chime when a knot of the prayer rope is complete. */
    val chimeOnCompletion: Boolean = true,
    /**
     * A soft click as each knot passes, so a press is confirmed with your eyes
     * closed.
     */
    val tickEachKnot: Boolean = true,
    /**
     * The day the calendar was last changed, if it ever was.
     *
     * Liturgical rules are the only ones whose due days come from outside the
     * app, and changing the reckoning moves them by thirteen days. Without this,
     * a fast kept faithfully under one calendar is re-scored against the other
     * and reads as a fortnight of failures — which the app must never be able to
     * say. Measured on the Swift side before it was fixed: fourteen kept and
     * none missed became one kept and thirteen missed. See [ScoringEngine].
     */
    val reckoningChangedOn: CalendarDate? = null,
    /**
     * What to call the person. Blank until they write one. Settings writes
     * the same field the welcome does, so a later change is the name that is kept.
     */
    val displayName: String = "",
    /**
     * The spiritual father's name, once one has been given. Blank is not a
     * name, and the app does not invent one. Rules marked as given read this
     * live, so changing it here changes the mark.
     */
    val spiritualFatherName: String = "",
    /**
     * The civil day the welcome was finished. Existing records that already
     * finished it have this stamped on the next launch, so the later question
     * waits thirty days instead of arriving at once.
     */
    val firstRunOn: CalendarDate? = null,
    /**
     * The civil day "Not yet" was chosen. The question waits thirty days from
     * this, or from [firstRunOn] when it has never been deferred.
     */
    val spiritualFatherDeferredOn: CalendarDate? = null,
    /**
     * The Julian date beside the civil one, as "6 Aug o.s."
     *
     * On by default. It is the one setting that starts on, so a day can show
     * both reckonings before anyone has opened Settings. A record that never
     * stored the key gets this default; one that stored false keeps false.
     * The Swift app starts with it off. This port does not, on purpose.
     */
    val showOldStyleDates: Boolean = true,
    /**
     * The percentage on Progress. Off leaves the prose and hides the figure.
     */
    val showConsistencyNumber: Boolean = true,
    /**
     * The caution before writing a rule of one's own.
     *
     * Set only when "Don't show again" was chosen. Clearing a spiritual
     * father's name does not bring the caution back.
     */
    val customCautionDismissed: Boolean = false,
    /**
     * Null only on a record saved before this existed, or on a re-save of one.
     * A new record uses [Affiliation] with [Affiliation.declared] and no name.
     * The property default stays null so a missing key is not read as "no church".
     */
    val affiliation: Affiliation? = null,
    /**
     * Rules the person paused on purpose.
     *
     * Empty when nothing is paused. A missing key on an older record is the
     * same as empty: closing a stretch by an edit is not a pause, and only
     * this list says which closed stretches were.
     */
    val pausedRuleIDs: List<@Serializable(with = UuidSerializer::class) java.util.UUID> = emptyList(),
) {
    /**
     * How a rule says it was given, once a name is stored.
     * Whitespace is not a name. With none stored, callers keep the nameless mark.
     */
    fun givenByPriestPhrase(): String? {
        val name = spiritualFatherName.trim()
        if (name.isEmpty()) return null
        return "Given to me by $name"
    }

    /**
     * Whether to ask if a spiritual father has been found.
     *
     * Not on the day of the welcome. Thirty days after it, or thirty days
     * after the last "Not yet". A stored name ends the question.
     */
    fun shouldAskForSpiritualFather(today: CalendarDate): Boolean {
        if (!hasCompletedFirstRun) return false
        if (spiritualFatherName.trim().isNotEmpty()) return false
        val anchor = spiritualFatherDeferredOn ?: firstRunOn ?: return false
        return today >= anchor.plusDays(30)
    }

    /**
     * The church to show. Null when they have said they have none.
     *
     * An older record with a jurisdiction and no affiliation still shows that
     * church. The OCA name used for the unnamed default is not shown.
     */
    val namedChurch: String?
        get() {
            val affiliation = affiliation ?: return jurisdiction.name
            val trimmed = affiliation.name?.trim().orEmpty()
            if (affiliation.declared && trimmed.isEmpty()) return null
            return trimmed.ifEmpty { jurisdiction.name }
        }

    /**
     * Name a church, or pass null or blank to say there is none.
     *
     * None follows the OCA and shows no church. A known name replaces the
     * jurisdiction with the one the app ships for that church.
     */
    fun chooseChurch(named: String?): AppSettings {
        val trimmed = named?.trim().orEmpty()
        if (trimmed.isEmpty()) {
            return copy(
                affiliation = Affiliation(declared = true, name = null),
                jurisdiction = Jurisdiction.DEFAULT,
            )
        }
        val chosen = Jurisdiction.KNOWN.firstOrNull { it.name == trimmed } ?: return this
        return copy(
            affiliation = Affiliation(name = chosen.name, declared = true),
            jurisdiction = chosen,
        )
    }

    companion object {
        /** A new record: no church named, OCA practice, and that fact written down. */
        val DEFAULT = AppSettings(
            affiliation = Affiliation(declared = true, name = null),
        )
    }
}
