import ChotkiCore
import Foundation

// The library and the editor. Core decides which templates are offered, how a
// change is scoped, and when an activation opens or closes. The window lists
// them and reports what was saved.

struct LibrarySession {
    var query: String = ""
    var draft: Rule?
    /// Set when the draft is an existing rule. A new rule, including one
    /// prepared from a template, has none until it is saved.
    var originalID: UUID?
    var token: Int = 0
    var showingCaution = false

    mutating func closeEditor() {
        draft = nil
        originalID = nil
        showingCaution = false
    }

    mutating func present(_ rule: Rule, original: UUID?) {
        draft = rule
        originalID = original
        showingCaution = false
        token += 1
    }
}

private let customCautionText = "This section is for personalized routines aimed at improving your overall physical, mental, and spiritual health. It is not intended to enable you to manufacture your own Orthodoxy. We strongly recommend that where appropriate, custom rules be discussed with your priest or spiritual father. If that is not possible, keep these custom rules simple and attainable (e.g., jogging, swimming, sobriety)."

private let libraryIntro = "Select a prayer, reading, or discipline to add to your routine."

private let customNote = "Custom routines are usually taken on the advice of your priest or spiritual father."

private let seasonChoices: [(FastingSeason, String)] = [
    (.greatLent, "Great Lent"),
    (.nativityFast, "Nativity Fast"),
    (.apostlesFast, "Apostles' Fast"),
    (.dormitionFast, "Dormition Fast"),
]

private let scopeChoices: [(EditScope, String)] = [
    (.thisDay, "Just this day"),
    (.thisAndFuture, "This day and after"),
    (.wholeSeries, "The whole rule"),
]

private let weekdayLabels = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]

struct LibraryTermPayload: Encodable {
    var slug: String
    var term: String
}

struct LibraryTemplatePayload: Encodable {
    var id: String
    var title: String
    var summary: String
    var note: String?
    var observanceNote: String?
    var taken: Bool
    var ruleID: String?
    /// The first few terms the template names. The window opens these; it does not scan.
    var terms: [LibraryTermPayload] = []
}

struct LibraryGroupPayload: Encodable {
    var category: String
    var templates: [LibraryTemplatePayload]
}

struct LibraryCustomPayload: Encodable {
    var id: String
    var title: String
    var time: String
    var note: String?
    var attribution: String?
    var active: Bool
}

struct LibraryPayload: Encodable {
    var intro: String
    var query: String
    var groups: [LibraryGroupPayload]
    var customNote: String
    var custom: [LibraryCustomPayload]
    var cautionDismissed: Bool
    var fatherName: String
}

struct EditorChoicePayload: Encodable {
    var id: String
    var name: String
}

struct EditorWeekdayPayload: Encodable {
    var raw: Int
    var label: String
    var selected: Bool
}

struct EditorLeadPayload: Encodable {
    var raw: Int
    var label: String
    var selected: Bool
}

struct EditorPayload: Encodable {
    var open: Bool
    var caution: Bool
    var cautionText: String?
    var token: Int
    var isNew: Bool
    var ruleID: String?
    var title: String
    var note: String
    var source: String
    var kind: String
    var kinds: [String]
    var weekdays: [EditorWeekdayPayload]
    var monthDay: Int
    var shortMonth: String
    var season: String
    var seasons: [EditorChoicePayload]
    var onceDate: String
    var hasTime: Bool
    var hour: Int
    var minute: Int
    var reminders: Bool
    var leads: [EditorLeadPayload]
    var fatherName: String
    var givenByPriest: Bool
    var paused: Bool
    var scope: String
    var scopes: [EditorChoicePayload]
}

private struct Shelf {
    var settings: AppSettings
    var rules: [Rule]
    var activations: [Activation]
}

private func shelf(_ store: SQLiteStore) throws -> Shelf {
    Shelf(
        settings: try store.loadSettings() ?? .default,
        rules: try store.rules(includeArchived: true),
        activations: try store.activations(ruleID: nil)
    )
}

private func isPaused(_ rule: Rule, activations: [Activation]) -> Bool {
    !activations.contains { $0.ruleID == rule.id && $0.isOpen }
}

private func isActive(_ rule: Rule, activations: [Activation]) -> Bool {
    !rule.isArchived && !isPaused(rule, activations: activations)
}

private func titleMatches(_ rule: Rule, _ title: String) -> Bool {
    rule.title.compare(title, options: .caseInsensitive) == .orderedSame
}

private func suggestedBy(_ rule: Rule, father: String) -> String? {
    guard rule.givenByPriest == true else { return nil }
    let saved = rule.source?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !saved.isEmpty && saved != "the library" { return "Suggested by \(saved)" }
    let current = father.trimmingCharacters(in: .whitespacesAndNewlines)
    return current.isEmpty ? "Suggested by a priest or spiritual father" : "Suggested by \(current)"
}

private func libraryPayload(_ store: SQLiteStore, session: LibrarySession) throws -> LibraryPayload {
    let held = try shelf(store)
    let library = RuleLibrary.shared.scoped(to: held.settings.jurisdiction.tradition)
    let glossary = Glossary.shared(for: held.settings.jurisdiction.tradition)
    let query = session.query.trimmingCharacters(in: .whitespacesAndNewlines)
    let groups: [LibraryGroupPayload] = library.byCategory().compactMap { category, templates in
        let rows: [LibraryTemplatePayload] = templates.compactMap { template in
            if !query.isEmpty && template.title.range(of: query, options: .caseInsensitive) == nil {
                return nil
            }
            let active = held.rules.first {
                titleMatches($0, template.title) && isActive($0, activations: held.activations)
            }
            var note: String? = nil
            if let trigger = template.requiredTrigger,
               !held.settings.observances.setting(for: trigger).drivesRules,
               active == nil {
                note = "Taking this on will start observing \(ObservanceSettings.name(for: trigger))."
            }
            let terms = template.glossarySlugs.prefix(3).compactMap { slug in
                glossary.entry(slug: slug).map { LibraryTermPayload(slug: slug, term: $0.term) }
            }
            return LibraryTemplatePayload(
                id: template.id, title: template.title, summary: template.summary,
                note: template.note, observanceNote: note, taken: active != nil,
                ruleID: active?.id.uuidString, terms: terms
            )
        }
        return rows.isEmpty ? nil : LibraryGroupPayload(category: category.displayName, templates: rows)
    }
    let own = CustomLibrary.entries(from: held.rules).filter { rule in
        query.isEmpty || rule.title.range(of: query, options: .caseInsensitive) != nil
    }
    let father = held.settings.spiritualFatherName
    return LibraryPayload(
        intro: libraryIntro, query: session.query, groups: groups, customNote: customNote,
        custom: own.map { rule in
            LibraryCustomPayload(
                id: rule.id.uuidString, title: rule.title,
                time: rule.timeOfDay.map { Format.time($0, held.settings.clockStyle) } ?? "All day",
                note: rule.note, attribution: suggestedBy(rule, father: father),
                active: isActive(rule, activations: held.activations)
            )
        },
        cautionDismissed: held.settings.customCautionDismissed,
        fatherName: father.trimmingCharacters(in: .whitespacesAndNewlines)
    )
}

private func editorPayload(_ store: SQLiteStore, session: LibrarySession,
                           on date: CalendarDate) throws -> EditorPayload {
    let held = try shelf(store)
    let father = held.settings.spiritualFatherName.trimmingCharacters(in: .whitespacesAndNewlines)
    let rule = session.draft ?? Rule(title: "", recurrence: .daily)
    let form = RecurrenceForm(rule.recurrence)
    let reminders = rule.effectiveReminders
    let selectedLeads = Set(reminders.leads)
    let paused = session.originalID.flatMap { id in held.rules.first { $0.id == id } }
        .map { isPaused($0, activations: held.activations) } ?? false
    let isNew = session.originalID == nil
    return EditorPayload(
        open: session.draft != nil,
        caution: session.showingCaution && session.draft == nil,
        cautionText: session.showingCaution ? customCautionText : nil,
        token: session.token, isNew: isNew, ruleID: session.originalID?.uuidString,
        title: rule.title, note: rule.note ?? "", source: rule.source ?? "",
        kind: form.kind.rawValue, kinds: RecurrenceForm.Kind.allCases.map(\.rawValue),
        weekdays: Weekday.allCases.enumerated().map { index, day in
            EditorWeekdayPayload(raw: day.rawValue, label: weekdayLabels[index],
                                 selected: form.weekdays.contains(day))
        },
        monthDay: form.monthDay, shortMonth: form.shortMonthPolicy.rawValue,
        season: form.season.rawValue,
        seasons: seasonChoices.map { EditorChoicePayload(id: $0.0.rawValue, name: $0.1) },
        onceDate: (form.onceDate ?? date).iso,
        hasTime: rule.timeOfDay != nil, hour: rule.timeOfDay?.hour ?? 6,
        minute: rule.timeOfDay?.minute ?? 30, reminders: reminders.enabled,
        leads: ReminderLead.choices.map { lead in
            EditorLeadPayload(raw: lead.rawValue, label: lead.label, selected: selectedLeads.contains(lead))
        },
        fatherName: father, givenByPriest: rule.givenByPriest == true, paused: paused,
        scope: EditScope.wholeSeries.rawValue,
        scopes: isNew ? [] : scopeChoices.map { EditorChoicePayload(id: $0.0.rawValue, name: $0.1) }
    )
}

private func reconcileObservances(_ store: SQLiteStore) throws {
    var settings = try store.loadSettings() ?? .default
    let rules = try store.rules(includeArchived: false)
    let activations = try store.activations(ruleID: nil)
    let liturgical = LiturgicalService(store: store, jurisdiction: settings.jurisdiction,
                                      networkPolicy: .never)
    let practice = Practice(rules: rules, activations: activations, occurrences: [],
                            settings: settings, liturgical: liturgical)
    let wanted = practice.observancesNeeded()
    guard !wanted.isEmpty else { return }
    for trigger in wanted { settings.observances.observe(trigger) }
    try store.saveSettings(settings)
}

func preserveFatherName(_ former: String, store: SQLiteStore) throws {
    for var rule in try store.rules(includeArchived: true) where rule.givenByPriest == true {
        let recorded = rule.source?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard recorded.isEmpty || recorded == "the library" else { continue }
        rule.source = former
        try store.save(rule)
    }
}

private func applyEditorFields(_ request: BridgeRequest, onto rule: inout Rule,
                               father: String, on date: CalendarDate) throws {
    if let title = request.title {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw BridgeError.unnamedRule }
        rule.title = trimmed
    }
    guard !rule.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw BridgeError.unnamedRule
    }
    if let note = request.note {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        rule.note = trimmed.isEmpty ? nil : trimmed
    }
    var form = RecurrenceForm(rule.recurrence)
    if let kind = request.kind {
        guard let parsed = RecurrenceForm.Kind(rawValue: kind) else { throw BridgeError.invalidRequest }
        form.kind = parsed
    }
    if let days = request.weekdays {
        form.weekdays = Set(days.compactMap(Weekday.init(rawValue:)))
    }
    if let monthDay = request.monthDay {
        guard (1...31).contains(monthDay) else { throw BridgeError.invalidRequest }
        form.monthDay = monthDay
    }
    if let shortMonth = request.shortMonth {
        guard let policy = ShortMonthPolicy(rawValue: shortMonth) else { throw BridgeError.invalidRequest }
        form.shortMonthPolicy = policy
    }
    if let season = request.season {
        guard let parsed = FastingSeason(rawValue: season) else { throw BridgeError.invalidRequest }
        form.season = parsed
    }
    if let onceDate = request.onceDate {
        guard let day = CalendarDate(iso: onceDate) else { throw BridgeError.invalidRequest }
        form.onceDate = day
    }
    rule.recurrence = form.recurrence(fallback: date)
    if let hasTime = request.hasTime {
        if hasTime {
            let hour = request.hour ?? rule.timeOfDay?.hour ?? 6
            let minute = request.minute ?? rule.timeOfDay?.minute ?? 30
            guard (0...23).contains(hour), (0...59).contains(minute) else { throw BridgeError.invalidRequest }
            rule.timeOfDay = TimeOfDay(hour: hour, minute: minute)
        } else {
            rule.timeOfDay = nil
        }
    }
    if let enabled = request.reminders {
        let leads = (request.leads ?? rule.effectiveReminders.leads.map(\.rawValue)).compactMap(ReminderLead.init(rawValue:))
        rule.reminders = RuleReminders(enabled: enabled, leads: leads.isEmpty ? [.tenMinutes] : leads.sorted())
    }
    let given = request.givenByPriest ?? (rule.givenByPriest == true)
    let typed = (request.source ?? rule.source ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let recorded = (rule.source ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let remembered = (rule.givenByPriest == true && !recorded.isEmpty && recorded != "the library") ? recorded : father
    let retains = father.isEmpty && given && typed == remembered && !remembered.isEmpty
    rule.givenByPriest = father.isEmpty ? retains : given
    let selected = (given && !father.isEmpty) ? father : typed
    rule.source = selected.isEmpty ? nil : selected
}

private func requireRule(_ raw: String?, in rules: [Rule]) throws -> Rule {
    guard let raw, let id = UUID(uuidString: raw), let rule = rules.first(where: { $0.id == id }) else {
        throw BridgeError.invalidRequest
    }
    return rule
}

private func scope(from raw: String?) throws -> EditScope {
    guard let raw, let parsed = EditScope(rawValue: raw) else { throw BridgeError.invalidRequest }
    return parsed
}

func performLibrary(_ request: BridgeRequest, store: SQLiteStore, on date: CalendarDate,
                    weekCenter: CalendarDate, session: inout LibrarySession) throws {
    let today = CalendarDate(Date(), in: .current)
    var changedRecord = false

    switch request.op {
    case "library":
        session.query = request.query ?? ""

    case "prepareTemplate":
        guard let id = request.template else { throw BridgeError.invalidRequest }
        let held = try shelf(store)
        let library = RuleLibrary.shared.scoped(to: held.settings.jurisdiction.tradition)
        guard let template = library.template(id: id) else { throw BridgeError.invalidRequest }
        if held.rules.contains(where: { titleMatches($0, template.title) && isActive($0, activations: held.activations) }) {
            session.closeEditor()
            break
        }
        if let resting = held.rules.first(where: {
            titleMatches($0, template.title) && !$0.isArchived && isPaused($0, activations: held.activations)
        }) {
            var plan = EditPlan()
            plan.updatedRules = [CustomLibrary.takingUp(resting)]
            plan.newActivations = [Activation(ruleID: resting.id, from: today)]
            try store.apply(plan)
            try reconcileObservances(store)
            session.closeEditor()
            changedRecord = true
            break
        }
        session.present(template.makeRule(source: "the library"), original: nil)

    case "openEditor":
        if let raw = request.ruleID {
            let rule = try requireRule(raw, in: try store.rules(includeArchived: true))
            session.present(rule, original: rule.id)
        } else if try (store.loadSettings() ?? .default).customCautionDismissed {
            session.present(Rule(title: "", recurrence: .daily), original: nil)
        } else {
            session.closeEditor()
            session.showingCaution = true
        }

    case "acknowledgeCaution":
        if request.hideCaution == true {
            var settings = try store.loadSettings() ?? .default
            settings.customCautionDismissed = true
            try store.saveSettings(settings)
        }
        session.present(Rule(title: "", recurrence: .daily), original: nil)

    case "saveRule":
        guard var draft = session.draft else { throw BridgeError.invalidRequest }
        let father = try (store.loadSettings() ?? .default).spiritualFatherName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try applyEditorFields(request, onto: &draft, father: father, on: date)
        if let originalID = session.originalID {
            let original = try requireRule(originalID.uuidString, in: try store.rules(includeArchived: true))
            let chosen = try scope(from: request.scope ?? EditScope.wholeSeries.rawValue)
            let activations = try store.activations(ruleID: original.id)
            try store.apply(EditPlanner().edit(
                rule: original, changes: draft, activations: activations, on: date, scope: chosen
            ))
        } else {
            var plan = EditPlan()
            plan.newRules = [draft]
            let started: CalendarDate
            if let raw = request.from {
                guard let day = CalendarDate(iso: raw) else { throw BridgeError.invalidRequest }
                started = day
            } else {
                started = today
            }
            plan.newActivations = [Activation(ruleID: draft.id, from: started)]
            try store.apply(plan)
        }
        try reconcileObservances(store)
        session.closeEditor()
        changedRecord = true

    case "pauseRule":
        let rule = try requireRule(request.ruleID, in: try store.rules(includeArchived: false))
        let activations = try store.activations(ruleID: rule.id)
        try store.apply(EditPlanner().pause(rule: rule, activations: activations, on: today))
        session.closeEditor()
        changedRecord = true

    case "resumeRule":
        let rule = try requireRule(request.ruleID, in: try store.rules(includeArchived: true))
        var plan = EditPlanner().resume(rule: rule, on: today)
        plan.updatedRules = [CustomLibrary.takingUp(rule)]
        try store.apply(plan)
        try reconcileObservances(store)
        session.closeEditor()
        changedRecord = true

    case "removeRule":
        let rule = try requireRule(request.ruleID, in: try store.rules(includeArchived: true))
        let chosen = try scope(from: request.scope)
        let activations = try store.activations(ruleID: rule.id)
        try store.apply(EditPlanner().delete(
            rule: rule, activations: activations, on: date, scope: chosen
        ))
        session.closeEditor()
        changedRecord = true

    case "takeUp":
        let rule = try requireRule(request.ruleID, in: try store.rules(includeArchived: true))
        var plan = EditPlan()
        plan.updatedRules = [CustomLibrary.takingUp(rule)]
        if isPaused(rule, activations: try store.activations(ruleID: nil)) || rule.isArchived {
            plan.newActivations = [Activation(ruleID: rule.id, from: today)]
        }
        try store.apply(plan)
        try reconcileObservances(store)
        changedRecord = true

    case "setAside":
        let rule = try requireRule(request.ruleID, in: try store.rules(includeArchived: true))
        try store.save(CustomLibrary.settingAside(rule))
        changedRecord = true

    case "setSpiritualFather":
        guard let name = request.name, name.count <= 120 else { throw BridgeError.invalidRequest }
        var settings = try store.loadSettings() ?? .default
        let former = settings.spiritualFatherName.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !former.isEmpty && former != next { try preserveFatherName(former, store: store) }
        settings.spiritualFatherName = next
        try store.saveSettings(settings)

    default:
        throw BridgeError.unsupportedOperation(request.op)
    }

    let library = try libraryPayload(store, session: session)
    let editor = try editorPayload(store, session: session, on: date)
    if changedRecord {
        var success = try homeSnapshot(store: store, on: date, weekCenter: weekCenter)
            .success(id: request.id, today: today.iso)
        success.library = library
        success.editor = editor
        respond(success)
    } else {
        respond(BridgeSuccess(v: bridgeProtocolVersion, id: request.id, library: library, editor: editor))
    }
}
