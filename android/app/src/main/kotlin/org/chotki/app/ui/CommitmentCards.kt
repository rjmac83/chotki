package org.chotki.app.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ColorMatrix
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.zIndex
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import org.chotki.core.ClockStyle
import org.chotki.core.DayEntry
import org.chotki.core.Format
import org.chotki.core.ReadingOrder
import org.chotki.core.Rule
import org.chotki.core.RuleCategory
import org.chotki.core.RuleReference
import org.chotki.core.content.Content
import org.chotki.core.content.Glossary
import org.chotki.core.glossarySlug
import org.chotki.core.reference
import org.chotki.core.ropePrayerId

private val Ink = Color(0xFF1A1916)
private val CardFaint = Color(0xFF6E6A60)
private val BlurbInk = Color(0xFF5E5A50)
private val FastGlyph = Color(0xFF5C5380)
private val Dash = Color(0xFF3A3424)

private val CardShape = RoundedCornerShape(22.dp)
private val CardWidth = 116.dp
private val CardHeight = 226.dp

/**
 * The day's rule, as a row of cards that glides.
 *
 * One card is one commitment. The circle is the only thing that marks it kept,
 * and tapping it again takes the mark off. Morning and evening prayers, the
 * Jesus Prayer, and a reading still fill the circle when they are finished,
 * and the same circle clears that too. Tapping the card opens the section
 * that holds it. A fast has no section: it turns over and says what the fast is.
 */
@Composable
internal fun Commitments(
    entries: List<DayEntry>,
    clock: ClockStyle,
    glossary: Glossary,
    isOnPause: (DayEntry) -> Boolean,
    pausedOnPurpose: (Rule) -> Boolean,
    afterPause: (DayEntry) -> Boolean,
    onToggle: (DayEntry) -> Unit,
    onReadPrayers: (DayEntry) -> Unit,
    onReadReading: (Int?) -> Unit,
    onReadPsalter: () -> Unit,
    onGoToRope: (String) -> Unit,
    onOpenTerm: (String) -> Unit,
    onEdit: (DayEntry) -> Unit,
    onMarkKeptLate: (DayEntry) -> Unit,
    onStandDown: (DayEntry) -> Unit,
    onClear: (DayEntry) -> Unit,
    onPause: (DayEntry) -> Unit,
    onResume: (DayEntry) -> Unit,
    onOpenLibrary: () -> Unit,
    givenBy: String?,
) {
    LazyRow(
        Modifier.testTag("commitments").fillMaxWidth(),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        items(entries, key = { it.id }) { entry ->
            CommitmentCard(
                entry = entry,
                clock = clock,
                glossary = glossary,
                isOnPause = isOnPause(entry),
                pausedOnPurpose = pausedOnPurpose(entry.rule),
                afterPause = afterPause(entry),
                onToggle = { onToggle(entry) },
                onOpen = { openCommitment(entry, onReadPrayers, onReadReading, onReadPsalter, onGoToRope) },
                onOpenTerm = onOpenTerm,
                onEdit = { onEdit(entry) },
                onMarkKeptLate = { onMarkKeptLate(entry) },
                onStandDown = { onStandDown(entry) },
                onClear = { onClear(entry) },
                onPause = { onPause(entry) },
                onResume = { onResume(entry) },
                onReadPrayers = { onReadPrayers(entry) },
                onReadReading = onReadReading,
                onReadPsalter = onReadPsalter,
                onGoToRope = onGoToRope,
                givenBy = givenBy,
            )
        }
        item(key = "add") { AddCard(onOpenLibrary) }
    }
}

/**
 * Where a tap on the card goes.
 *
 * A rope prayer and a prayer the prayers screen already holds open that
 * screen on the right words. Anything else with prayers still opens the
 * rule's own text. A reading opens the Reading. A fast does not come here:
 * the card turns over instead.
 */
private fun openCommitment(
    entry: DayEntry,
    onReadPrayers: (DayEntry) -> Unit,
    onReadReading: (Int?) -> Unit,
    onReadPsalter: () -> Unit,
    onGoToRope: (String) -> Unit,
) {
    val rule = entry.rule
    val selection = prayerSelection(rule)
    when {
        selection != null -> onGoToRope(selection)
        rule.reference == RuleReference.READING -> onReadReading(ReadingOrder.bandOfTitle(rule.title))
        rule.reference == RuleReference.PSALTER -> onReadPsalter()
        rule.reference == RuleReference.PRAYERS -> onReadPrayers(entry)
        else -> Unit
    }
}

/** The prayers screen's own id for this rule, when it has one. */
private fun prayerSelection(rule: Rule): String? {
    rule.ropePrayerId?.let { return it }
    val ids = rule.prayerIDs
    if (ids != null) {
        Content.prayerSequences.firstOrNull { it.prayerIDs == ids }?.let { return it.id }
    }
    // The editor never rewrites this list. A rule that still has the
    // sequence's title, and whose stored prayers are all part of it, opens
    // the sequence as it stands now rather than an older copy of the list.
    val sequence = Content.prayerSequences.firstOrNull {
        it.title.equals(rule.title, ignoreCase = true)
    } ?: return null
    if (ids != null && (ids.isEmpty() || ids.any { it !in sequence.prayerIDs })) return null
    return sequence.id
}

private fun Rule.cardBlurb(): String {
    val curated = Content.ruleLibrary
        .firstOrNull { it.title.equals(title, ignoreCase = true) }
        ?.summary
    if (!curated.isNullOrBlank()) return curated
    return note?.trim().orEmpty()
}

private fun Rule.cardLabel(): String = when (category) {
    RuleCategory.PRAYER -> "prayer"
    RuleCategory.FASTING -> "fasting"
    RuleCategory.SERVICES -> "services"
    RuleCategory.READING -> "reading"
    RuleCategory.LIFE -> "life"
    null -> "custom"
}

@Composable
private fun CommitmentCard(
    entry: DayEntry,
    clock: ClockStyle,
    glossary: Glossary,
    isOnPause: Boolean,
    pausedOnPurpose: Boolean,
    afterPause: Boolean,
    onToggle: () -> Unit,
    onOpen: () -> Unit,
    onOpenTerm: (String) -> Unit,
    onEdit: () -> Unit,
    onMarkKeptLate: () -> Unit,
    onStandDown: () -> Unit,
    onClear: () -> Unit,
    onPause: () -> Unit,
    onResume: () -> Unit,
    onReadPrayers: () -> Unit,
    onReadReading: (Int?) -> Unit,
    onReadPsalter: () -> Unit,
    onGoToRope: (String) -> Unit,
    givenBy: String?,
) {
    var menuOpen by remember { mutableStateOf(false) }
    var flipped by remember(entry.id) { mutableStateOf(false) }
    val fasting = entry.rule.isFastingRule
    val turn by animateFloatAsState(
        targetValue = if (flipped) 180f else 0f,
        animationSpec = tween(durationMillis = 420),
        label = "commitment-flip",
    )
    val showBack = turn > 90f
    val resting = isOnPause || entry.isStoodDown

    Box(Modifier.size(CardWidth, CardHeight)) {
        Box(
            Modifier
                .fillMaxSize()
                .shadow(10.dp, CardShape)
                .clip(CardShape)
                .background(if (resting) Color(0xFFD5D0C4) else Chotki.parchment)
                .combinedClickable(
                    onClick = {
                        if (fasting) flipped = !flipped else onOpen()
                    },
                    onLongClick = { menuOpen = true },
                )
                .semantics { contentDescription = entry.rule.title }
                .graphicsLayer {
                    rotationY = if (showBack) turn - 180f else turn
                    cameraDistance = 16f * density
                    if (resting) {
                        alpha = 0.6f
                        colorFilter = ColorFilter.colorMatrix(ColorMatrix().apply { setToSaturation(0f) })
                    }
                },
        ) {
            if (showBack) {
                FastBack(
                    entry = entry,
                    glossary = glossary,
                    onOpenTerm = onOpenTerm,
                )
            } else {
                CardFace(
                    entry = entry,
                    clock = clock,
                    onPause = isOnPause,
                    onOpenTerm = onOpenTerm,
                    givenBy = if (entry.rule.givenByPriest == true) givenBy else null,
                )
            }
        }

        // Drawn after the face, and not inside it, so a tap here never opens
        // the section and never turns the card over. A day after a pause was
        // never asked, so there is no circle to tick.
        if (!showBack && !afterPause) {
            Mark(
                title = entry.rule.title,
                on = entry.showsAsSatisfied,
                enabled = !entry.isDispensed,
                onToggle = onToggle,
                modifier = Modifier
                    .zIndex(1f)
                    .align(Alignment.TopEnd)
                    .padding(top = 6.dp, end = 6.dp)
                    .graphicsLayer { alpha = if (resting) 0.55f else 1f },
            )
        }

        RuleMenu(
            open = menuOpen,
            entry = entry,
            pausedOnPurpose = pausedOnPurpose,
            afterPause = afterPause,
            onDismiss = { menuOpen = false },
            onReadPrayers = onReadPrayers,
            onReadReading = onReadReading,
            onReadPsalter = onReadPsalter,
            onGoToRope = onGoToRope,
            onToggle = onToggle,
            onMarkKeptLate = onMarkKeptLate,
            onStandDown = onStandDown,
            onClear = onClear,
            onEdit = onEdit,
            onPause = onPause,
            onResume = onResume,
        )
    }
}

@Composable
private fun CardFace(
    entry: DayEntry,
    clock: ClockStyle,
    onPause: Boolean,
    onOpenTerm: (String) -> Unit,
    givenBy: String?,
) {
    val rule = entry.rule
    val blurb = rule.cardBlurb()
    val slug = rule.glossarySlug
    var overflows by remember(blurb) { mutableStateOf(false) }

    Column(
        Modifier
            .fillMaxSize()
            .padding(start = 12.dp, top = 16.dp, end = 12.dp, bottom = 14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        CommitmentGlyph(rule.category)
        Text(rule.cardLabel(), color = CardFaint, fontSize = 11.sp)
        Text(
            rule.title,
            color = Ink,
            fontFamily = Chotki.reading,
            fontWeight = FontWeight.Medium,
            fontSize = 17.sp,
            lineHeight = 20.sp,
        )
        if (givenBy != null || entry.rule.givenByPriest == true) {
            Text(
                givenBy ?: "GIVEN BY A PRIEST",
                color = Chotki.goldDim,
                fontSize = 9.sp,
                letterSpacing = 0.04.em,
                lineHeight = 12.sp,
            )
        }
        Box(Modifier.weight(1f).fillMaxWidth()) {
            if (blurb.isNotEmpty() && !overflows) {
                Text(
                    blurb,
                    color = BlurbInk,
                    fontFamily = Chotki.reading,
                    fontSize = 12.5.sp,
                    lineHeight = 17.sp,
                    overflow = TextOverflow.Clip,
                    modifier = Modifier.fillMaxSize(),
                    onTextLayout = { layout ->
                        if (layout.didOverflowHeight && slug != null) overflows = true
                    },
                )
            } else if (overflows && slug != null) {
                Text(
                    "Tap to learn more",
                    color = Chotki.goldDim,
                    fontFamily = androidx.compose.ui.text.font.FontFamily.SansSerif,
                    fontSize = 12.5.sp,
                    lineHeight = 17.sp,
                    textDecoration = TextDecoration.Underline,
                    modifier = Modifier
                        .clickable { onOpenTerm(slug) }
                        .semantics { contentDescription = "Tap to learn more" },
                )
            }
        }
        val dispensation = entry.dispensation
        if (dispensation != null && !onPause) {
            Text("Not observed during $dispensation", color = Chotki.goldDim, fontSize = 11.sp, lineHeight = 14.sp)
        }
        val resting = onPause || entry.isStoodDown
        val mark = when {
            onPause -> "Paused"
            entry.isStoodDown -> "Stood Down"
            else -> null
        }
        Text(
            text = mark ?: (rule.timeOfDay?.let { Format.time(it, clock) } ?: "All day"),
            color = if (resting) Ink else CardFaint,
            fontWeight = if (resting) FontWeight.SemiBold else FontWeight.Normal,
            fontSize = 12.sp,
        )
    }
}

/**
 * The other side of a fast. The short account, and the way to the glossary
 * when that is not the whole of it. The long paragraphs used to sit on the
 * day itself, between the week and the date.
 */
@Composable
private fun FastBack(
    entry: DayEntry,
    glossary: Glossary,
    onOpenTerm: (String) -> Unit,
) {
    val rule = entry.rule
    val slug = rule.glossarySlug
    val gloss = slug?.let { glossary.entry(it) }
    val blurb = rule.cardBlurb()
    Column(
        Modifier
            .fillMaxSize()
            .padding(start = 12.dp, top = 16.dp, end = 12.dp, bottom = 14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        CommitmentGlyph(rule.category)
        Text(rule.cardLabel(), color = CardFaint, fontSize = 11.sp)
        Text(
            rule.title,
            color = Ink,
            fontFamily = Chotki.reading,
            fontWeight = FontWeight.Medium,
            fontSize = 17.sp,
            lineHeight = 20.sp,
        )
        Text(
            gloss?.short ?: blurb,
            color = BlurbInk,
            fontFamily = Chotki.reading,
            fontSize = 12.5.sp,
            lineHeight = 17.sp,
            modifier = Modifier.weight(1f),
            overflow = TextOverflow.Clip,
        )
        if (slug != null) {
            Text(
                "Tap to learn more",
                color = Chotki.goldDim,
                fontFamily = androidx.compose.ui.text.font.FontFamily.SansSerif,
                fontSize = 12.5.sp,
                textDecoration = TextDecoration.Underline,
                modifier = Modifier
                    .clickable { onOpenTerm(slug) }
                    .semantics { contentDescription = "Tap to learn more" },
            )
        }
    }
}

@Composable
private fun Mark(
    title: String,
    on: Boolean,
    enabled: Boolean,
    onToggle: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier
            .size(36.dp)
            .clickable(onClick = { if (enabled) onToggle() })
            .semantics {
                contentDescription = when {
                    !enabled && on -> "$title kept"
                    !enabled -> "$title not yet kept"
                    else -> "Mark $title kept"
                }
            },
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier
                .size(22.dp)
                .clip(CircleShape)
                .background(if (on) Chotki.gold else Color.Transparent)
                .border(1.5.dp, if (on) Chotki.gold else Chotki.goldDim, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            if (on) {
                Canvas(Modifier.size(12.dp)) {
                    val path = Path().apply {
                        moveTo(size.width * 0.15f, size.height * 0.52f)
                        lineTo(size.width * 0.40f, size.height * 0.76f)
                        lineTo(size.width * 0.86f, size.height * 0.24f)
                    }
                    drawPath(
                        path,
                        color = Chotki.ground,
                        style = Stroke(
                            width = size.minDimension * 0.16f,
                            cap = StrokeCap.Round,
                            join = StrokeJoin.Round,
                        ),
                    )
                }
            }
        }
    }
}

@Composable
private fun AddCard(onOpenLibrary: () -> Unit) {
    Box(
        Modifier
            .size(CardWidth, CardHeight)
            .drawBehind {
                drawRoundRect(
                    color = Dash,
                    style = Stroke(
                        width = 1.dp.toPx(),
                        pathEffect = PathEffect.dashPathEffect(
                            floatArrayOf(6.dp.toPx(), 5.dp.toPx()),
                        ),
                    ),
                    cornerRadius = CornerRadius(22.dp.toPx(), 22.dp.toPx()),
                )
            }
            .clickable(onClick = onOpenLibrary)
            .semantics { contentDescription = "Add a commitment" },
        contentAlignment = Alignment.Center,
    ) {
        Text("+ Add", color = Chotki.gold, fontSize = 13.sp)
    }
}

@Composable
private fun CommitmentGlyph(category: RuleCategory?) {
    val fasting = category == RuleCategory.FASTING
    val tint = if (fasting) FastGlyph else Chotki.goldDim
    Canvas(Modifier.size(18.dp)) {
        val stroke = Stroke(
            width = size.minDimension * (1.3f / 18f),
            cap = StrokeCap.Round,
            join = StrokeJoin.Round,
        )
        when (category) {
            RuleCategory.PRAYER -> prayerFigure(tint, stroke)
            RuleCategory.READING -> readingBook(tint, stroke)
            RuleCategory.FASTING -> fastingBowl(tint, stroke)
            RuleCategory.SERVICES -> serviceCross(tint)
            RuleCategory.LIFE -> lifeFigure(tint, stroke)
            null -> customPencil(tint, stroke)
        }
    }
}

/** A prayer rope, the same mark the Prayers tab uses, fitted to the card. */
private fun DrawScope.prayerFigure(tint: Color, stroke: Stroke) {
    rope(
        tint,
        Stroke(width = size.minDimension * 0.085f, cap = stroke.cap, join = stroke.join),
    )
}

/**
 * An open book, as tall as the prayer figure beside it.
 *
 * The figure runs from 3.3 to 14.7 in the same 18-unit box. A book drawn
 * inside a shorter band reads as a smaller mark, which is what the cards
 * were doing.
 */
private fun DrawScope.readingBook(tint: Color, stroke: Stroke) {
    val s = size.width / 18f
    // Same vertical span as the prayer figure: the crown of the head is at
    // 3.3 and the foot of the body at 14.7, in this same 18-unit box.
    val top = 3.3f * s
    val bottom = 14.7f * s
    val mid = 9f * s
    val left = 3.2f * s
    val right = 14.8f * s
    val path = Path().apply {
        moveTo(left, top)
        quadraticTo(mid, top + 2.6f * s, right, top)
        lineTo(right, bottom)
        quadraticTo(mid, bottom - 2.2f * s, left, bottom)
        close()
    }
    drawPath(path, tint, style = stroke)
    drawLine(tint, Offset(mid, top + 1.3f * s), Offset(mid, bottom - 1.1f * s), stroke.width)
}

private fun DrawScope.customPencil(tint: Color, stroke: Stroke) {
    val s = size.width / 18f
    val path = Path().apply {
        moveTo(11f * s, 3.5f * s)
        lineTo(14.5f * s, 7f * s)
        lineTo(7f * s, 14.5f * s)
        lineTo(3.5f * s, 14.5f * s)
        lineTo(3.5f * s, 11f * s)
        close()
    }
    drawPath(path, tint, style = stroke)
}

private fun DrawScope.fastingBowl(tint: Color, stroke: Stroke) {
    val s = size.width / 18f
    val bowl = Path().apply {
        moveTo(4f * s, 8.5f * s)
        lineTo(14f * s, 8.5f * s)
        cubicTo(14f * s, 11.7f * s, 12f * s, 13.7f * s, 9f * s, 13.7f * s)
        cubicTo(6f * s, 13.7f * s, 4f * s, 11.7f * s, 4f * s, 8.5f * s)
        close()
    }
    drawPath(bowl, tint, style = stroke)
    drawLine(tint, Offset(7f * s, 8.5f * s), Offset(7f * s, 6.2f * s), stroke.width, cap = StrokeCap.Round)
    drawLine(tint, Offset(11f * s, 8.5f * s), Offset(11f * s, 6.2f * s), stroke.width, cap = StrokeCap.Round)
}

private fun DrawScope.serviceCross(tint: Color) {
    val s = size.width / 18f
    drawRect(tint, Offset(8.2f * s, 2f * s), Size(1.6f * s, 13f * s))
    drawRect(tint, Offset(5f * s, 4.2f * s), Size(8f * s, 1.5f * s))
    drawRect(tint, Offset(6.2f * s, 7f * s), Size(5.6f * s, 1.3f * s))
    val foot = Path().apply {
        moveTo(5.2f * s, 13.2f * s)
        lineTo(6.6f * s, 12.4f * s)
        lineTo(12.6f * s, 15.2f * s)
        lineTo(11.2f * s, 16f * s)
        close()
    }
    drawPath(foot, tint)
}

private fun DrawScope.lifeFigure(tint: Color, stroke: Stroke) {
    val s = size.width / 18f
    drawCircle(tint, radius = 2f * s, center = Offset(9f * s, 5f * s), style = stroke)
    val shoulders = Path().apply {
        moveTo(5.5f * s, 14.5f * s)
        cubicTo(5.9f * s, 12.1f * s, 7.3f * s, 10.9f * s, 9f * s, 10.9f * s)
        cubicTo(10.7f * s, 10.9f * s, 12.1f * s, 12.1f * s, 12.5f * s, 14.5f * s)
    }
    drawPath(shoulders, tint, style = stroke)
}

@Composable
private fun RuleMenu(
    open: Boolean,
    entry: DayEntry,
    pausedOnPurpose: Boolean,
    afterPause: Boolean,
    onDismiss: () -> Unit,
    onReadPrayers: () -> Unit,
    onReadReading: (Int?) -> Unit,
    onReadPsalter: () -> Unit,
    onGoToRope: (String) -> Unit,
    onToggle: () -> Unit,
    onMarkKeptLate: () -> Unit,
    onStandDown: () -> Unit,
    onClear: () -> Unit,
    onEdit: () -> Unit,
    onPause: () -> Unit,
    onResume: () -> Unit,
) {
    DropdownMenu(
        expanded = open,
        onDismissRequest = onDismiss,
        modifier = Modifier.background(Chotki.panel),
    ) {
        fun choosing(action: () -> Unit): () -> Unit = { onDismiss(); action() }

        if (entry.isDispensed) {
            DropdownMenuItem(
                text = { Text("Lifted by the Church today", color = Chotki.muted) },
                onClick = onDismiss,
            )
        } else {
            when (entry.rule.reference) {
                RuleReference.ROPE -> {
                    Item("Go to the rope", choosing { entry.rule.ropePrayerId?.let(onGoToRope) })
                    HorizontalDivider(color = Chotki.lineSoft)
                }
                RuleReference.PRAYERS -> {
                    Item("Read the prayers", choosing(onReadPrayers))
                    HorizontalDivider(color = Chotki.lineSoft)
                }
                RuleReference.READING -> {
                    Item(
                        "Read the day\u2019s readings",
                        choosing { onReadReading(ReadingOrder.bandOfTitle(entry.rule.title)) },
                    )
                    HorizontalDivider(color = Chotki.lineSoft)
                }
                RuleReference.PSALTER -> {
                    Item("Read today\u2019s kathisma", choosing(onReadPsalter))
                    HorizontalDivider(color = Chotki.lineSoft)
                }

                RuleReference.NONE -> Unit
            }

            if (!afterPause) {
                Item(
                    if (entry.isKept) "Clear this day" else "Mark as kept",
                    choosing(onToggle),
                )
                if (!entry.isKept) Item("Mark as kept, late", choosing(onMarkKeptLate))
                Item(
                    "Stand down for this day",
                    choosing { if (entry.isStoodDown) onClear() else onStandDown() },
                    checked = entry.isStoodDown,
                )
            }
        }

        HorizontalDivider(color = Chotki.lineSoft)
        Item("Edit rule\u2026", choosing(onEdit))
        Item(
            "Pause this rule",
            choosing { if (pausedOnPurpose) onResume() else onPause() },
            checked = pausedOnPurpose,
        )
    }
}

@Composable
private fun Item(label: String, onClick: () -> Unit, checked: Boolean = false) {
    DropdownMenuItem(
        text = {
            Text(
                if (checked) "\u2713  $label" else label,
                color = Chotki.parchment,
                fontSize = 15.sp,
                fontFamily = androidx.compose.ui.text.font.FontFamily.SansSerif,
            )
        },
        onClick = onClick,
    )
}
