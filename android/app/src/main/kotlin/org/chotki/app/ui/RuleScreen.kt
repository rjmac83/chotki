package org.chotki.app.ui

import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.chotki.app.AppState
import org.chotki.core.CalendarDate
import org.chotki.core.DayEntry
import org.chotki.core.Observance
import org.chotki.core.content.Glossary

/**
 * The day, and what is on the rule for it.
 *
 * Commitments are cards. Only the circle marks one kept, and it sits off the
 * card's own tap, which opens the prayers or the reading. A fast has nothing
 * to open: the card turns over. The circle toggles, including a mark the
 * reading or the rope put there on its own.
 */
@Composable
fun RuleScreen(
    state: AppState,
    modifier: Modifier = Modifier,
    onReadPrayers: (DayEntry) -> Unit = {},
    onReadReading: (Int?) -> Unit = {},
    onReadPsalter: () -> Unit = {},
    onEdit: (DayEntry) -> Unit = {},
    onOpenLibrary: () -> Unit = {},
    /** Straight to the rope, already counting the prayer the rule names. */
    onGoToRope: (String) -> Unit = {},
    /** The glossary, opened at the entry that explains this rule. */
    onOpenTerm: (String) -> Unit = {},
) {
    val entries = state.entriesIncludingPaused(state.selectedDate)

    // Held here rather than inside the calendar, and deliberately not derived
    // from the scroll position any more. It used to fold the moment the rules
    // were touched, so reading your rules took the month away and getting it
    // back meant scrolling to the very top; Ryan asked for a control instead.
    // Surviving the composition is the point: following a rule to its prayers
    // and coming back should find the calendar as it was left.
    var monthOpen by rememberSaveable { mutableStateOf(false) }

    BoxWithConstraints(modifier.fillMaxSize()) {
        // Half, and no more. The calendar used to take whatever it wanted and
        // the rules it sits above were pushed off the bottom of the screen,
        // where nothing could reach them because this column does not scroll.
        val cap = this@BoxWithConstraints.maxHeight / 2

        val glossary = remember(state.settings.jurisdiction.tradition) {
            Glossary.shared(state.settings.jurisdiction.tradition)
        }
        Column(Modifier.fillMaxSize()) {
            Calendar(
                state,
                expanded = monthOpen,
                onToggleExpanded = { monthOpen = !monthOpen },
                maxHeight = cap,
            )
            // One column, in document order. The saying follows whatever is
            // above it. It is not pinned to the bottom of the screen, and a
            // tall day scrolls to reach it.
            //
            // With no rule cards to fill the day, the picture is drawn at the foot of the screen, so the
            // empty space is above it and "Create your first rule" has something to be above. It is
            // still the last thing in the scroll, not fixed there.
            BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
            val viewport = maxHeight
            val noCards = state.rules.isEmpty() || entries.isEmpty()
            Column(
                Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .testTag("the day"),
            ) {
            Column(
                Modifier.fillMaxWidth().defaultMinSize(minHeight = if (noCards) viewport else 0.dp),
                verticalArrangement = Arrangement.SpaceBetween,
            ) {
              Column {
                val liturgical = state.liturgicalDay(state.selectedDate)?.title
                if (liturgical != null) {
                    Text(
                        liturgical,
                        color = Chotki.muted,
                        fontFamily = Chotki.reading,
                        fontSize = 15.5.sp,
                        lineHeight = 22.sp,
                        textAlign = TextAlign.Center,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 18.dp, vertical = 12.dp),
                    )
                }
                FastNote(state)
                DayHeader(state)

                if (state.rules.isEmpty()) {
                    FirstRun(onOpenLibrary)
                } else if (entries.isEmpty()) {
                    EmptyDay(onOpenLibrary)
                } else {
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .padding(start = 18.dp, top = 14.dp, end = 18.dp, bottom = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            "Today's commitments",
                            color = Chotki.muted,
                            fontFamily = Chotki.reading,
                            fontSize = 13.sp,
                        )
                        Text(
                            " · ",
                            color = Chotki.muted,
                            fontFamily = Chotki.reading,
                            fontSize = 13.sp,
                        )
                        Text(
                            "Add a new rule.",
                            color = Chotki.gold,
                            fontFamily = Chotki.reading,
                            fontSize = 13.sp,
                            modifier = Modifier
                                .clickable(onClick = onOpenLibrary)
                                .semantics { contentDescription = "Add a new rule" },
                        )
                    }
                    Commitments(
                        entries = entries,
                        clock = state.settings.clockStyle,
                        glossary = glossary,
                        isOnPause = { state.isOnPause(it.rule, it.date) },
                        pausedOnPurpose = { state.isPausedOnPurpose(it) },
                        afterPause = { state.isPausedAndNotAsked(it.rule, it.date) },
                        onToggle = { state.toggleKept(it) },
                        onReadPrayers = onReadPrayers,
                        onReadReading = onReadReading,
                        onReadPsalter = onReadPsalter,
                        onGoToRope = onGoToRope,
                        onOpenTerm = onOpenTerm,
                        onEdit = onEdit,
                        onMarkKeptLate = { state.markKeptLate(it) },
                        onStandDown = { state.standDown(it) },
                        onClear = { state.clearOccurrence(it) },
                        onPause = { state.pause(it.rule) },
                        onResume = { state.resume(it.rule) },
                        onOpenLibrary = onOpenLibrary,
                        givenBy = state.settings.givenByPriestPhrase(),
                    )
                }
              }
                SayingCard(
                    state.selectedDate,
                    Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                    persistMotion = state.selectedDate == state.today,
                )
            }
            }
            }
        }
    }
}

@Composable
private fun DayHeader(state: AppState) {
    val date = state.selectedDate
    Row(
        Modifier
            .fillMaxWidth()
            .padding(start = 18.dp, end = 18.dp, top = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = longDate(date),
            color = Chotki.parchment,
            fontFamily = Chotki.reading,
            fontSize = 17.sp,
            modifier = Modifier
                .weight(1f)
                .semantics { contentDescription = "The day" },
        )
        if (state.settings.showOldStyleDates) {
            Text(
                oldStyleDate(date),
                color = Chotki.faint,
                fontFamily = Chotki.reading,
                fontSize = 13.sp,
            )
        }
    }
}

/**
 * Nothing due, and the way to change that.
 *
 * The words alone sent someone hunting for a control they had not noticed. The
 * library is named in the sentence, so the library is drawn under it, at a size
 * that reads as the thing to press. The corner icon stays where it is — it is
 * how the library is reached on every other day, and a control that moves
 * depending on whether the day is empty is worse than one that does not.
 */
@Composable
private fun FirstRun(onOpenLibrary: () -> Unit) {
    Column(
        Modifier.fillMaxWidth().padding(top = 28.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .clickable(onClick = onOpenLibrary)
                .semantics { contentDescription = "Create your first rule" },
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Box(
                Modifier
                    .size(54.dp)
                    .border(1.5.dp, Chotki.goldDim, androidx.compose.foundation.shape.CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Text("+", color = Chotki.gold, fontSize = 28.sp)
            }
            Text(
                "Create your first rule",
                color = Chotki.parchment,
                fontFamily = androidx.compose.ui.text.font.FontFamily.Serif,
                fontWeight = FontWeight.Medium,
                fontSize = 22.sp,
                modifier = Modifier.padding(top = 14.dp),
            )
        }
    }
}

/**
 * What the calendar says about the fast, and nothing more.
 *
 * The purpose of the fast used to be pasted here in full, which pushed the
 * day down into the cards. That account lives on the fast's own card, and
 * from there in the glossary.
 */
@Composable
private fun FastNote(state: AppState) {
    val day = state.liturgicalDay(state.selectedDate) ?: return
    val due = state.entries(state.selectedDate).any { it.rule.isFastingRule }
    val observed = state.settings.observances.fasting == Observance.OBSERVED
    if (!due && !observed) return
    if (!day.isFast || day.isFastFree) return
    Column(
        Modifier.fillMaxWidth().padding(start = 18.dp, end = 18.dp, top = 16.dp, bottom = 8.dp),
    ) {
        Text(
            "The calendar marks this as ${day.fastDescription}.",
            color = Chotki.violet,
            fontFamily = Chotki.reading,
            fontSize = 13.sp,
            lineHeight = 18.sp,
        )
        if (day.abstentions.isNotEmpty()) {
            Text(
                "Customarily set aside: ${day.abstentions.joinToString(", ")}.",
                color = Chotki.faint,
                fontFamily = FontFamily.SansSerif,
                fontSize = 12.sp,
                lineHeight = 16.sp,
                modifier = Modifier.padding(top = 10.dp),
            )
        }
    }
}

@Composable
private fun EmptyDay(onOpenLibrary: () -> Unit) {
    Column(
        Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            "Nothing on the rule for this day.",
            color = Chotki.muted,
            fontFamily = Chotki.reading,
            fontSize = 14.sp,
        )
        Spacer(Modifier.size(6.dp))
        Text(
            "Take something on from the library when you are ready.",
            color = Chotki.faint,
            fontFamily = Chotki.reading,
            fontSize = 13.sp,
        )
        Column(
            Modifier
                .clickable(onClick = onOpenLibrary)
                .padding(14.dp)
                // Not the same label as the icon in the bar. Two controls
                // announcing themselves identically on one screen is a maze
                // for anyone using a screen reader, and it made the test that
                // clicks the bar's icon ambiguous — which is how it was found.
                .semantics { contentDescription = "Take something on from the library" },
        ) {
            LibraryIcon(Chotki.gold, 56.dp)
        }
    }
}

private val months = listOf(
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
)

private val weekdays = listOf(
    "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
)

internal fun longDate(date: CalendarDate): String =
    "${weekdays[date.weekday.number - 1]} ${date.day} ${months[date.month - 1]}"

/** "6 Aug o.s." The civil day, thirteen days earlier, which is the Julian date. */
internal fun oldStyleDate(date: CalendarDate): String {
    val julian = date.plusDays(-13)
    return "${julian.day} ${months[julian.month - 1].take(3)} o.s."
}
