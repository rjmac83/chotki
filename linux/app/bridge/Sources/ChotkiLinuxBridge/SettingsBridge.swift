import ChotkiCore
import Foundation

// Settings the Mac stores, plus the Linux welcome and reduced motion.
// Core decides the church, the calendar, and the welcome words. This file
// only carries them to the window and writes the record.

let linuxAlphaVersion = "Linux alpha 0.1.0~alpha1"

/// The directory that holds chotki.sqlite. Set once, when the helper opens.
/// The helper handles one record on one thread.
nonisolated(unsafe) var recordDirectory: URL?

struct SettingsOption: Encodable {
    var value: String
    var label: String
}

struct WelcomeSpanPayload: Encodable {
    var text: String
    var url: String?
}

struct WelcomeParagraphPayload: Encodable {
    var aside: Bool
    var spans: [WelcomeSpanPayload]
}

struct SettingsPayload: Encodable {
    var needsWelcome: Bool
    var welcomeTitle: String
    var welcomeParagraphs: [WelcomeParagraphPayload]
    var churchPrompt: String
    var noChurch: String
    var beginLabel: String
    var churches: [String]
    var displayName: String
    var spiritualFatherName: String
    var church: String
    /// The jurisdiction actually followed. The window does not show this when
    /// no church was named, so the OCA is not presented as their affiliation.
    var followed: String
    var reckoning: String
    var reckonings: [SettingsOption]
    var calendarNote: String?
    var akathistNote: String?
    var practiceNotes: [String]
    var fasting: String
    var feasts: String
    var observances: [SettingsOption]
    var showOldStyleDates: Bool
    var oldStyleHelp: String
    var clock: String
    var clocks: [SettingsOption]
    var notifications: Bool
    var notificationHelp: String
    var lead: String
    var leads: [SettingsOption]
    var chime: Bool
    var tick: Bool
    var tickHelp: String
    var showFigure: Bool
    var figureHelp: String
    var reducedMotion: Bool
    var launchAtLogin: Bool
    var backupDirectory: String
    var backupHelp: String
    var version: String
    var aboutURL: String
    var privacyURL: String
    var notice: String?
}

private func motionFile() -> URL? {
    recordDirectory?.appendingPathComponent("reduced-motion")
}

func readReducedMotion() -> Bool {
    guard let url = motionFile(), let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
    return text.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
}

private func writeReducedMotion(_ value: Bool) throws {
    guard let url = motionFile() else { return }
    try (value ? "1\n" : "0\n").write(to: url, atomically: true, encoding: .utf8)
}

func backupDirectoryURL() -> URL? {
    recordDirectory?.appendingPathComponent("backups", isDirectory: true)
}

/// One dated copy a day, beside the database. An empty record is not copied.
/// Review mode does not call this.
func writeDailyBackup(_ store: SQLiteStore) {
    guard let directory = backupDirectoryURL() else { return }
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard try !store.rules(includeArchived: true).isEmpty else { return }
        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withFullDate]
        let url = directory.appendingPathComponent("chotki-\(stamp.string(from: Date())).json")
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try store.exportJSON().write(to: url)
        let existing = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in existing.dropFirst(10) {
            try? FileManager.default.removeItem(at: old)
        }
    } catch {
        // A failed backup must never stop the record opening.
    }
}

func needsWelcome(_ settings: AppSettings, store: SQLiteStore) throws -> Bool {
    if settings.hasCompletedFirstRun { return false }
    return try store.rules(includeArchived: true).isEmpty
}

func settingsPayload(_ settings: AppSettings, store: SQLiteStore, notice: String? = nil) throws -> SettingsPayload {
    let observances = [
        SettingsOption(value: Observance.hidden.rawValue, label: "Hidden"),
        SettingsOption(value: Observance.shown.rawValue, label: "Shown"),
        SettingsOption(value: Observance.observed.rawValue, label: "Observed"),
    ]
    return SettingsPayload(
        needsWelcome: try needsWelcome(settings, store: store),
        welcomeTitle: Welcome.title,
        welcomeParagraphs: Welcome.paragraphs.map { paragraph in
            WelcomeParagraphPayload(
                aside: paragraph.isAside,
                spans: paragraph.spans.map { WelcomeSpanPayload(text: $0.text, url: $0.url) }
            )
        },
        churchPrompt: Welcome.churchPrompt,
        noChurch: Welcome.noChurchAffiliation,
        beginLabel: Welcome.beginLabel,
        churches: Jurisdiction.known.map(\.name),
        displayName: settings.displayName,
        spiritualFatherName: settings.spiritualFatherName,
        church: settings.namedChurch ?? "",
        followed: settings.jurisdiction.name,
        reckoning: settings.jurisdiction.reckoning.rawValue,
        reckonings: Reckoning.allCases.map {
            SettingsOption(value: $0.rawValue, label: $0.displayName)
        },
        calendarNote: settings.calendarDifferenceNote,
        akathistNote: Akathist.fallbackNote(for: settings.jurisdiction.tradition),
        practiceNotes: settings.jurisdiction.practice.notes,
        fasting: settings.observances.fasting.rawValue,
        feasts: settings.observances.feasts.rawValue,
        observances: observances,
        showOldStyleDates: settings.showOldStyleDates,
        oldStyleHelp: "Shows the Julian date alongside the civil one.",
        clock: settings.clockStyle.rawValue,
        clocks: ClockStyle.allCases.map {
            SettingsOption(value: $0.rawValue, label: $0.displayName)
        },
        notifications: settings.reminders.notificationsEnabled,
        notificationHelp: "Turning these off silences the app. It does not change what is due, or how anything is counted.",
        lead: String(settings.reminders.defaultLead.rawValue),
        leads: ReminderLead.choices.map {
            SettingsOption(value: String($0.rawValue), label: $0.label)
        },
        chime: settings.chimeOnCompletion,
        tick: settings.tickEachKnot,
        tickHelp: "A soft click confirms a press landed, for praying with your eyes closed.",
        showFigure: settings.showConsistencyNumber,
        figureHelp: "With this off, progress is reported in words only.",
        reducedMotion: readReducedMotion(),
        launchAtLogin: settings.launchAtLogin,
        backupDirectory: backupDirectoryURL()?.path ?? "",
        backupHelp: "A copy is also written automatically each day, in the backups folder beside your record. Restoring merges into what is already here; nothing is removed.",
        version: linuxAlphaVersion,
        aboutURL: "https://chotki.app/about",
        privacyURL: "https://chotki.app/privacy",
        notice: notice
    )
}

private func absoluteBackupPath(_ raw: String?) throws -> URL {
    guard let raw, raw.hasPrefix("/") else { throw BridgeError.backupPath }
    return URL(fileURLWithPath: raw)
}

/// `$XDG_CONFIG_HOME/autostart` when that variable is absolute. A relative
/// value is refused, the same way a relative review directory is. Otherwise
/// the file is `~/.config/autostart/org.chotki.Chotki.desktop`.
func autostartFileURL() -> URL? {
    let proposed = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"] ?? ""
    if !proposed.isEmpty && !proposed.hasPrefix("/") { return nil }
    let base = proposed.hasPrefix("/")
        ? URL(fileURLWithPath: proposed, isDirectory: true)
        : FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
    return base.appendingPathComponent("autostart/org.chotki.Chotki.desktop")
}

func desktopExecLine(_ executable: String) -> String? {
    guard executable.hasPrefix("/"), executable.count < 4000,
          !executable.contains("\n"), !executable.contains("\r"),
          !executable.contains("\"") else { return nil }
    if executable.contains(" ") || executable.contains("\t") {
        return "\"\(executable)\""
    }
    return executable
}

/// Review mode does not touch the person's autostart directory. Turning the
/// switch off removes the file. Turning it on writes it only when the window
/// has sent an absolute path.
func syncLaunchAtLogin(enabled: Bool, executable: String?, review: Bool) throws {
    if review { return }
    guard let url = autostartFileURL() else { return }
    if !enabled {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        return
    }
    guard let executable, let exec = desktopExecLine(executable) else { return }
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    let text = [
        "[Desktop Entry]",
        "Type=Application",
        "Name=Chotki",
        "Exec=\(exec)",
        "Icon=org.chotki.Chotki",
        "X-GNOME-Autostart-enabled=true",
        "",
    ].joined(separator: "\n")
    try text.write(to: url, atomically: true, encoding: .utf8)
}

func performSettings(_ request: BridgeRequest, store: SQLiteStore,
                     on date: CalendarDate, weekCenter: CalendarDate, review: Bool) throws {
    switch request.op {
    case "syncAutostart":
        if !review {
            let settings = try store.loadSettings() ?? .default
            try syncLaunchAtLogin(
                enabled: settings.launchAtLogin, executable: request.executable, review: false
            )
        }
        respond(BridgeSuccess(v: bridgeProtocolVersion, id: request.id))

    case "settings":
        let settings = try store.loadSettings() ?? .default
        respond(BridgeSuccess(
            v: bridgeProtocolVersion, id: request.id,
            settings: try settingsPayload(settings, store: store)
        ))

    case "exportBackup":
        let url = try absoluteBackupPath(request.path)
        do {
            try store.exportJSON().write(to: url)
        } catch {
            throw BridgeError.backupWrite
        }
        let settings = try store.loadSettings() ?? .default
        respond(BridgeSuccess(
            v: bridgeProtocolVersion, id: request.id,
            settings: try settingsPayload(
                settings, store: store, notice: "Backup written to \(url.lastPathComponent)."
            )
        ))

    case "importBackup":
        let url = try absoluteBackupPath(request.path)
        let data: Data
        do {
            data = try Data(contentsOf: url)
            try store.importJSON(data)
        } catch {
            throw BridgeError.backupRead
        }
        var success = try homeSnapshot(store: store, on: date, weekCenter: weekCenter)
            .success(id: request.id, today: CalendarDate(Date(), in: .current).iso)
        let settings = try store.loadSettings() ?? .default
        success.settings = try settingsPayload(
            settings, store: store, notice: "Restored from \(url.lastPathComponent)."
        )
        respond(success)

    case "saveSettings":
        var updated = try store.loadSettings() ?? .default
        let formerFather = updated.spiritualFatherName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name = request.name {
            updated.displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let father = request.father {
            let next = father.trimmingCharacters(in: .whitespacesAndNewlines)
            if !formerFather.isEmpty && formerFather != next {
                try preserveFatherName(formerFather, store: store)
            }
            updated.spiritualFatherName = next
        }
        if let church = request.church {
            let trimmed = church.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !Jurisdiction.known.contains(where: { $0.name == trimmed }) {
                throw BridgeError.invalidRequest
            }
            updated.chooseChurch(named: trimmed.isEmpty ? nil : trimmed)
        }
        if let raw = request.reckoning {
            guard let reckoning = Reckoning(rawValue: raw) else { throw BridgeError.invalidRequest }
            updated.jurisdiction.reckoning = reckoning
        }
        if let raw = request.fasting {
            guard let value = Observance(rawValue: raw) else { throw BridgeError.invalidRequest }
            updated.observances.fasting = value
        }
        if let raw = request.feasts {
            guard let value = Observance(rawValue: raw) else { throw BridgeError.invalidRequest }
            updated.observances.feasts = value
        }
        if let oldStyle = request.showOldStyleDates { updated.showOldStyleDates = oldStyle }
        if let raw = request.clock {
            guard let style = ClockStyle(rawValue: raw) else { throw BridgeError.invalidRequest }
            updated.clockStyle = style
        }
        if let enabled = request.notifications { updated.reminders.notificationsEnabled = enabled }
        if let lead = request.lead {
            guard let value = ReminderLead(rawValue: lead), ReminderLead.choices.contains(value) else {
                throw BridgeError.invalidRequest
            }
            updated.reminders.defaultLead = value
        }
        if let chime = request.chime { updated.chimeOnCompletion = chime }
        if let tick = request.tick { updated.tickEachKnot = tick }
        if let figure = request.showFigure { updated.showConsistencyNumber = figure }
        if let motion = request.motion { try writeReducedMotion(motion) }
        if let enabled = request.launchAtLogin { updated.launchAtLogin = enabled }
        if request.welcome == true { updated.hasCompletedFirstRun = true }
        let today = CalendarDate(Date(), in: .current)
        if updated.hasCompletedFirstRun && updated.firstRunOn == nil { updated.firstRunOn = today }
        let stored = try store.loadSettings() ?? .default
        let reckoningChanged = updated.jurisdiction.reckoning != stored.jurisdiction.reckoning
        let jurisdictionChanged = updated.jurisdiction != stored.jurisdiction
        if reckoningChanged { updated.reckoningChangedOn = today }
        try store.saveSettings(updated)
        if request.launchAtLogin != nil {
            try syncLaunchAtLogin(
                enabled: updated.launchAtLogin, executable: request.executable, review: review
            )
        }
        if jurisdictionChanged {
            let liturgical = LiturgicalService(
                store: store, jurisdiction: updated.jurisdiction, networkPolicy: .never
            )
            try liturgical.setJurisdiction(updated.jurisdiction, around: today)
        }
        let notice = reckoningChanged
            ? "The calendar is now the \(updated.jurisdiction.reckoning.displayName). Fasts and feasts move by thirteen days from today. What you have already kept is untouched."
            : nil
        var success = try homeSnapshot(store: store, on: date, weekCenter: weekCenter)
            .success(id: request.id, today: today.iso)
        success.settings = try settingsPayload(updated, store: store, notice: notice)
        respond(success)

    default:
        throw BridgeError.unsupportedOperation(request.op)
    }
}
