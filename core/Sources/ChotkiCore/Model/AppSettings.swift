import Foundation

/// Whether a person has named a church.
///
/// Written on every new save. A missing key on an older record is not this:
/// it means the stored jurisdiction is the church they already chose.
/// `declared` with no name means they said they have no church yet, and the
/// app follows the OCA without showing that name.
public struct Affiliation: Sendable, Hashable, Codable {
    public var name: String?
    public var declared: Bool

    public init(name: String? = nil, declared: Bool = true) {
        self.name = name
        self.declared = declared
    }
}

/// Everything the user can change, in one Codable value.
///
/// Lives in core so the settings a person has chosen move with their data
/// rather than being tied to one platform's preferences system.
public struct AppSettings: Sendable, Hashable, Codable {
    public var displayName: String = ""
    public var spiritualFatherName: String = ""
    public var firstRunOn: CalendarDate? = nil
    public var spiritualFatherDeferredOn: CalendarDate? = nil
    public var customCautionDismissed: Bool = false

    public var givenByPriestPhrase: String? {
        let name = spiritualFatherName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : "Given to me by \(name)"
    }

    public func shouldAskForSpiritualFather(on today: CalendarDate) -> Bool {
        guard hasCompletedFirstRun, givenByPriestPhrase == nil,
              let anchor = spiritualFatherDeferredOn ?? firstRunOn else { return false }
        return today >= anchor.adding(days: 30)
    }

    public var jurisdiction: Jurisdiction
    /// Nil only on a record saved before this existed. See `namedChurch`.
    public var affiliation: Affiliation?
    public var observances: ObservanceSettings
    public var reminders: ReminderPolicy
    /// Show the Julian date alongside the civil one — useful on the Old
    /// Calendar, where a parish bulletin and a wall calendar disagree.
    public var showOldStyleDates: Bool
    /// The consistency figure can be hidden entirely, leaving only the prose.
    public var showConsistencyNumber: Bool
    public var launchAtLogin: Bool
    /// Show a Dock icon and a full window as well as the menu bar item.
    /// The menu bar item is always present; this only adds the rest.
    public var showInDock: Bool
    /// The chime when a knot of the prayer rope is complete.
    public var chimeOnCompletion: Bool
    /// A soft click as each knot passes, so a press is confirmed with your eyes
    /// closed.
    public var tickEachKnot: Bool
    /// Cleared once the first rules have been taken on.
    public var hasCompletedFirstRun: Bool
    /// Whether times read as 06:30 or as 6:30 AM.
    public var clockStyle: ClockStyle
    /// The day the calendar was last changed, if it ever was.
    ///
    /// Liturgical rules are the only ones whose due days come from outside the
    /// app, and changing the reckoning moves them by thirteen days. Without
    /// this, a fast kept faithfully under one calendar is re-scored against the
    /// other and reads as a fortnight of failures — which the app must never be
    /// able to say. See `ScoringEngine.report`.
    public var reckoningChangedOn: CalendarDate?
    /// The rules the person has paused, on purpose.
    ///
    /// A rule with no open stretch is not necessarily paused: editing one from
    /// today on ends the old rule and starts a new one, and removing the rest of
    /// a series closes it too. Neither is something the person set aside, and
    /// neither should sit on the day greyed as "Paused". Only the act of pausing
    /// writes here, and resuming or taking the rule back up clears it.
    ///
    /// Settings rather than a column on the rule: every key here is optional, so
    /// a record or a backup written before this existed reads as having none,
    /// and no database migration is needed.
    public var pausedRuleIDs: [UUID] = []

    public init(
        jurisdiction: Jurisdiction = .default,
        observances: ObservanceSettings = .default,
        reminders: ReminderPolicy = .default,
        showOldStyleDates: Bool = true,
        showConsistencyNumber: Bool = true,
        launchAtLogin: Bool = false,
        showInDock: Bool = true,
        chimeOnCompletion: Bool = true,
        tickEachKnot: Bool = true,
        hasCompletedFirstRun: Bool = false,
        clockStyle: ClockStyle = .twentyFourHour,
        reckoningChangedOn: CalendarDate? = nil,
        affiliation: Affiliation? = Affiliation(declared: true)
    ) {
        self.jurisdiction = jurisdiction
        self.affiliation = affiliation
        self.observances = observances
        self.reminders = reminders
        self.showOldStyleDates = showOldStyleDates
        self.showConsistencyNumber = showConsistencyNumber
        self.launchAtLogin = launchAtLogin
        self.showInDock = showInDock
        self.chimeOnCompletion = chimeOnCompletion
        self.tickEachKnot = tickEachKnot
        self.hasCompletedFirstRun = hasCompletedFirstRun
        self.clockStyle = clockStyle
        self.reckoningChangedOn = reckoningChangedOn
    }

    private enum CodingKeys: String, CodingKey {
        case displayName, spiritualFatherName, firstRunOn, spiritualFatherDeferredOn
        case customCautionDismissed, jurisdiction, affiliation, observances, reminders
        case showOldStyleDates, showConsistencyNumber, launchAtLogin, showInDock
        case chimeOnCompletion, tickEachKnot, hasCompletedFirstRun, clockStyle
        case reckoningChangedOn, pausedRuleIDs
    }

    /// Every key optional, every absence a default.
    ///
    /// Synthesised decoding throws when a key is missing, so adding a setting
    /// would make every record written before it unreadable — and this app has
    /// already lost a person's settings once, which is how fasting rules
    /// silently stopped appearing. A record that predates a setting is not
    /// corrupt; it simply has not got one yet.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = AppSettings.default
        func value<T: Decodable>(_ key: CodingKeys, _ default: T) throws -> T {
            try container.decodeIfPresent(T.self, forKey: key) ?? `default`
        }
        displayName = try value(.displayName, "")
        spiritualFatherName = try value(.spiritualFatherName, "")
        firstRunOn = try container.decodeIfPresent(CalendarDate.self, forKey: .firstRunOn)
        spiritualFatherDeferredOn = try container.decodeIfPresent(CalendarDate.self, forKey: .spiritualFatherDeferredOn)
        customCautionDismissed = try value(.customCautionDismissed, false)
        jurisdiction = try value(.jurisdiction, fallback.jurisdiction)
        // A stored church with no affiliation key is that church. A record
        // that names neither is a new one: no church, following the OCA.
        // An explicit null is the same as a missing key beside a church,
        // because a save of an older record writes null rather than omitting it.
        if container.contains(.affiliation) {
            affiliation = try container.decodeIfPresent(Affiliation.self, forKey: .affiliation)
        } else if container.contains(.jurisdiction) {
            affiliation = nil
        } else {
            affiliation = Affiliation(declared: true)
        }
        observances = try value(.observances, fallback.observances)
        reminders = try value(.reminders, fallback.reminders)
        showOldStyleDates = try value(.showOldStyleDates, fallback.showOldStyleDates)
        showConsistencyNumber = try value(.showConsistencyNumber, fallback.showConsistencyNumber)
        launchAtLogin = try value(.launchAtLogin, fallback.launchAtLogin)
        showInDock = try value(.showInDock, fallback.showInDock)
        chimeOnCompletion = try value(.chimeOnCompletion, fallback.chimeOnCompletion)
        tickEachKnot = try value(.tickEachKnot, fallback.tickEachKnot)
        hasCompletedFirstRun = try value(.hasCompletedFirstRun, fallback.hasCompletedFirstRun)
        clockStyle = try value(.clockStyle, fallback.clockStyle)
        reckoningChangedOn = try container.decodeIfPresent(
            CalendarDate.self, forKey: .reckoningChangedOn
        )
        pausedRuleIDs = try value(.pausedRuleIDs, [])
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(spiritualFatherName, forKey: .spiritualFatherName)
        try container.encodeIfPresent(firstRunOn, forKey: .firstRunOn)
        try container.encodeIfPresent(spiritualFatherDeferredOn, forKey: .spiritualFatherDeferredOn)
        try container.encode(customCautionDismissed, forKey: .customCautionDismissed)
        try container.encode(jurisdiction, forKey: .jurisdiction)
        try container.encodeIfPresent(affiliation, forKey: .affiliation)
        try container.encode(observances, forKey: .observances)
        try container.encode(reminders, forKey: .reminders)
        try container.encode(showOldStyleDates, forKey: .showOldStyleDates)
        try container.encode(showConsistencyNumber, forKey: .showConsistencyNumber)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encode(showInDock, forKey: .showInDock)
        try container.encode(chimeOnCompletion, forKey: .chimeOnCompletion)
        try container.encode(tickEachKnot, forKey: .tickEachKnot)
        try container.encode(hasCompletedFirstRun, forKey: .hasCompletedFirstRun)
        try container.encode(clockStyle, forKey: .clockStyle)
        try container.encodeIfPresent(reckoningChangedOn, forKey: .reckoningChangedOn)
        // Written only when there is something to say, so a record that has
        // never paused a rule is byte-for-byte what it was before.
        if !pausedRuleIDs.isEmpty {
            try container.encode(pausedRuleIDs, forKey: .pausedRuleIDs)
        }
    }

    /// The church to show. Nil when they have said they have none.
    ///
    /// An older record with a jurisdiction and no affiliation still shows
    /// that church. The OCA name used for the unnamed default is not shown.
    public var namedChurch: String? {
        guard let affiliation else { return jurisdiction.name }
        let trimmed = affiliation.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if affiliation.declared && trimmed.isEmpty { return nil }
        return trimmed.isEmpty ? jurisdiction.name : trimmed
    }

    /// Name a church, or pass nil or blank to say there is none.
    ///
    /// None follows the OCA and shows no church. A known name replaces the
    /// jurisdiction with the one the app ships for that church.
    public mutating func chooseChurch(named name: String?) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            affiliation = Affiliation(declared: true)
            jurisdiction = .default
            return
        }
        guard let chosen = Jurisdiction.known.first(where: { $0.name == trimmed }) else { return }
        affiliation = Affiliation(name: chosen.name, declared: true)
        jurisdiction = chosen
    }

    /// The "usually keeps" sentence, or nil when no church was named.
    /// Naming the OCA here would show an affiliation they did not choose.
    public var calendarDifferenceNote: String? {
        guard namedChurch != nil,
              jurisdiction.reckoningDiffersFromJurisdiction,
              let usual = jurisdiction.asShipped
        else { return nil }
        return "\(usual.name) usually keeps the \(usual.reckoning.displayName)."
    }

    public static let `default` = AppSettings()
}
