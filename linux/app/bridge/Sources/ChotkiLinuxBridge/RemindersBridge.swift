import ChotkiCore
import Foundation

// The ticker decides. This file only reads the record, asks it, and writes an
// occurrence when a notification's button says the rule was kept.

private func plannedReminders(_ store: SQLiteStore) throws -> [PlannedNotification] {
    let settings = try store.loadSettings() ?? .default
    let scheduler = Scheduler(policy: settings.reminders, timeZone: .current)
    let today = CalendarDate(Date(), in: .current)
    let practice = try dayPractice(store, on: today)
    return scheduler.plan(
        rules: practice.rulesNotOnPause(on: today),
        activations: try store.activations(ruleID: nil),
        occurrences: try store.occurrences(ruleID: nil, from: today.adding(days: -1), through: today),
        on: today
    )
}

private func remindersPayload(
    _ decision: ReminderTicker.Decision, alsoWithdraw acted: String? = nil
) -> RemindersPayload {
    var withdraw = decision.withdraw
    if let acted, !acted.isEmpty, !withdraw.contains(acted) {
        withdraw.append(acted)
    }
    return RemindersPayload(
        show: decision.show.map { note in
            ReminderNotice(
                id: note.request.id,
                title: note.request.title,
                body: note.request.body,
                actions: note.request.actions.map { ReminderActionPayload(id: $0.id, title: $0.title) }
            )
        },
        withdraw: withdraw.sorted()
    )
}

private func reminderSettled(_ entry: DayEntry) -> Bool {
    switch entry.status {
    case .completed, .completedLate, .skipped, .cancelled, .moved:
        return true
    case nil:
        return false
    }
}

/// Review mode answers with an empty decision and does not advance the ticker,
/// so a screenshot never posts a notification or writes the review record.
func performTickReminders(id: Int, store: SQLiteStore, review: Bool,
                          ticker: inout ReminderTicker) throws {
    if review {
        respond(BridgeSuccess(
            v: bridgeProtocolVersion, id: id,
            reminders: RemindersPayload(show: [], withdraw: [])
        ))
        return
    }
    let decision = ticker.tick(planned: try plannedReminders(store), now: Date())
    respond(BridgeSuccess(
        v: bridgeProtocolVersion, id: id, reminders: remindersPayload(decision)
    ))
}

func performNotificationAction(_ request: BridgeRequest, store: SQLiteStore,
                               on selectedDate: CalendarDate, weekCenter: CalendarDate,
                               ticker: inout ReminderTicker) throws {
    guard let name = request.name, !name.isEmpty,
          let selection = request.selection, !selection.isEmpty else {
        throw BridgeError.invalidRequest
    }
    let parts = name.split(separator: ":").map(String.init)
    guard parts.count >= 2,
          let ruleID = UUID(uuidString: parts[0]),
          let date = CalendarDate(iso: parts[1]) else {
        throw BridgeError.invalidRequest
    }
    guard selection == "complete" || selection == "snooze" else {
        throw BridgeError.invalidRequest
    }

    let practice = try dayPractice(store, on: date)
    guard let entry = practice.entries(on: date).first(where: { $0.rule.id == ruleID }) else {
        throw BridgeError.unknownRule
    }

    var wrote = false
    var markedKept = false
    let wasSettled = date == selectedDate && practice.isSettled(on: date)
    if selection == "complete" {
        if entry.isDispensed { throw BridgeError.notAsked }
        if !reminderSettled(entry) {
            try store.save(Occurrence(
                ruleID: ruleID, date: date, status: .completed, completedAt: Date()
            ))
            wrote = true
            markedKept = true
        }
    } else {
        ticker.snooze(ruleID: ruleID, date: date, until: Date().addingTimeInterval(60 * 60))
    }

    let decision = ticker.tick(planned: try plannedReminders(store), now: Date())
    let reminders = remindersPayload(decision, alsoWithdraw: name)
    if wrote {
        let today = CalendarDate(Date(), in: .current)
        var success = try homeSnapshot(store: store, on: selectedDate, weekCenter: weekCenter)
            .success(id: request.id, today: today.iso)
        let settledNow = success.week?.first { $0.date == selectedDate.iso }?.settled ?? false
        if markedKept, date == selectedDate, !wasSettled, settledNow {
            success.thanksgiving = "Glory to God for all things."
        }
        success.reminders = reminders
        respond(success)
        return
    }
    respond(BridgeSuccess(v: bridgeProtocolVersion, id: request.id, reminders: reminders))
}
