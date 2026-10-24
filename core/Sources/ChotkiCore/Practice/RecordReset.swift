import Foundation

/// Starting the record again from today.
///
/// Erasing what was kept is not enough on its own. A rule's stretch still
/// reaches back, and with nothing recorded against it every day of that stretch
/// would read as missed — months of apparent failure from one deliberate act,
/// which is exactly what this app must never be able to say. So the stretches
/// are cut as well, in the same plan:
///
/// - a rule in force begins again today;
/// - a rule the person paused stays paused, kept as one stood-down day so it is
///   still shown as paused and is not counted;
/// - a rule that only ever ended or was edited away has nothing left to hold.
///
/// Pure: it decides, and the platform applies it. The history itself —
/// every occurrence — is removed by the caller, after this plan is applied and
/// never before it, so that a failure part-way leaves a record that is merely
/// still there rather than one that has turned into a list of misses.
public struct RecordReset: Sendable {

    public init() {}

    public func plan(
        rules: [Rule],
        activations: [Activation],
        pausedRuleIDs: Set<UUID>,
        today: CalendarDate
    ) -> EditPlan {
        var plan = EditPlan()
        for rule in rules {
            let mine = activations.filter { $0.ruleID == rule.id }
            guard !mine.isEmpty else { continue }

            if let current = mine.first(where: \.isOpen) {
                var restarted = current
                restarted.from = max(current.from, today)
                plan.updatedActivations.append(restarted)
                plan.removedActivationIDs += mine.filter { $0.id != current.id }.map(\.id)
            } else if pausedRuleIDs.contains(rule.id), !rule.isArchived,
                      let pausedOn = mine.compactMap(\.to).max(),
                      let last = mine.first(where: { $0.to == pausedOn }) {
                var collapsed = last
                collapsed.from = pausedOn
                plan.updatedActivations.append(collapsed)
                plan.removedActivationIDs += mine.filter { $0.id != last.id }.map(\.id)
                plan.newOccurrences.append(
                    Occurrence(ruleID: rule.id, date: pausedOn, status: .skipped)
                )
            } else {
                plan.removedActivationIDs += mine.map(\.id)
            }
        }
        return plan
    }
}
