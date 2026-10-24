package org.chotki.core

import java.util.UUID

/**
 * Starting the record again from today.
 *
 * Erasing what was kept is not enough on its own. A rule's stretch still
 * reaches back, and with nothing recorded against it every day of that stretch
 * would read as missed. The stretches are cut in the same plan:
 *
 * - a rule in force begins again today;
 * - a rule the person paused stays paused, kept as one stood-down day;
 * - a rule that only ever ended or was edited away has nothing left to hold.
 *
 * The caller applies the stretches first, then erases occurrences, then writes
 * the stand-downs. A failure part-way leaves a record that is still there
 * rather than one that has turned into a list of misses.
 */
class RecordReset {
    fun plan(
        rules: List<Rule>,
        activations: List<Activation>,
        pausedRuleIDs: Set<UUID>,
        today: CalendarDate,
    ): EditPlan {
        val updated = mutableListOf<Activation>()
        val removed = mutableListOf<UUID>()
        val standDowns = mutableListOf<Occurrence>()
        for (rule in rules) {
            val mine = activations.filter { it.ruleID == rule.id }
            if (mine.isEmpty()) continue
            val current = mine.firstOrNull { it.isOpen }
            if (current != null) {
                val restartedFrom = if (current.from > today) current.from else today
                updated += current.copy(from = restartedFrom)
                removed += mine.filter { it.id != current.id }.map { it.id }
            } else if (rule.id in pausedRuleIDs && !rule.isArchived) {
                val pausedOn = mine.mapNotNull { it.to }.maxOrNull() ?: continue
                val last = mine.firstOrNull { it.to == pausedOn } ?: continue
                updated += last.copy(from = pausedOn)
                removed += mine.filter { it.id != last.id }.map { it.id }
                standDowns += Occurrence(
                    ruleID = rule.id,
                    date = pausedOn,
                    status = OccurrenceStatus.SKIPPED,
                )
            } else {
                removed += mine.map { it.id }
            }
        }
        return EditPlan(
            updatedActivations = updated,
            removedActivationIDs = removed,
            newOccurrences = standDowns,
        )
    }
}
