import ChotkiCore
import Foundation

// The Linux UI owns desktop behavior. This process owns the existing Swift
// decisions and record. Requests and replies are the types in Protocol.swift.

private enum LaunchMode {
    case review
    case normal

    init?(_ argument: String) {
        switch argument {
        case "--review": self = .review
        case "--normal": self = .normal
        default: return nil
        }
    }

    var isReview: Bool { self == .review }
}

enum BridgeError: Error, CustomStringConvertible {
    case invalidRequest
    case incompatibleProtocol
    case unsupportedOperation(String)
    case reviewOnly
    case unknownRule
    case notAsked
    case invalidReviewDirectory
    case unknownPrayer
    case unnamedRule
    case unknownTerm
    case backupPath
    case backupRead
    case backupWrite

    var description: String {
        switch self {
        case .invalidRequest: "The request is incomplete or malformed."
        case .incompatibleProtocol: "The Linux interface and Swift helper use different protocol versions."
        case .unsupportedOperation(let name): "Unsupported operation: \(name)"
        case .reviewOnly: "This command is available only in the isolated review record."
        case .unknownRule: "That rule is not on the selected day."
        case .notAsked: "Nothing was asked on this day."
        case .invalidReviewDirectory: "The review record directory must be an absolute path."
        case .unknownPrayer: "That prayer is not in the book."
        case .unnamedRule: "Give the rule a name before saving."
        case .unknownTerm: "That term is not in the glossary."
        case .backupPath: "The backup path must be an absolute path."
        case .backupRead: "Could not read that backup."
        case .backupWrite: "Could not write that backup."
        }
    }
}

private func dataDirectory(for mode: LaunchMode) throws -> URL {
    let home = FileManager.default.homeDirectoryForCurrentUser
    if mode.isReview {
        // Tests set this so they do not write the human review record at the
        // fixed cache path. An unset variable keeps that path.
        let override = ProcessInfo.processInfo.environment["CHOTKI_LINUX_REVIEW_DIR"] ?? ""
        if !override.isEmpty {
            guard override.hasPrefix("/") else { throw BridgeError.invalidReviewDirectory }
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return home.appendingPathComponent(".cache/chotki-linux-review", isDirectory: true)
    }
    let proposed = ProcessInfo.processInfo.environment["XDG_DATA_HOME"] ?? ""
    let base = proposed.hasPrefix("/")
        ? URL(fileURLWithPath: proposed, isDirectory: true)
        : home.appendingPathComponent(".local/share", isDirectory: true)
    return base.appendingPathComponent("Chotki", isDirectory: true)
}

func respond<T: Encodable>(_ value: T) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let encoded = try? encoder.encode(value) else { return }
    var line = encoded
    line.append(0x0A)
    FileHandle.standardOutput.write(line)
}

private func fail(id: Int, _ error: Error) {
    respond(BridgeFailure(v: bridgeProtocolVersion, id: id, error: String(describing: error)))
}

private struct CardFace {
    var destination: String
    var selection: String?
    var band: Int?
    var action: String
    var back: String
}

/// The same choice the Mac makes when a card is opened. Fasting turns the card
/// over. A counted prayer opens the rope. A sequence opens that sequence.
private func cardFace(_ entry: DayEntry, summary: String, tradition: Tradition) -> CardFace {
    let rule = entry.rule
    var back = summary
    if let reason = entry.dispensation, !reason.isEmpty {
        back = "Not observed during \(reason)."
    } else if rule.isFastingRule, let slug = rule.glossarySlug,
              let term = Glossary.shared(for: tradition).entry(slug: slug) {
        back = term.short
    }
    if rule.isFastingRule {
        return CardFace(destination: "fast", selection: nil, band: nil, action: "Open", back: back)
    }
    if let id = rule.ropePrayerID {
        return CardFace(destination: "rope", selection: id, band: nil, action: "Go to the Rope", back: back)
    }
    if let id = rule.sequenceID {
        return CardFace(destination: "prayers", selection: id, band: nil, action: "Read the Prayers", back: back)
    }
    switch rule.reference {
    case .reading:
        let life = rule.title.lowercased().contains("life of the day")
        return CardFace(
            destination: "reading", selection: nil, band: ReadingOrder.band(ofTitle: rule.title),
            action: life ? "Read the Saint\u{2019}s Life" : "Read the Day\u{2019}s Readings", back: back
        )
    case .psalter:
        return CardFace(destination: "psalter", selection: nil, band: nil,
                        action: "Read Today\u{2019}s Kathisma", back: back)
    case .prayers:
        return CardFace(destination: "prayers", selection: rule.sequenceID, band: nil,
                        action: "Read the Prayers", back: back)
    default:
        return CardFace(destination: "editor", selection: nil, band: nil, action: "Open", back: back)
    }
}

func homeSnapshot(store: SQLiteStore, on selectedDate: CalendarDate,
                          weekCenter: CalendarDate) throws -> HomeSnapshot {
    let settings = try store.loadSettings() ?? .default
    let rules = try store.rules(includeArchived: false)
    let activations = try store.activations(ruleID: nil)
    let occurrences = try store.occurrences(ruleID: nil, from: selectedDate, through: selectedDate)
    let liturgical = LiturgicalService(store: store, jurisdiction: settings.jurisdiction,
                                      networkPolicy: .never)
    let practice = Practice(rules: rules, activations: activations,
                            occurrences: occurrences, settings: settings, liturgical: liturgical)
    let entries: [EntryPayload] = practice.entries(on: selectedDate).map { entry in
        let summary = RuleLibrary.shared.templates.first { $0.title == entry.rule.title }?.summary
            ?? entry.rule.note ?? "A rule of your own."
        let time = entry.rule.timeOfDay.map { Format.time($0, settings.clockStyle) }
        let face = cardFace(entry, summary: summary, tradition: settings.jurisdiction.tradition)
        return EntryPayload(
            id: entry.rule.id.uuidString, title: entry.rule.title,
            category: RuleCategory(rawValue: entry.rule.category ?? "")?.displayName ?? "Rule",
            summary: summary, time: time ?? "All Day", kept: entry.isKept,
            dispensed: entry.isDispensed, dispensation: entry.dispensation ?? "",
            stoodDown: entry.isStoodDown, destination: face.destination, selection: face.selection,
            band: face.band, action: face.action, back: face.back,
            glossarySlug: entry.rule.glossarySlug
        )
    }
    let weekStart = weekCenter.adding(days: -3)
    let weekEnd = weekCenter.adding(days: 3)
    let weekOccurrences = try store.occurrences(ruleID: nil, from: weekStart, through: weekEnd)
    let weekPractice = Practice(rules: rules, activations: activations,
                                occurrences: weekOccurrences, settings: settings,
                                liturgical: liturgical)
    let week: [WeekDayPayload] = (-3...3).map { offset in
        let date = weekCenter.adding(days: offset)
        let day = liturgical.cachedDay(for: date)
        let feast = settings.observances.feasts.isVisible && day?.isGreatFeast == true
        let fast = settings.observances.fasting.isVisible && day?.isFast == true
            && date.weekday != .sunday && !feast
        return WeekDayPayload(
            date: date.iso, day: date.day, weekday: date.weekday.rawValue,
            selected: date == selectedDate, fast: fast, feast: feast,
            settled: weekPractice.isSettled(on: date)
        )
    }
    let monthAnchor = CalendarDate(year: calendarView.visible.year, month: calendarView.visible.month, day: 1)
        ?? selectedDate
    let gridStart = monthAnchor.adding(days: 1 - monthAnchor.weekday.rawValue)
    let gridEnd = gridStart.adding(days: 41)
    let monthOccurrences = try store.occurrences(ruleID: nil, from: gridStart, through: gridEnd)
    let monthPractice = Practice(rules: rules, activations: activations,
                                 occurrences: monthOccurrences, settings: settings,
                                 liturgical: liturgical)
    let month: [WeekDayPayload] = (0..<42).map { offset in
        let date = gridStart.adding(days: offset)
        let day = liturgical.cachedDay(for: date)
        let feast = settings.observances.feasts.isVisible && day?.isGreatFeast == true
        let fast = settings.observances.fasting.isVisible && day?.isFast == true
            && date.weekday != .sunday && !feast
        return WeekDayPayload(
            date: date.iso, day: date.day, weekday: date.weekday.rawValue,
            selected: date == selectedDate, fast: fast, feast: feast,
            settled: monthPractice.isSettled(on: date),
            inMonth: date.year == monthAnchor.year && date.month == monthAnchor.month
        )
    }
    let saying = PatristicReadings.shared.reading(for: selectedDate)
    let liturgicalDay = liturgical.cachedDay(for: selectedDate)
    let today = CalendarDate(Date(), in: .current)
    let link = TodayLink.needed(selected: selectedDate, today: today,
                                visibleMonth: monthAnchor, monthOpen: calendarView.shown)
    return HomeSnapshot(
        selectedDate: selectedDate.iso, displayName: settings.displayName,
        hasCompletedFirstRun: settings.hasCompletedFirstRun,
        psalmOneVerses: Psalter.psalm(1)?.verses.count ?? 0, entries: entries, week: week,
        month: month, monthTitle: Format.monthAndYear(monthAnchor),
        dayTitle: liturgicalDay?.title ?? "", observedDate: liturgicalDay?.observedDate.iso ?? "",
        showOldStyleDates: settings.showOldStyleDates, sayingText: saying?.text ?? "",
        sayingAuthor: saying?.author ?? "", sayingSource: saying?.source ?? "",
        todayLink: link?.text,
        needsWelcome: try needsWelcome(settings, store: store),
        reducedMotion: readReducedMotion()
    )
}

struct CalendarViewState {
    var visible: CalendarDate
    var shown: Bool
}

nonisolated(unsafe) var calendarView = CalendarViewState(
    visible: CalendarDate(year: 2026, month: 1, day: 1)!, shown: false)
nonisolated(unsafe) var panSession: [String: Date] = [:]

private func panFile() -> URL? {
    recordDirectory?.appendingPathComponent("saying-pan")
}

/// The day's pan starts once. A later visit, in this process or the next,
/// continues from that instant. Review does not write the file.
private func panStart(identity: String, persist: Bool) -> Date {
    if let existing = panSession[identity] { return existing }
    if persist, let url = panFile(),
       let text = try? String(contentsOf: url, encoding: .utf8) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.count >= 2, lines[0] == identity, let seconds = Double(lines[1]) {
            let started = Date(timeIntervalSince1970: seconds)
            panSession[identity] = started
            return started
        }
    }
    let now = Date()
    panSession[identity] = now
    if persist, let url = panFile() {
        try? (identity + "\n" + String(now.timeIntervalSince1970))
            .write(to: url, atomically: true, encoding: .utf8)
    }
    return now
}

func dayPractice(_ store: SQLiteStore, on date: CalendarDate) throws -> Practice {
    let settings = try store.loadSettings() ?? .default
    let liturgical = LiturgicalService(store: store, jurisdiction: settings.jurisdiction,
                                      networkPolicy: .never)
    return Practice(
        rules: try store.rules(includeArchived: false),
        activations: try store.activations(ruleID: nil),
        occurrences: try store.occurrences(ruleID: nil, from: date, through: date),
        settings: settings, liturgical: liturgical
    )
}

private func reply(id: Int, snapshot: HomeSnapshot) throws {
    let today = CalendarDate(Date(), in: .current).iso
    respond(snapshot.success(id: id, today: today))
}

guard CommandLine.arguments.count == 2,
      let mode = LaunchMode(CommandLine.arguments[1]) else {
    FileHandle.standardError.write(Data("Usage: ChotkiLinuxBridge --review|--normal\n".utf8))
    exit(2)
}

do {
    let directory = try dataDirectory(for: mode)
    recordDirectory = directory
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let store = try SQLiteStore(path: directory.appendingPathComponent("chotki.sqlite").path)

    if mode.isReview {
        if try store.loadSettings() == nil {
            var sample = AppSettings.default
            sample.displayName = "Anna"
            sample.hasCompletedFirstRun = true
            try store.saveSettings(sample)
        }
        if try store.rules(includeArchived: false).isEmpty {
            let today = CalendarDate(Date(), in: .current)
            for title in ["Morning prayers", "The day's Gospel", "The day's Epistle",
                          "Evening prayers", "The Jesus Prayer", "The life of the day's saint",
                          "A kathisma of the Psalter", "The Wednesday and Friday fast"] {
                guard let template = RuleLibrary.shared.templates.first(where: { $0.title == title }) else {
                    continue
                }
                let rule = template.makeRule(source: "the library")
                try store.save(rule)
                try store.save(Activation(ruleID: rule.id, from: today.adding(days: -40)))
                if title == "Morning prayers" {
                    try store.save(Occurrence(
                        ruleID: rule.id, date: today, status: .completed, completedAt: Date()
                    ))
                }
            }
        }
    } else {
        writeDailyBackup(store)
    }

    var selectedDate = CalendarDate(Date(), in: .current)
    var weekCenter = selectedDate
    calendarView.visible = selectedDate
    calendarView.shown = false
    panSession.removeAll()
    // The rope count lives for this process, as it does on the Mac. Leaving the
    // page and coming back reads it again. A new process starts at the beginning.
    var prayers = PrayerSession()
    var reading = ReadingSession()
    var psalter = PsalterSession()
    var library = LibrarySession()
    // One ticker for the process. A new one on each request would forget what
    // had already been shown, and the first tick would wipe a snooze.
    var ticker = ReminderTicker()

    while let line = readLine() {
        let decoded = try? JSONDecoder().decode(BridgeRequest.self, from: Data(line.utf8))
        let id = decoded?.id ?? 0
        do {
            guard let request = decoded else { throw BridgeError.invalidRequest }
            guard request.v == bridgeProtocolVersion else { throw BridgeError.incompatibleProtocol }

            switch request.op {
            case "hello":
                respond(BridgeSuccess(v: bridgeProtocolVersion, id: id,
                                      mode: mode.isReview ? "review" : "normal"))

            case "snapshot":
                try reply(id: id, snapshot: homeSnapshot(store: store, on: selectedDate,
                                                         weekCenter: weekCenter))

            case "selectDate":
                guard let raw = request.date, let date = CalendarDate(iso: raw) else {
                    throw BridgeError.invalidRequest
                }
                selectedDate = date
                weekCenter = date
                calendarView.visible = date
                reading.applyFocus()
                psalter.clear()
                try reply(id: id, snapshot: homeSnapshot(store: store, on: selectedDate,
                                                         weekCenter: weekCenter))

            case "shiftWeek":
                guard let direction = request.direction, direction == -1 || direction == 1 else {
                    throw BridgeError.invalidRequest
                }
                weekCenter = weekCenter.adding(days: direction * 7)
                try reply(id: id, snapshot: homeSnapshot(store: store, on: selectedDate,
                                                         weekCenter: weekCenter))

            case "shiftMonth":
                guard let direction = request.direction, direction == -1 || direction == 1 else {
                    throw BridgeError.invalidRequest
                }
                let first = CalendarDate(year: calendarView.visible.year,
                                         month: calendarView.visible.month, day: 1) ?? selectedDate
                let stepped = direction < 0
                    ? first.adding(days: -1)
                    : first.adding(days: first.lastDayOfMonth)
                calendarView.visible = CalendarDate(year: stepped.year, month: stepped.month, day: 1) ?? stepped
                try reply(id: id, snapshot: homeSnapshot(store: store, on: selectedDate,
                                                         weekCenter: weekCenter))

            case "setMonthShown":
                calendarView.shown = request.shown == true
                try reply(id: id, snapshot: homeSnapshot(store: store, on: selectedDate,
                                                         weekCenter: weekCenter))

            case "noteSayingPan":
                guard let name = request.name, !name.isEmpty, name.count < 240,
                      !name.contains("\n"), !name.contains("/") || name.hasPrefix("sayings/") else {
                    throw BridgeError.invalidRequest
                }
                let today = CalendarDate(Date(), in: .current)
                let identity = "pan3-\(selectedDate.iso)-\(name)"
                let started = panStart(identity: identity, persist: !mode.isReview && selectedDate == today)
                var noted = try homeSnapshot(store: store, on: selectedDate, weekCenter: weekCenter)
                    .success(id: id, today: today.iso)
                noted.sayingPanStart = started.timeIntervalSince1970
                respond(noted)

            case "toggleKept", "markKeptLate", "standDownDay":
                guard let raw = request.ruleID, let ruleID = UUID(uuidString: raw) else {
                    throw BridgeError.invalidRequest
                }
                let practice = try dayPractice(store, on: selectedDate)
                guard let entry = practice.entries(on: selectedDate).first(where: { $0.rule.id == ruleID }) else {
                    throw BridgeError.unknownRule
                }
                if entry.isDispensed { throw BridgeError.notAsked }
                let wasSettled = practice.isSettled(on: selectedDate)
                var markedKept = false
                switch request.op {
                case "toggleKept":
                    if entry.isKept {
                        try store.removeOccurrence(ruleID: ruleID, date: selectedDate)
                    } else {
                        try store.save(Occurrence(
                            ruleID: ruleID, date: selectedDate, status: .completed, completedAt: Date()
                        ))
                        markedKept = true
                    }
                case "markKeptLate":
                    try store.save(Occurrence(
                        ruleID: ruleID, date: selectedDate, status: .completedLate, completedAt: Date()
                    ))
                case "standDownDay":
                    try store.save(Occurrence(
                        ruleID: ruleID, date: selectedDate, status: .skipped, completedAt: nil
                    ))
                default:
                    break
                }
                let snapshot = try homeSnapshot(store: store, on: selectedDate, weekCenter: weekCenter)
                var success = snapshot.success(id: id, today: CalendarDate(Date(), in: .current).iso)
                let settledNow = snapshot.week.first { $0.date == selectedDate.iso }?.settled ?? false
                if markedKept, !wasSettled, settledNow {
                    success.thanksgiving = "Glory to God for all things."
                }
                respond(success)

            case "setReviewName":
                guard mode.isReview else { throw BridgeError.reviewOnly }
                guard let name = request.name, name.count <= 80 else { throw BridgeError.invalidRequest }
                var settings = try store.loadSettings() ?? .default
                settings.displayName = name
                try store.saveSettings(settings)
                respond(BridgeSuccess(
                    v: bridgeProtocolVersion, id: id,
                    displayName: try store.loadSettings()?.displayName ?? ""
                ))

            case "prayer", "advancePrayer", "choosePrayer", "aimPrayer", "showRope", "startAgain":
                try performPrayer(request, store: store, session: &prayers)

            case "reading", "openReading", "toggleReading", "finishReading":
                try performReading(request, store: store, on: selectedDate,
                                   weekCenter: weekCenter, session: &reading)

            case "psalter", "openKathisma", "finishPsalter":
                try performPsalter(request, store: store, on: selectedDate,
                                   weekCenter: weekCenter, session: &psalter)

            case "library", "prepareTemplate", "openEditor", "acknowledgeCaution",
                 "saveRule", "pauseRule", "resumeRule", "removeRule", "takeUp",
                 "setAside", "setSpiritualFather":
                try performLibrary(request, store: store, on: selectedDate,
                                   weekCenter: weekCenter, session: &library)

            case "progress":
                try performProgress(request, store: store)

            case "glossary":
                try performGlossary(request, store: store)

            case "settings", "saveSettings", "exportBackup", "importBackup", "syncAutostart":
                try performSettings(request, store: store, on: selectedDate, weekCenter: weekCenter,
                                    review: mode.isReview)

            case "tickReminders":
                try performTickReminders(id: id, store: store, review: mode.isReview, ticker: &ticker)

            case "notificationAction":
                try performNotificationAction(
                    request, store: store, on: selectedDate, weekCenter: weekCenter, ticker: &ticker
                )

            case "opening":
                respond(openingSuccess(id: id))

            case "tones":
                respond(try tonesSuccess(id: id, session: &prayers))

            default:
                throw BridgeError.unsupportedOperation(request.op)
            }
        } catch {
            fail(id: id, error)
        }
    }
} catch {
    fail(id: 0, error)
    exit(1)
}
