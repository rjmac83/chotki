import ChotkiCore
import Foundation

// The progress report. Core scores the days and writes the sentences.
// The window paints them. Today is outside the report, and a stood-down day
// is already out of both sides of the count.

func resetRecord(_ store: SQLiteStore) throws {
    let today = CalendarDate(Date(), in: .current)
    let settings = try store.loadSettings() ?? .default
    let rules = try store.rules(includeArchived: false)
    let activations = try store.activations(ruleID: nil)
    let plan = RecordReset().plan(
        rules: rules, activations: activations,
        pausedRuleIDs: Set(settings.pausedRuleIDs), today: today
    )
    // Stretches first. The history goes only once they are cut.
    var stretchesOnly = plan
    stretchesOnly.newOccurrences = []
    try store.apply(stretchesOnly)
    for occurrence in try store.occurrences(ruleID: nil, from: nil, through: nil) {
        try store.removeOccurrence(ruleID: occurrence.ruleID, date: occurrence.date)
    }
    for standDown in plan.newOccurrences {
        try store.save(standDown)
    }
    eraseAutomaticBackups()
}

func performProgress(_ request: BridgeRequest, store: SQLiteStore, notice: String? = nil) throws {
    let days = request.days ?? 30
    guard (1...366).contains(days) else { throw BridgeError.invalidRequest }
    let today = CalendarDate(Date(), in: .current)
    let through = Practice.progressThrough(today: today)
    let from = through.adding(days: -(days - 1))
    let settings = try store.loadSettings() ?? .default
    let liturgical = LiturgicalService(
        store: store, jurisdiction: settings.jurisdiction, networkPolicy: .never
    )
    let practice = Practice(
        rules: try store.rules(includeArchived: false),
        activations: try store.activations(ruleID: nil),
        occurrences: try store.occurrences(ruleID: nil, from: from, through: through),
        settings: settings, liturgical: liturgical
    )
    let report = practice.report(days: days, today: today, timeZone: .current)
    let figure: Int? = settings.showConsistencyNumber
        ? report.overall.map { Int(($0 * 100).rounded()) }
        : nil
    let payload = ProgressPayload(
        heading: "Your progress up to \(Format.longDate(report.through))",
        through: report.through.iso,
        summary: report.summary,
        rules: report.perRule.filter(\.hasAnythingDue).map { score in
            ProgressRulePayload(
                id: score.ruleID.uuidString, title: score.title,
                count: "\(score.kept + score.keptLate) of \(score.scoreable)"
            )
        },
        figure: figure,
        figureNote: figure.map { _ in "Kept, over the \(days) days to then" },
        notice: notice
    )
    respond(BridgeSuccess(v: bridgeProtocolVersion, id: request.id, progress: payload))
}
