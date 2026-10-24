package org.chotki.app.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.chotki.app.AppState
import org.chotki.app.R
import org.chotki.core.Practice
import kotlin.math.roundToInt

/**
 * What was kept, said in words first.
 *
 * The prose leads and the figure follows, because "evening prayers slipped
 * twice, both Fridays" is something a person can act on and a percentage is not.
 *
 * Progress stops at yesterday. A day still in progress is not a verdict, and a
 * rule taken on this morning and not yet kept must not count against anyone
 * before they have had the chance.
 *
 * The icon is anchored at the bottom. When the report is taller than the room
 * above it, the words scroll under the picture and fade as they go.
 */
@Composable
fun ProgressScreen(state: AppState, modifier: Modifier = Modifier) {
    val report = state.report()
    val through = Practice.progressThrough(state.today)
    var platePx by remember { mutableIntStateOf(0) }
    var confirmingReset by remember { mutableStateOf(false) }
    val density = LocalDensity.current

    BoxWithConstraints(modifier.fillMaxSize()) {
        val totalPx = constraints.maxHeight.coerceAtLeast(1)
        val covered = (platePx.toFloat() / totalPx).coerceIn(0f, 0.85f)
        val visible = (1f - covered).coerceAtLeast(0.2f)
        val band = 0.1f * visible
        val reportList = rememberLazyListState()
        val top = reportList.scrolledTopBand(full = band)

        LazyColumn(
            Modifier
                .fillMaxSize()
                .edgeFade(
                    topBand = top,
                    bottomOpaqueUntil = visible - band,
                    bottomClearAt = visible,
                ),
            state = reportList,
            contentPadding = PaddingValues(bottom = with(density) { platePx.toDp() }),
        ) {
            item {
                Column(Modifier.padding(16.dp)) {
                    Text(
                        "Your progress up to ${longDate(through)}",
                        color = Chotki.parchment,
                        fontFamily = Chotki.reading,
                        fontSize = 16.sp,
                        modifier = Modifier.semantics { contentDescription = "Progress heading" },
                    )
                    Spacer(Modifier.size(8.dp))
                    Text(
                        "Reset record",
                        color = Chotki.muted,
                        fontFamily = Chotki.reading,
                        fontSize = 14.sp,
                        modifier = Modifier
                            .clickable { confirmingReset = true }
                            .semantics { contentDescription = "Reset record" },
                    )
                    val cleared = state.notice
                    if (cleared != null) {
                        Spacer(Modifier.size(6.dp))
                        Text(
                            cleared,
                            color = Chotki.parchmentDim,
                            fontFamily = Chotki.reading,
                            fontSize = 14.sp,
                        )
                    }
                    Spacer(Modifier.size(12.dp))
                    for (line in report.summary) {
                        Text(
                            line,
                            color = Chotki.parchmentDim,
                            fontFamily = Chotki.reading,
                            fontSize = 15.sp,
                        )
                        Spacer(Modifier.size(6.dp))
                    }
                    val overall = report.overall
                    if (overall != null && state.settings.showConsistencyNumber) {
                        Spacer(Modifier.size(8.dp))
                        Text(
                            "${(overall * 100).roundToInt()}% over the last thirty days",
                            color = Chotki.goldDim,
                            fontFamily = Chotki.reading,
                            fontSize = 14.sp,
                        )
                    }
                }
            }

            val scored = report.perRule.filter { it.hasAnythingDue }
            if (scored.isNotEmpty()) {
                item {
                    Text(
                        "By rule",
                        color = Chotki.gold,
                        fontFamily = Chotki.reading,
                        fontSize = 13.sp,
                        modifier = Modifier.padding(start = 16.dp, top = 8.dp, bottom = 4.dp),
                    )
                }
                items(scored.size) { index ->
                    val score = scored[index]
                    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp)) {
                        Text(
                            score.title,
                            color = Chotki.parchment,
                            fontFamily = Chotki.reading,
                            fontSize = 15.sp,
                        )
                        // Never "missed": the wording says what was kept, and the
                        // rest is arithmetic the reader can do if they want it.
                        Text(
                            buildString {
                                append("${score.kept} kept")
                                if (score.keptLate > 0) append(", ${score.keptLate} a little late")
                                if (score.stoodDown > 0) append(", ${score.stoodDown} stood down")
                            },
                            color = Chotki.faint,
                            fontFamily = Chotki.reading,
                            fontSize = 13.sp,
                        )
                    }
                }
            }
        }

        ClimacusPlate(
            Modifier
                .align(Alignment.BottomCenter)
                .onSizeChanged { platePx = it.height },
        )

        if (confirmingReset) {
            AlertDialog(
                onDismissRequest = { confirmingReset = false },
                title = { Text("Are you sure?") },
                text = { Text("This will completely erase your record and cannot be undone.") },
                confirmButton = {
                    TextButton(onClick = {
                        confirmingReset = false
                        state.resetRecord()
                    }) { Text("Yes") }
                },
                dismissButton = {
                    TextButton(onClick = { confirmingReset = false }) { Text("Cancel") }
                },
            )
        }
    }
}

private val QUOTE =
    "Those who have really determined to serve Christ, with the help of spiritual fathers and their own self-knowledge, will strive before all else to choose a place, a way of life, a habitation, and exercises suitable for them."

private const val ATTRIBUTION =
    "-- Saint John Climacus, from The Ladder of Divine Ascent, 7th century AD."

private const val CAPTION =
    "Icon of St. Anthony the Great, St. Paul of Thebes, St. Sabbas the Sanctified, and St. John Climacus."

/** Soft enough to stay quiet, dark enough that parchment still reads on the robes. */
private val onIcon = Shadow(
    color = Color.Black.copy(alpha = 0.7f),
    offset = Offset(0f, 1f),
    blurRadius = 6f,
)

/**
 * The fresco anchored at the bottom. The saying lies on the picture, as low as
 * it can sit without meeting the caption, and the caption is one line in the
 * shaded foot.
 */
@Composable
private fun ClimacusPlate(modifier: Modifier = Modifier) {
    Box(modifier.fillMaxWidth()) {
        Image(
            painter = painterResource(R.drawable.s1641005),
            contentDescription = null,
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(960f / 670f),
        )
        Column(
            Modifier
                .align(Alignment.BottomStart)
                .padding(start = 12.dp, end = 12.dp, bottom = 8.dp),
        ) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
                Text(
                    "“",
                    color = Chotki.goldDim,
                    fontFamily = Chotki.reading,
                    fontSize = 42.sp * 0.85f,
                    lineHeight = 42.sp * 0.85f,
                    style = TextStyle(shadow = onIcon),
                    modifier = Modifier.padding(end = 4.dp),
                )
                Column(Modifier.weight(1f)) {
                    Text(
                        QUOTE + "”",
                        color = Chotki.parchment,
                        fontFamily = Chotki.reading,
                        fontStyle = FontStyle.Italic,
                        fontSize = 17.sp * 0.85f,
                        lineHeight = 17.sp * 0.85f * 1.35f,
                        style = TextStyle(shadow = onIcon),
                    )
                    Text(
                        ATTRIBUTION,
                        color = Chotki.muted,
                        fontFamily = Chotki.reading,
                        fontSize = 13.sp * 0.85f,
                        lineHeight = 13.sp * 0.85f * 1.35f,
                        style = TextStyle(shadow = onIcon),
                        modifier = Modifier.padding(top = 6.dp),
                    )
                }
            }
            Spacer(Modifier.height(10.dp))
            IconCaption()
        }
    }
}

/**
 * "St." is what keeps this to one line. The layout itself says when the line
 * still overflows, and the size steps down until the whole caption is visible.
 */
@Composable
private fun IconCaption() {
    var size by remember { mutableFloatStateOf(11.5f) }
    Text(
        CAPTION,
        color = Chotki.parchment,
        fontFamily = FontFamily.SansSerif,
        fontSize = size.sp,
        maxLines = 1,
        softWrap = false,
        overflow = TextOverflow.Clip,
        textAlign = TextAlign.Start,
        onTextLayout = { result ->
            if (result.didOverflowWidth && size > 7f) {
                size = (size - 0.25f).coerceAtLeast(7f)
            }
        },
        modifier = Modifier
            .fillMaxWidth()
            .semantics { contentDescription = "Icon caption" },
    )
}
