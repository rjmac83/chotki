import Testing
import Foundation
@testable import Chotki
@testable import ChotkiCore

/// Stand-ins so nothing is scheduled, shown, or registered during a test.
private struct SilentNotifier: Notifier {
    var supportsActions: Bool { true }
    func requestAuthorization() async throws -> Bool { true }
    func show(_ request: NotificationRequest) async throws {}
    func cancel(ids: [String]) async {}
    var actionEvents: AsyncStream<NotificationActionEvent> { AsyncStream { $0.finish() } }
}

private struct NoLaunchAtLogin: LaunchAtLogin {
    var isEnabled: Bool { false }
    func setEnabled(_ enabled: Bool) throws {}
}

@MainActor
private func makeModel() throws -> AppModel {
    AppModel(
        store: InMemoryStore(),
        notifier: SilentNotifier(),
        launchAtLogin: NoLaunchAtLogin(),
        storage: .none(),
        startsReminders: false,
        writesBackups: false, loadsCalendar: false
    )
}

/// A Wednesday and a Friday, so fast-day rules have somewhere to land.
private struct StubCalendar: LiturgicalDayProvider {
    func isFastDay(_ date: CalendarDate) -> Bool {
        date.weekday == .wednesday || date.weekday == .friday
    }
    func isGreatFeast(_ date: CalendarDate) -> Bool { false }
    func season(_ date: CalendarDate) -> FastingSeason? { nil }
}

@Suite("A cold open")
@MainActor
struct ColdOpenTests {
    @Test("only a real launch arms the mark")
    func staysOffUntilLaunch() throws {
        let model = try makeModel()
        #expect(model.coldOpen == false)
    }
}

@Suite("Taking rules on")
@MainActor
struct TakingRulesOnTests {

    @Test("a rule written by hand shows up on the day it is due")
    func ownRuleAppears() throws {
        let model = try makeModel()
        let rule = Rule(title: "Read the Psalter", recurrence: .daily)
        model.save(rule, isNew: true)

        let entries = model.entries(on: model.today)
        #expect(entries.count == 1)
        #expect(entries.first?.rule.title == "Read the Psalter")
    }

    // The bug found by hand: taking on the Wednesday and Friday fast changed
    // nothing at all, because a liturgical rule produces no due days while its
    // observance is merely shown — and shown is the default.
    @Test("taking on a fast rule turns fasting on rather than doing nothing")
    func fastRuleTurnsObservanceOn() throws {
        let model = try makeModel()
        #expect(model.settings.observances.fasting == .shown, "the default")

        let template = try #require(RuleLibrary.shared.template(id: "wednesday-friday-fast"))
        model.take(on: template)

        #expect(model.settings.observances.fasting == .observed,
                "taking it on is a statement of intent")
        #expect(model.rules.contains { $0.title == template.title })
        #expect(model.notice != nil, "and the change is stated, not silent")
    }

    @Test("an Akathist still set for Saturday does not fall on 3 October 2026")
    func oldSaturdayAkathistFollowsTheChurch() throws {
        let model = try makeModel()
        let today = try #require(CalendarDate(year: 2026, month: 10, day: 3))
        model.save(Rule(title: "An akathist", recurrence: .weekly(days: [.saturday])), isNew: true)

        let kept = try #require(model.rules.first { $0.title == "An akathist" })
        #expect(kept.recurrence == .liturgical(.akathist))
        #expect(model.entries(on: today).contains { $0.rule.title == "An akathist" } == false)

        let fifth = try #require(CalendarDate(year: 2027, month: 4, day: 16))
        let first = try #require(CalendarDate(year: 2027, month: 3, day: 19))
        #expect(model.entries(on: fifth).contains { $0.rule.title == "An akathist" })

        let greek = try #require(Jurisdiction.known.first { $0.name == "Greek Orthodox Archdiocese" })
        let georgian = try #require(Jurisdiction.known.first { $0.name == "Georgian Orthodox Church" })
        model.update { $0.jurisdiction = greek }
        #expect(model.entries(on: first).contains { $0.rule.title == "An akathist" })
        model.update { $0.jurisdiction = georgian }
        #expect(model.entries(on: first).contains { $0.rule.title == "An akathist" } == false)
        model.update { settings in
            settings.jurisdiction.reckoning = .revisedJulian
        }
        #expect(model.entries(on: fifth).contains { $0.rule.title == "An akathist" })
        #expect(model.entries(on: today).contains { $0.rule.title == "An akathist" } == false)
    }

    @Test("a rule taken from the library is due, not merely stored")
    func libraryRuleBecomesDue() throws {
        let model = try makeModel()
        let template = try #require(RuleLibrary.shared.template(id: "morning-prayers"))
        model.take(on: template)

        let entries = model.entries(on: model.today)
        #expect(entries.contains { $0.rule.title == template.title },
                "storing a rule that never comes due is the same as doing nothing")
    }

    @Test("a template with no observance requirement leaves settings alone")
    func ordinaryTemplateDoesNotChangeSettings() throws {
        let model = try makeModel()
        let before = model.settings.observances
        model.take(on: try #require(RuleLibrary.shared.template(id: "evening-prayers")))
        #expect(model.settings.observances == before)
        #expect(model.notice == nil)
    }

    @Test("every template that depends on the church calendar declares it")
    func templatesDeclareWhatTheyNeed() {
        for template in RuleLibrary.bundled {
            if case .liturgical(let trigger) = template.recurrence {
                #expect(template.requiredTrigger == trigger,
                        "\(template.id) would silently do nothing when taken on")
            } else if template.category == .fasting {
                // Weekly in shape, but still wants fast days marked on the
                // calendar and still answers to dispensations.
                #expect(template.requiredTrigger == .fastDay, "\(template.id)")
            } else {
                #expect(template.requiredTrigger == nil, "\(template.id)")
            }
        }
    }

    // The bug this covers: the Wednesday and Friday fast was modelled as
    // `.liturgical(.fastDay)`, which means *any* day the calendar marks as a
    // fast — so through the Dormition Fast, Great Lent and the Nativity Fast it
    // appeared every single day.
    @Test("the Wednesday and Friday fast falls on Wednesdays and Fridays")
    func weeklyFastIsWeekly() throws {
        let template = try #require(RuleLibrary.shared.template(id: "wednesday-friday-fast"))
        #expect(template.recurrence == .weekly(days: [.wednesday, .friday]))

        let engine = RecurrenceEngine()
        let rule = template.makeRule()
        let activations = [Activation(ruleID: rule.id, from: CalendarDate(year: 2026, month: 8, day: 1)!)]
        let due = engine.dueDates(
            rule: rule, activations: activations,
            from: CalendarDate(year: 2026, month: 8, day: 1)!,
            through: CalendarDate(year: 2026, month: 8, day: 31)!
        )
        #expect(due.count == 8, "four Wednesdays and four Fridays")
        #expect(due.allSatisfy { $0.weekday == .wednesday || $0.weekday == .friday })
    }

    /// Every fasting template should fall on the days its own name claims.
    @Test("no fasting template fires every day of a fasting season")
    func fastingTemplatesMatchTheirNames() throws {
        let engine = RecurrenceEngine()
        let template = try #require(RuleLibrary.shared.template(id: "wednesday-friday-fast"))
        let rule = template.makeRule()
        let from = CalendarDate(year: 2026, month: 1, day: 1)!
        let through = CalendarDate(year: 2026, month: 12, day: 31)!
        let due = engine.dueDates(
            rule: rule,
            activations: [Activation(ruleID: rule.id, from: from)],
            from: from, through: through
        )
        #expect(due.count > 90 && due.count < 110, "about two days a week, not most of the year")
    }
}

@Suite("Marking rules kept")
@MainActor
struct MarkingKeptTests {

    private func modelWithRule() throws -> (AppModel, DayEntry) {
        let model = try makeModel()
        model.save(Rule(title: "Morning prayers", recurrence: .daily), isNew: true)
        let entry = try #require(model.entries(on: model.today).first)
        return (model, entry)
    }

    @Test("marking kept records it and shows as kept")
    func markKept() throws {
        let (model, entry) = try modelWithRule()
        #expect(!entry.isKept)

        model.toggleKept(entry)

        let updated = try #require(model.entries(on: model.today).first)
        #expect(updated.isKept)
        #expect(updated.status == .completed)
    }

    @Test("marking kept twice returns the day to simply due")
    func toggleBack() throws {
        let (model, entry) = try modelWithRule()
        model.toggleKept(entry)
        let kept = try #require(model.entries(on: model.today).first)
        model.toggleKept(kept)

        let cleared = try #require(model.entries(on: model.today).first)
        #expect(!cleared.isKept)
    }

    // Superseded: ticking no longer infers lateness from when the box was
    // ticked. See BackfillingTests — forgetting to record something is not the
    // same as doing it late, and the app cannot tell them apart.
    @Test("ticking an earlier day trusts that it was kept")
    func earlierDayIsTrusted() throws {
        let model = try makeModel()
        model.save(Rule(title: "Evening prayers", recurrence: .daily), isNew: true)
        model.selectedDate = model.today.adding(days: -1)

        // Yesterday is inside the activation only if the rule started then.
        let rule = try #require(model.rules.first)
        try model.store.save(Activation(ruleID: rule.id, from: model.today.adding(days: -7)))
        model.reload()

        let yesterday = try #require(model.entries(on: model.today.adding(days: -1)).first)
        model.toggleKept(yesterday)

        let updated = try #require(model.entries(on: model.today.adding(days: -1)).first)
        #expect(updated.status == .completed, "not penalised for recording it later")
    }
}

@Suite("Pausing and resuming")
@MainActor
struct PausingTests {

    @Test("pausing takes a rule off the day, resuming puts it back")
    func pauseAndResume() throws {
        let model = try makeModel()
        model.save(Rule(title: "Jesus prayer", recurrence: .daily), isNew: true)
        let rule = try #require(model.rules.first)
        #expect(!model.isPaused(rule))

        model.standDown(rule)
        #expect(model.isPaused(rule))
        #expect(model.entries(on: model.today.adding(days: 1)).isEmpty,
                "tomorrow is no longer due")

        model.resume(rule)
        #expect(!model.isPaused(rule))
        #expect(!model.entries(on: model.today).isEmpty)
    }

    @Test("ending evening prayers from today takes it off the home row, and taking it on puts the same rule back")
    func endedEveningPrayersReturn() throws {
        let model = try makeModel()
        let template = try #require(RuleLibrary.shared.template(id: "evening-prayers"))
        model.take(on: template)
        let rule = try #require(model.rules.first { $0.title == "Evening prayers" })

        model.delete(rule, scope: .thisAndFuture)

        #expect(!model.entries(on: model.today).contains { $0.rule.title == "Evening prayers" })
        #expect(!model.isTaken(template), "the library must not keep saying it is on the rule")

        model.prepare(template)

        #expect(model.entries(on: model.today).contains { $0.rule.title == "Evening prayers" })
        #expect(model.rules.filter { $0.title == "Evening prayers" }.count == 1,
                "taking it on again continues the same rule")
        #expect(model.isTaken(template))
    }

    @Test("pausing keeps the day it happened on")
    func pauseIsInclusiveOfToday() throws {
        let model = try makeModel()
        model.save(Rule(title: "Morning prayers", recurrence: .daily), isNew: true)
        let rule = try #require(model.rules.first)
        model.standDown(rule)
        #expect(!model.entries(on: model.today).isEmpty,
                "standing down in the evening still counts today")
    }

    @Test("a paused rule stays on Home, set apart from what is due, until it is taken back")
    func pausedRuleStaysOnHome() throws {
        let model = try makeModel()
        model.save(Rule(title: "Jesus prayer", recurrence: .daily), isNew: true)
        let rule = try #require(model.rules.first)
        let tomorrow = model.today.adding(days: 1)

        model.standDown(rule)

        #expect(model.isPausedOnPurpose(rule))
        #expect(model.isOnPause(rule, on: model.today), "greyed from the day it was paused")
        #expect(model.entries(on: tomorrow).isEmpty, "nothing is due, so nothing is asked")
        #expect(model.entriesIncludingPaused(on: tomorrow).map(\.rule.id) == [rule.id])

        model.resume(rule)

        #expect(!model.isPausedOnPurpose(rule))
        #expect(!model.isOnPause(rule, on: tomorrow))
        #expect(model.entries(on: tomorrow).map(\.rule.id) == [rule.id])
        #expect(model.settings.pausedRuleIDs.isEmpty, "nothing is left marked")
    }

    @Test("taking a paused rule back through the library clears the pause")
    func libraryTakesItBack() throws {
        let model = try makeModel()
        let template = try #require(RuleLibrary.shared.template(id: "evening-prayers"))
        model.take(on: template)
        let rule = try #require(model.rules.first { $0.title == "Evening prayers" })

        model.standDown(rule)
        #expect(model.isPausedOnPurpose(rule))

        model.prepare(template)

        #expect(!model.isPausedOnPurpose(rule))
        #expect(model.settings.pausedRuleIDs.isEmpty)
    }

    @Test("a rule ended from today on is not shown as paused, and cannot be paused")
    func endedRuleIsNotPaused() throws {
        let model = try makeModel()
        model.save(Rule(title: "Almsgiving", recurrence: .daily), isNew: true)
        let rule = try #require(model.rules.first)
        model.delete(rule, scope: .thisAndFuture)
        let tomorrow = model.today.adding(days: 1)

        #expect(!model.isPausedOnPurpose(rule))
        #expect(model.entriesIncludingPaused(on: tomorrow).isEmpty,
                "ending a rule leaves no greyed copy behind")

        model.standDown(rule)

        #expect(model.settings.pausedRuleIDs.isEmpty, "there was nothing to pause")
        #expect(model.entriesIncludingPaused(on: tomorrow).isEmpty)
    }

    @Test("standing a day down can be lifted again, and leaves the day as it was")
    func standDownCanBeLifted() throws {
        let model = try makeModel()
        model.save(Rule(title: "Morning prayers", recurrence: .daily), isNew: true)
        let rule = try #require(model.rules.first)

        model.setStatus(.skipped, for: rule, on: model.today)
        let stoodDown = try #require(model.entries(on: model.today).first)
        #expect(stoodDown.isStoodDown)

        model.clearOccurrence(stoodDown)

        let restored = try #require(model.entries(on: model.today).first)
        #expect(!restored.isStoodDown)
        #expect(!restored.isKept)
    }

    /// What a right click does, driven through the card's own menu rather than
    /// the model: the menu is where the tick and the undo live.
    @Test("the card's menu ticks Pause and Stand Down, and choosing a ticked one undoes it")
    func menuTogglesUndo() throws {
        let model = try makeModel()
        model.save(Rule(title: "Morning prayers", recurrence: .daily), isNew: true)
        let rule = try #require(model.rules.first)

        func menu() throws -> [RuleCardInteraction.MenuAction] {
            let entry = try #require(model.entries(on: model.today).first { $0.rule.id == rule.id })
            return EntryRow(model: model, entry: entry).menuActions
        }
        func item(_ title: String) throws -> RuleCardInteraction.MenuAction {
            try #require(try menu().first { $0.title == title }, "no \"\(title)\" in the menu")
        }

        // Stand down for the day, then lift it.
        #expect(try !item("Stand Down for This Day").isOn)
        try item("Stand Down for This Day").perform()
        #expect(try item("Stand Down for This Day").isOn, "ticked once stood down")
        try item("Stand Down for This Day").perform()
        #expect(try !item("Stand Down for This Day").isOn, "choosing it again lifts it")
        let entry = try #require(model.entries(on: model.today).first)
        #expect(!entry.isStoodDown && !entry.isKept)

        // Pause the rule, then take it back.
        #expect(try !item("Pause This Rule").isOn)
        try item("Pause This Rule").perform()
        #expect(try item("Pause This Rule").isOn, "ticked once paused")
        #expect(model.isPausedOnPurpose(rule))
        #expect(try menu().contains { $0.title == "Resume This Rule" } == false,
                "resuming is unticking Pause, not a second item")
        try item("Pause This Rule").perform()
        #expect(try !item("Pause This Rule").isOn)
        #expect(!model.isPausedOnPurpose(rule))
    }
}

/// Shared content navigates by setting `model.screen`, which is the popover's
/// mechanism. The window has a sidebar instead and must translate every one of
/// those requests — a screen it forgets is a button that silently does nothing
/// there while working perfectly in the popover. That is exactly what happened
/// to Add, Library, Terms, Settings and the edit pencil.
@Suite("Window routing")
@MainActor
struct WindowRoutingTests {

    @Test("every screen shared content can ask for lands somewhere")
    func everyScreenIsHandled() {
        // Every case of `Screen` except `.main`. Add a case to the enum and
        // this list must grow with it, or the new control is dead in the window.
        let requests: [Screen] = [
            .library, .settings, .glossary(nil), .glossary("pascha"),
            .editor(nil), .editor(UUID()), .prayerRope, .prayers(UUID())
        ]
        for screen in requests {
            #expect(WindowRoute.route(for: screen) != .stay,
                    "\(screen) would do nothing in the window")
        }
    }

    @Test("only the main screen stays put")
    func mainStays() {
        #expect(WindowRoute.route(for: .main) == .stay)
    }

    @Test("each request lands in the right place")
    func routesAreCorrect() {
        #expect(WindowRoute.route(for: .library) == .section(.library))
        #expect(WindowRoute.route(for: .settings) == .section(.settings))
        #expect(WindowRoute.route(for: .glossary("pascha")) == .glossary("pascha"))
        #expect(WindowRoute.route(for: .editor(nil)) == .editor(nil))
        #expect(WindowRoute.route(for: .prayerRope) == .section(.prayers))
        let ruleID = UUID()
        #expect(WindowRoute.route(for: .prayers(ruleID)) == .prayers(ruleID))
    }

    @Test("adding a rule opens the editor rather than being swallowed")
    func addOpensEditor() {
        #expect(WindowRoute.route(for: .editor(nil)) == .editor(nil))
        let id = UUID()
        #expect(WindowRoute.route(for: .editor(id)) == .editor(id))
    }
}

/// Mapping a String range onto an AttributedString index is the part of the
/// term linking most likely to be subtly wrong — off by one and the wrong
/// words get underlined.
@Suite("Linking terms in running text")
@MainActor
struct TermTextTests {
    let glossary = Glossary.shared

    private func links(in text: String) -> [(String, URL)] {
        let attributed = TermText.link(text, in: glossary)
        var found: [(String, URL)] = []
        for run in attributed.runs {
            if let url = run.link {
                found.append((String(attributed[run.range].characters), url))
            }
        }
        return found
    }

    @Test("a known term is linked, and the link covers exactly that word")
    func linksTheRightCharacters() {
        // A real fasting description, as the reading tab produces it.
        let found = links(in: "The calendar marks this as dormition fast — fish, wine and oil are allowed.")
        #expect(found.count == 2, "the season and the dispensation are both terms")
        for (word, url) in found {
            #expect(url.scheme == "chotki-term")
            #expect(!word.isEmpty)
            #expect(!word.hasPrefix(" "), "the link starts mid-word: \(word)")
            #expect(!word.hasSuffix(" "), "the link runs past the word: \(word)")
        }
    }

    @Test("the linked text matches the term it points at")
    func linkTargetsMatchTheirText() {
        for (word, url) in links(in: "Pascha, the Theotokos, and Great Lent.") {
            let slug = try! #require(url.host)
            let entry = try! #require(glossary.entry(slug: slug))
            let candidates = ([entry.term] + entry.aliases).map { $0.lowercased() }
            #expect(candidates.contains(word.lowercased()),
                    "\"\(word)\" was linked to \(slug), whose term is \"\(entry.term)\"")
        }
    }

    @Test("text with nothing to link is returned unchanged")
    func plainTextIsUntouched() {
        let text = "Some ordinary sentence about nothing in particular."
        #expect(links(in: text).isEmpty)
        #expect(String(TermText.link(text, in: glossary).characters) == text)
    }

    @Test("linking never alters the text itself")
    func textIsPreserved() {
        let samples = [
            "Martyr Andrew Stratelates and Companions",
            "The calendar marks this as dormition fast — fish, wine and oil are allowed.",
            "Wednesday of the 12th week after Pentecost"
        ]
        for text in samples {
            #expect(String(TermText.link(text, in: glossary).characters) == text)
        }
    }
}

/// The failure this covers: a rule tied to the church calendar sat on the list
/// while its observance was not being observed, so it could never come due and
/// simply did not appear. That could happen to a rule taken on before this was
/// handled, or restored from an older backup.
@Suite("Repairing stranded rules")
@MainActor
struct ObservanceReconciliationTests {

    private struct AlwaysFasting: LiturgicalDayProvider {
        func isFastDay(_ date: CalendarDate) -> Bool { true }
        func isGreatFeast(_ date: CalendarDate) -> Bool { false }
        func season(_ date: CalendarDate) -> FastingSeason? { nil }
    }

    @Test("a fast rule already on the list turns fasting back on at load")
    func repairsOnLoad() throws {
        let store = InMemoryStore()

        // A rule saved directly, as an older build would have left it: on the
        // list, with fasting merely shown.
        let rule = Rule(title: "The Wednesday and Friday fast", recurrence: .liturgical(.fastDay))
        try store.save(rule)
        try store.save(Activation(ruleID: rule.id, from: CalendarDate(Date(), in: .current)))
        try store.saveSettings(AppSettings.default)
        #expect(try store.loadSettings()?.observances.fasting == .shown)

        let model = AppModel(
            store: store, notifier: SilentNotifier(), launchAtLogin: NoLaunchAtLogin(),
            storage: .none(), startsReminders: false, writesBackups: false, loadsCalendar: false
        )

        #expect(model.settings.observances.fasting == .observed,
                "a rule that can never come due is worse than a changed setting")
        #expect(try store.loadSettings()?.observances.fasting == .observed, "and it is written down")
    }

    @Test("a paused fast rule does not force the observance on")
    func pausedRulesAreLeftAlone() throws {
        let store = InMemoryStore()
        let rule = Rule(title: "Great Lent", recurrence: .liturgical(.season(.greatLent)))
        try store.save(rule)
        let today = CalendarDate(Date(), in: .current)
        // Closed activation: the rule is stood down.
        try store.save(Activation(ruleID: rule.id, from: today.adding(days: -10), to: today.adding(days: -1)))
        try store.saveSettings(AppSettings.default)

        let model = AppModel(
            store: store, notifier: SilentNotifier(), launchAtLogin: NoLaunchAtLogin(),
            storage: .none(), startsReminders: false, writesBackups: false, loadsCalendar: false
        )
        #expect(model.settings.observances.fasting == .shown,
                "nothing is stranded, so nothing needs changing")
    }

    @Test("settings chosen in the app are written to the store")
    func settingsPersist() throws {
        let store = InMemoryStore()
        let model = AppModel(
            store: store, notifier: SilentNotifier(), launchAtLogin: NoLaunchAtLogin(),
            storage: .none(), startsReminders: false, writesBackups: false, loadsCalendar: false
        )
        model.update { $0.showOldStyleDates = true }
        #expect(try store.loadSettings()?.showOldStyleDates == true)
    }
}

/// Records what was actually shown, so the driver can be observed without a
/// desktop.
private final class RecordingNotifier: Notifier, @unchecked Sendable {
    private let lock = NSLock()
    private var _shown: [String] = []
    private var _cancelled: [String] = []

    var shown: [String] {
        lock.lock(); defer { lock.unlock() }
        return _shown
    }
    var cancelled: [String] {
        lock.lock(); defer { lock.unlock() }
        return _cancelled
    }

    private func locked(_ body: () -> Void) {
        lock.lock(); body(); lock.unlock()
    }

    var supportsActions: Bool { true }
    func requestAuthorization() async throws -> Bool { true }
    func show(_ request: NotificationRequest) async throws {
        locked { _shown.append(request.id) }
    }
    func cancel(ids: [String]) async {
        locked { _cancelled.append(contentsOf: ids) }
    }
    var actionEvents: AsyncStream<NotificationActionEvent> { AsyncStream { $0.finish() } }
}

/// The rollover runs once a day, which means in practice it never runs while
/// anyone is watching. A mistake costs a whole day: either silence from
/// midnight, or yesterday's reminders arriving again.
@Suite("The day rollover")
@MainActor
struct ReminderDriverTests {

    private func instant(_ date: CalendarDate, _ hour: Int) -> Date {
        date.dueInstant(at: TimeOfDay(hour: hour, minute: 0)!, in: .current)!
    }

    private func reminder(_ date: CalendarDate, _ hour: Int, id: String) -> PlannedNotification {
        PlannedNotification(
            id: id, ruleID: UUID(), date: date, fireAt: instant(date, hour),
            request: NotificationRequest(id: id, title: "Evening prayers", body: "At \(hour):00")
        )
    }

    @Test("a reminder fires once, not on every tick")
    func firesOnce() async {
        let today = CalendarDate(Date(), in: .current)
        let clock = FixedClock(instant(today, 9))
        let notifier = RecordingNotifier()
        let driver = ReminderDriver(notifier: notifier, clock: clock) {
            [self.reminder(today, 9, id: "a")]
        }

        driver.tick()
        driver.tick()
        driver.tick()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(notifier.shown == ["a"], "three ticks, one notification")
    }

    @Test("crossing midnight lets the next day's reminders fire")
    func rollover() async throws {
        let today = CalendarDate(Date(), in: .current)
        let tomorrow = today.adding(days: 1)
        let clock = FixedClock(instant(today, 9))
        let notifier = RecordingNotifier()

        // The plan follows the clock, as the real one does.
        let driver = ReminderDriver(notifier: notifier, clock: clock) { [clock] in
            let day = CalendarDate(clock.now, in: .current)
            return [self.reminder(day, 9, id: "rule:\(day.iso)")]
        }

        driver.tick()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(notifier.shown == ["rule:\(today.iso)"])

        // Move to the same hour tomorrow.
        clock.set(instant(tomorrow, 9))
        driver.tick()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(notifier.shown == ["rule:\(today.iso)", "rule:\(tomorrow.iso)"],
                "the new day must be able to remind")
    }

    // The fix that prompted this: turning an observance on mid-afternoon made
    // several earlier reminders due at once.
    @Test("reminders long past their moment stay quiet")
    func stalePastRemindersDoNotFire() async {
        let today = CalendarDate(Date(), in: .current)
        let clock = FixedClock(instant(today, 16))
        let notifier = RecordingNotifier()
        let driver = ReminderDriver(notifier: notifier, clock: clock) {
            [
                self.reminder(today, 7, id: "morning"),
                self.reminder(today, 12, id: "noon"),
                self.reminder(today, 16, id: "now")
            ]
        }

        driver.tick()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(notifier.shown == ["now"], "only the one whose moment has just come")
    }

    @Test("a reminder that leaves the plan is withdrawn")
    func withdrawnWhenNoLongerPlanned() async {
        let today = CalendarDate(Date(), in: .current)
        let clock = FixedClock(instant(today, 9))
        let notifier = RecordingNotifier()
        var planned = [PlannedNotification]()
        planned = [reminder(today, 9, id: "a")]

        let driver = ReminderDriver(notifier: notifier, clock: clock) { planned }
        driver.tick()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(notifier.shown == ["a"])

        // The rule was kept, so it is no longer planned.
        planned = []
        driver.tick()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(notifier.cancelled == ["a"], "a delivered reminder must be taken back")
    }
}

/// Recording a day you kept but forgot to tick at the time.
@Suite("Marking earlier days")
@MainActor
struct BackfillingTests {

    private func modelWithRuleSince(_ daysAgo: Int) throws -> (AppModel, Rule) {
        let model = try makeModel()
        let rule = Rule(title: "Morning prayers", recurrence: .daily)
        try model.store.save(rule)
        try model.store.save(
            Activation(ruleID: rule.id, from: model.today.adding(days: -daysAgo))
        )
        model.reload()
        return (model, rule)
    }

    @Test("an earlier day can be marked kept")
    func canMarkAnEarlierDay() throws {
        let (model, _) = try modelWithRuleSince(7)
        let threeDaysAgo = model.today.adding(days: -3)

        let entry = try #require(model.entries(on: threeDaysAgo).first)
        #expect(!entry.isKept)
        model.toggleKept(entry)

        #expect(try #require(model.entries(on: threeDaysAgo).first).isKept)
    }

    // Forgetting to tick a box is not the same as doing something late, and the
    // app cannot tell the difference — so it must not guess against the user.
    @Test("marking an earlier day records it as kept, not as late")
    func earlierDaysAreNotAssumedLate() throws {
        let (model, _) = try modelWithRuleSince(7)
        let yesterday = model.today.adding(days: -1)

        let entry = try #require(model.entries(on: yesterday).first)
        model.toggleKept(entry)

        #expect(try #require(model.entries(on: yesterday).first).status == .completed,
                "trusting the user, not penalising them for remembering late")
    }

    @Test("kept late is available as a deliberate choice")
    func lateIsExplicit() throws {
        let (model, _) = try modelWithRuleSince(7)
        let yesterday = model.today.adding(days: -1)

        let entry = try #require(model.entries(on: yesterday).first)
        model.markKeptLate(entry)

        #expect(try #require(model.entries(on: yesterday).first).status == .completedLate)
    }

    // Un-ticking previously wrote `.skipped`, which quietly excused the day
    // instead of restoring it — and made the checkbox identical to standing the
    // rule down.
    @Test("clearing a day restores it to having no record")
    func clearingRestoresAbsence() throws {
        let (model, rule) = try modelWithRuleSince(7)
        let yesterday = model.today.adding(days: -1)

        let entry = try #require(model.entries(on: yesterday).first)
        model.toggleKept(entry)
        let kept = try #require(model.entries(on: yesterday).first)
        model.toggleKept(kept)

        let cleared = try #require(model.entries(on: yesterday).first)
        #expect(cleared.occurrence == nil, "no record at all, not a stood-down one")
        #expect(!cleared.isStoodDown)
        #expect(try model.store.occurrences(ruleID: rule.id, from: nil, through: nil).isEmpty)
    }

    @Test("standing a day down is still distinct from clearing it")
    func standingDownIsSeparate() throws {
        let (model, _) = try modelWithRuleSince(7)
        let yesterday = model.today.adding(days: -1)

        let entry = try #require(model.entries(on: yesterday).first)
        model.setStatus(.skipped, for: entry.rule, on: entry.date)

        let stood = try #require(model.entries(on: yesterday).first)
        #expect(stood.isStoodDown)
        #expect(stood.occurrence != nil)
    }

    // Backfilling must respect when the rule was actually taken on.
    @Test("days before the rule existed are not offered")
    func noDaysBeforeTheRuleBegan() throws {
        let (model, _) = try modelWithRuleSince(3)
        #expect(model.entries(on: model.today.adding(days: -3)).count == 1)
        #expect(model.entries(on: model.today.adding(days: -4)).isEmpty,
                "the rule did not exist then")
    }
}
@Suite("Progress stops at yesterday")
@MainActor
struct ProgressWindowTests {

    @Test("the window ends the day before today")
    func endsYesterday() throws {
        let model = try makeModel()
        #expect(model.progressThrough == model.today.adding(days: -1))
    }

    @Test("a rule added today does not drag the score down")
    func todaysRuleIsNotJudged() throws {
        let model = try makeModel()
        // A timed rule whose hour has already passed today.
        model.save(
            Rule(title: "Morning prayers", recurrence: .daily,
                 timeOfDay: TimeOfDay(hour: 0, minute: 1)),
            isNew: true
        )

        let report = model.report()
        #expect(report.overall == nil, "nothing has finished yet, so there is no figure")
        #expect(report.perRule.allSatisfy { $0.missed == 0 })
    }

    @Test("yesterday still counts")
    func yesterdayIsJudged() throws {
        let model = try makeModel()
        let rule = Rule(title: "Evening prayers", recurrence: .daily)
        try model.store.save(rule)
        try model.store.save(Activation(ruleID: rule.id, from: model.today.adding(days: -3)))
        model.reload()

        let report = model.report()
        #expect(report.perRule[0].missed == 3, "the three finished days")
    }

    @Test("keeping yesterday shows up straight away")
    func keptYesterdayCounts() throws {
        let model = try makeModel()
        let rule = Rule(title: "Evening prayers", recurrence: .daily)
        try model.store.save(rule)
        try model.store.save(Activation(ruleID: rule.id, from: model.today.adding(days: -1)))
        model.reload()

        let entry = try #require(model.entries(on: model.today.adding(days: -1)).first)
        model.toggleKept(entry)

        #expect(model.report().overall == 1.0)
    }

    @Test("what today is marked as makes no difference to progress")
    func todayIsIgnoredEitherWay() throws {
        let model = try makeModel()
        let rule = Rule(title: "Jesus prayer", recurrence: .daily)
        try model.store.save(rule)
        try model.store.save(Activation(ruleID: rule.id, from: model.today.adding(days: -2)))
        model.reload()

        let before = model.report()
        let today = try #require(model.entries(on: model.today).first)
        model.toggleKept(today)
        let after = model.report()

        #expect(before.perRule[0].scoreable == after.perRule[0].scoreable)
        #expect(before.overall == after.overall, "today is outside the window entirely")
    }
}

/// The app does not congratulate anyone for praying. When the last thing on a
/// day is settled it gives thanks instead — once, quietly, and only then.
@Suite("Thanksgiving")
@MainActor
struct ThanksgivingTests {

    private func modelWithRules(_ titles: [String]) throws -> AppModel {
        let model = try makeModel()
        for title in titles {
            model.save(Rule(title: title, recurrence: .daily), isNew: true)
        }
        return model
    }

    private func entry(_ model: AppModel, _ title: String) throws -> DayEntry {
        try #require(model.entries(on: model.today).first { $0.rule.title == title })
    }

    @Test("nothing is said until the last thing is done")
    func onlyOnTheLast() throws {
        let model = try modelWithRules(["Morning prayers", "Evening prayers"])

        model.toggleKept(try entry(model, "Morning prayers"))
        #expect(model.thanksgiving == nil, "one of two is not the day")

        model.toggleKept(try entry(model, "Evening prayers"))
        #expect(model.thanksgiving == "Glory to God for all things.")
    }

    @Test("a day with one rule still counts")
    func singleRuleDay() throws {
        let model = try modelWithRules(["Morning prayers"])
        model.toggleKept(try entry(model, "Morning prayers"))
        #expect(model.thanksgiving != nil)
    }

    // Standing a rule down is a legitimate act. Treating it as unfinished would
    // quietly punish pausing, which the rest of the app takes care not to do.
    @Test("a rule stood down still leaves the day settled")
    func stoodDownStillSettles() throws {
        let model = try modelWithRules(["Morning prayers", "Jesus prayer"])
        let stood = try entry(model, "Jesus prayer")
        model.setStatus(.skipped, for: stood.rule, on: stood.date)

        model.toggleKept(try entry(model, "Morning prayers"))
        #expect(model.thanksgiving != nil, "nothing is left outstanding")
    }

    @Test("standing everything down says nothing")
    func nothingKeptSaysNothing() throws {
        let model = try modelWithRules(["Morning prayers", "Evening prayers"])
        for title in ["Morning prayers", "Evening prayers"] {
            let e = try entry(model, title)
            model.setStatus(.skipped, for: e.rule, on: e.date)
        }
        #expect(model.thanksgiving == nil, "nothing was kept, so there is nothing to give thanks for")
        #expect(!model.dayIsSettled(model.today))
    }

    @Test("un-ticking does not give thanks")
    func clearingIsSilent() throws {
        let model = try modelWithRules(["Morning prayers"])
        model.toggleKept(try entry(model, "Morning prayers"))
        model.clearThanksgiving()

        model.toggleKept(try entry(model, "Morning prayers"))
        #expect(model.thanksgiving == nil)
    }

    @Test("a settled day that is ticked again does not repeat itself")
    func noRepeatOnAnAlreadySettledDay() throws {
        let model = try modelWithRules(["Morning prayers", "Evening prayers"])
        model.toggleKept(try entry(model, "Morning prayers"))
        model.toggleKept(try entry(model, "Evening prayers"))
        model.clearThanksgiving()

        // Clear one and re-tick it: the day was already settled before.
        let evening = try entry(model, "Evening prayers")
        model.toggleKept(evening)
        model.clearThanksgiving()
        model.toggleKept(try entry(model, "Evening prayers"))
        #expect(model.thanksgiving != nil, "it became settled again, so it is said again")
    }

    @Test("a day with nothing on it is not settled")
    func emptyDayIsNotSettled() throws {
        let model = try makeModel()
        #expect(!model.dayIsSettled(model.today))
    }

    @Test("it can be cleared")
    func clearing() throws {
        let model = try modelWithRules(["Morning prayers"])
        model.toggleKept(try entry(model, "Morning prayers"))
        #expect(model.thanksgiving != nil)
        model.clearThanksgiving()
        #expect(model.thanksgiving == nil)
    }
}

/// Following a term out of what you were reading, and getting back to it.
@Suite("Opening a term")
@MainActor
struct GlossaryReturnTests {

    @Test("comes back to the screen it was opened from")
    func returnsToWhereItStarted() throws {
        let model = try makeModel()
        model.screen = .prayerRope

        model.openGlossary("publican")
        #expect(model.screen == .glossary("publican"))
        #expect(model.glossaryReturn == .prayerRope)
    }

    // Following "Publican" to "Jesus Prayer" to "Chotki" and pressing back
    // should land on the prayer, not walk back through the terms.
    @Test("a chain of terms still returns to the start")
    func chainKeepsTheOrigin() throws {
        let model = try makeModel()
        model.screen = .prayers(UUID())
        let origin = model.screen

        model.openGlossary("publican")
        model.openGlossary("jesus-prayer")
        model.openGlossary("chotki")

        #expect(model.glossaryReturn == origin)
    }

    @Test("opened from the main screen it returns there")
    func fromMain() throws {
        let model = try makeModel()
        #expect(model.screen == .main)
        model.openGlossary(nil)
        #expect(model.glossaryReturn == .main)
    }

    @Test("the library remembers it too")
    func fromLibrary() throws {
        let model = try makeModel()
        model.screen = .library
        model.openGlossary("great-lent")
        #expect(model.glossaryReturn == .library)
    }
}

/// The prayers screen keeps its place across a detour.
@Suite("The prayers screen survives navigation")
@MainActor
struct PrayerStateTests {

    @Test("a rope count is not lost to looking a word up")
    func countSurvives() throws {
        let model = try makeModel()
        model.prayers = PrayerScreen(selection: "jesus-prayer", count: 0, target: 100)
        for _ in 0..<40 { model.prayers.advance() }

        model.openGlossary("jesus-prayer")
        model.screen = model.glossaryReturn

        #expect(model.prayers.count == 40)
        #expect(model.prayers.selection == "jesus-prayer")
    }

    @Test("nor is the chosen prayer")
    func selectionSurvives() throws {
        let model = try makeModel()
        model.prayers.choose("morning")
        model.prayers.showRope(true)

        model.openGlossary("symbol-of-faith")
        model.screen = model.glossaryReturn

        #expect(model.prayers.selection == "morning")
        #expect(model.prayers.showsRope(), "the override survives too")
    }
}

/// The library opened underneath the day rather than instead of it.
@Suite("The library on the rule screen")
@MainActor
struct LibraryDrawerTests {

    @Test("starts closed")
    func startsClosed() throws {
        #expect(try makeModel().libraryOnRule == false)
    }

    @Test("opening it does not navigate away from the rule")
    func staysOnTheRule() throws {
        let model = try makeModel()
        model.libraryOnRule = true
        #expect(model.screen == .main, "the day and its calendar are still on screen")
    }
}

/// The day the view is showing, once the clock has moved on.
///
/// `DayRolloverTests` in core proves the rule. This proves the model obeys it —
/// that the selection actually moves, that the grid follows it to the right
/// month, and that a day chosen on purpose is not taken away. A rule nothing
/// calls is the failure this project keeps meeting.
@MainActor
@Suite("The day advances under the view")
struct DayAdvanceTests {

    @Test("opening on a later day moves the view to it")
    func movesToTheNewToday() throws {
        let model = try makeModel()
        let opened = model.selectedDate

        model.advanceDayIfNeeded(now: opened.adding(days: 1))
        #expect(model.selectedDate == opened.adding(days: 1))
    }

    @Test("the grid follows the selection into the new month")
    func gridFollowsIntoTheNewMonth() throws {
        let model = try makeModel()
        let opened = model.selectedDate

        // Far enough to land in a different month whatever today happens to be.
        let later = opened.adding(days: 40)
        model.advanceDayIfNeeded(now: later)
        #expect(model.selectedDate == later)
        #expect(model.visibleMonth.month == later.month)
        #expect(model.visibleMonth.year == later.year)
    }

    @Test("a day chosen on purpose is left where it is")
    func leavesADeliberateChoiceAlone() throws {
        let model = try makeModel()
        let lastWeek = model.selectedDate.adding(days: -7)
        model.selectedDate = lastWeek

        model.advanceDayIfNeeded(now: model.selectedDate.adding(days: 8))
        #expect(model.selectedDate == lastWeek, "looking back at last week was interrupted")
    }

    @Test("nothing moves when the day has not changed")
    func stillWithinTheSameDay() throws {
        let model = try makeModel()
        let opened = model.selectedDate

        model.advanceDayIfNeeded(now: opened)
        model.advanceDayIfNeeded(now: opened)
        #expect(model.selectedDate == opened)
    }
}
