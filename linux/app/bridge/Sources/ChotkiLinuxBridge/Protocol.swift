import Foundation

// Newline-framed JSON, version 1. Optional keys are omitted, so an older
// reader that looks up keys still sees the same shape. Version stays 1 until
// a key changes meaning.
let bridgeProtocolVersion = 1

struct BridgeRequest: Decodable {
    var v: Int
    var id: Int
    var op: String
    var date: String?
    var ruleID: String?
    var direction: Int?
    var name: String?
    /// A prayer id. Empty or null on `choosePrayer` is the rope alone.
    var selection: String?
    /// One of `PrayerScreen.targets` for `aimPrayer`.
    var target: Int?
    /// The reader's own decision for `showRope`.
    var shown: Bool?
    /// Square the rope layout is computed in, in points.
    var diameter: Double?
    /// Unix seconds for `advancePrayer`. Omitted, the helper uses the clock.
    var now: Double?
    /// A Reading section. Null on `openReading` is the sidebar, every section closed.
    var band: Int?
    /// A kathisma number, 1 through 20, for `openKathisma`.
    var kathisma: Int?
    /// True when `openKathisma` is the reader's own choice rather than the day's appointment.
    var manual: Bool?
    /// A library template id for `prepareTemplate`.
    var template: String?
    /// The library search. Empty shows every template.
    var query: String?
    /// Editor fields. Omitted keys keep what the draft already has.
    var title: String?
    var note: String?
    var source: String?
    var kind: String?
    var weekdays: [Int]?
    var monthDay: Int?
    var shortMonth: String?
    var season: String?
    var onceDate: String?
    var hasTime: Bool?
    var hour: Int?
    var minute: Int?
    var reminders: Bool?
    var leads: [Int]?
    var givenByPriest: Bool?
    /// `thisDay`, `thisAndFuture`, or `wholeSeries`.
    var scope: String?
    /// True when "Don't Show Again" was checked on the custom-rule caution.
    var hideCaution: Bool?
    /// Start of a new rule's activation. Omitted, the rule starts today.
    /// The editor does not send this. A progress fixture needs a day already past.
    var from: String?
    /// Length of a `progress` report. Omitted, the window is the Mac's 30 days.
    var days: Int?
    /// A glossary slug for `glossary`. Omitted opens the index.
    var slug: String?
    /// The named church for `saveSettings`. Empty says there is none.
    var church: String?
    /// A `Reckoning` raw value.
    var reckoning: String?
    /// `hidden`, `shown`, or `observed`.
    var fasting: String?
    var feasts: String?
    /// A `ClockStyle` raw value.
    var clock: String?
    /// The reminder master switch. Delivery is a later slice.
    var notifications: Bool?
    /// A `ReminderLead` raw value.
    var lead: Int?
    var chime: Bool?
    var tick: Bool?
    /// The consistency figure. Words stay either way.
    var showFigure: Bool?
    /// Linux-only. The opening mark still follows the desktop on the next process.
    var motion: Bool?
    /// An absolute path for `exportBackup` or `importBackup`.
    var path: String?
    /// Completes the first run. The library is where a rule is chosen.
    var welcome: Bool?
    /// The spiritual father's name. Empty clears it and keeps names already on rules.
    var father: String?
    /// Show the Julian date beside the civil one.
    var showOldStyleDates: Bool?
}

struct PrayerKnotPayload: Encodable {
    var x: Double
    var y: Double
    /// "counted", "next", or "waiting". The helper classifies; the window only paints.
    var mark: String
}

struct PrayerBeadPayload: Encodable {
    var x: Double
    var y: Double
    var passed: Bool
}

struct PrayerChoicePayload: Encodable {
    var id: String
    var title: String
    var group: String
}

struct PrayerBlockPayload: Encodable {
    var title: String
    var rubric: String?
    /// Plain paragraphs. Existing checks read these, not the links.
    var paragraphs: [String]
    /// One HTML paragraph per plain paragraph. The first occurrence of a term
    /// in a sitting is a link. Later occurrences stay plain.
    var html: [String]
    var source: String
    var sourceURL: String?
    var centred: Bool
}

struct PrayerPayload: Encodable {
    var selection: String
    var ropeAlone: Bool
    var count: Int
    var target: Int
    var targets: [Int]
    var complete: Bool
    var showsRope: Bool
    var cue: String
    var advanced: Bool
    var event: Int
    var sound: String?
    var diameter: Double
    var dot: Double
    var bead: Double
    var knots: [PrayerKnotPayload]
    var beads: [PrayerBeadPayload]
    var choices: [PrayerChoicePayload]
    var words: [PrayerBlockPayload]
}

struct OpeningPointPayload: Encodable {
    var x: Double
    var y: Double
}

struct OpeningBoxPayload: Encodable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

struct OpeningFootrestPayload: Encodable {
    var leadingX: Double
    var trailingX: Double
    var leadingY: Double
    var trailingY: Double
    var thickness: Double
}

/// The opening mark. Positions are fractions from core. The clock matches the Mac opening.
struct OpeningPayload: Encodable {
    var knots: [OpeningPointPayload]
    var knotRadius: Double
    var knotSlots: Int
    var box: OpeningBoxPayload
    var bars: [OpeningBoxPayload]
    var footrest: OpeningFootrestPayload
    var build: Double
    var hold: Double
    var fade: Double
    var knotFade: Double
    var staggerLead: Double
}

struct TonePayload: Encodable {
    var tick: String
    var tock: String
    var bell: String
}

struct ReadingPassagePayload: Encodable {
    var citation: String
    /// The bundled King James text, already broken into paragraphs. Shown as it is.
    var text: String
}

struct LifeSpanPayload: Encodable {
    var text: String
    var italic: Bool
    var bold: Bool
}

struct LifeBlockPayload: Encodable {
    var kind: String
    var text: String
    var spans: [LifeSpanPayload]
    var rows: [[LifeSpanPayload]]
}

struct LifeSectionPayload: Encodable {
    var heading: String
    var blocks: [LifeBlockPayload]
}

struct LifePayload: Encodable {
    var available: Bool
    var dates: String
    var preface: String
    var sections: [LifeSectionPayload]
    var saints: String
    var unavailable: String
    var source: String
    var sourceURL: String
    var license: String
    var licenseURL: String
    var licenseNote: String
}

struct AppointedPayload: Encodable {
    var heading: String
    var note: String
    var paragraphs: [String]
    var source: String
    var sourceURL: String
}

struct ReadingSectionPayload: Encodable {
    var band: Int
    var title: String
    var open: Bool
    var kept: Bool
    var dispensed: Bool
    var stoodDown: Bool
    var asked: Bool
    var passages: [ReadingPassagePayload]
    var life: LifePayload?
    var appointed: AppointedPayload?
}

struct ReadingPayload: Encodable {
    var title: String
    var summary: String
    var fastNote: String
    var abstentionNote: String
    var fathersText: String
    var fathersBy: String
    var footer: String
    var waiting: String
    var waitingDetail: String
    var sections: [ReadingSectionPayload]
    /// Rule ids this call wrote as kept. Opening a section leaves this empty.
    var marked: [String]
    /// The summary and the fast note, with every glossary match linked.
    /// Scripture stays in `sections` as plain text.
    var summaryHtml: String = ""
    var fastNoteHtml: String = ""
}

struct PsalmVersePayload: Encodable {
    var number: String
    var text: String
}

struct PsalmPayload: Encodable {
    var number: Int
    var superscription: String?
    var verses: [PsalmVersePayload]
}

struct KathismaPayload: Encodable {
    var number: Int
    var label: String
    var range: String
    var open: Bool
    var psalms: [PsalmPayload]
}

struct PsalterGroupPayload: Encodable {
    var service: String
    var kathismata: [KathismaPayload]
}

struct PsalterPayload: Encodable {
    var season: String
    var note: String
    var empty: String
    var appointed: [PsalterGroupPayload]
    var manual: Int?
    var manualKathisma: KathismaPayload?
    var source: String
    var marked: [String]
}

struct EntryPayload: Encodable {
    var id: String
    var title: String
    var category: String
    var summary: String
    var time: String
    var kept: Bool
    var dispensed: Bool
    var dispensation: String
    var stoodDown: Bool
    /// Where the first click goes: rope, prayers, reading, psalter, fast, or editor.
    var destination: String
    var selection: String?
    var band: Int?
    /// The menu's name for that destination.
    var action: String
    /// The fasting card's other face. Other cards repeat the summary.
    var back: String
    /// The library template's first glossary slug, or a term in the title.
    /// Omitted when the rule is the person's own and names nothing explained.
    var glossarySlug: String? = nil
}

struct WeekDayPayload: Encodable {
    var date: String
    var day: Int
    var weekday: Int
    var selected: Bool
    var fast: Bool
    var feast: Bool
    var settled: Bool
    /// Set on a month cell. Omitted on the week strip. False is a leading or
    /// trailing blank, not a day of the month on show.
    var inMonth: Bool? = nil
}

/// One successful reply. Nil fields are left out of the JSON.
struct BridgeSuccess: Encodable {
    var v: Int
    var id: Int
    var ok: Bool = true
    var mode: String?
    var displayName: String?
    var today: String?
    var selectedDate: String?
    var hasCompletedFirstRun: Bool?
    var psalmOneVerses: Int?
    var entries: [EntryPayload]?
    var week: [WeekDayPayload]?
    /// Forty-two cells for the month on show. Present only on a home snapshot.
    var month: [WeekDayPayload]?
    /// "October 2026", from core. Present only on a home snapshot.
    var monthTitle: String?
    var dayTitle: String?
    var observedDate: String?
    var showOldStyleDates: Bool?
    var sayingText: String?
    var sayingAuthor: String?
    var sayingSource: String?
    var prayer: PrayerPayload? = nil
    var opening: OpeningPayload? = nil
    var tones: TonePayload? = nil
    var reading: ReadingPayload? = nil
    var psalter: PsalterPayload? = nil
    var library: LibraryPayload? = nil
    var editor: EditorPayload? = nil
    /// "← Today" or "Today →", from core `TodayLink`. Omitted on today itself.
    var todayLink: String? = nil
    /// Set only on the reply that settles a day. The window shows it, then lets it go.
    var thanksgiving: String? = nil
    /// The progress report. Not a home snapshot: today is already outside it.
    var progress: ProgressPayload? = nil
    /// The glossary. Not a home snapshot, and not a ruling.
    var glossary: GlossaryPayload? = nil
    /// Settings and the welcome. A read or an export is not a home snapshot.
    var settings: SettingsPayload? = nil
    /// True only while the record has no rules and the welcome has not been finished.
    var needsWelcome: Bool? = nil
    /// Stored beside the record, so a helper restart still knows.
    var reducedMotion: Bool? = nil
    /// Unix seconds when today's saying began its pan. Only `noteSayingPan`
    /// sets it. A review record does not keep the file.
    var sayingPanStart: Double? = nil
}

struct ProgressRulePayload: Encodable {
    var id: String
    var title: String
    /// "1 of 2". Kept, out of what came round. Stood-down days are already out of both.
    var count: String
}

struct ProgressPayload: Encodable {
    var heading: String
    var through: String
    var summary: [String]
    var rules: [ProgressRulePayload]
    /// Rounded percent. Omitted when the figure is hidden or nothing has come due.
    var figure: Int? = nil
    var figureNote: String? = nil
}

struct BridgeFailure: Encodable {
    var v: Int
    var id: Int
    var ok: Bool = false
    var error: String
}

struct HomeSnapshot {
    var selectedDate: String
    var displayName: String
    var hasCompletedFirstRun: Bool
    var psalmOneVerses: Int
    var entries: [EntryPayload]
    var week: [WeekDayPayload]
    var month: [WeekDayPayload]
    var monthTitle: String
    var dayTitle: String
    var observedDate: String
    var showOldStyleDates: Bool
    var sayingText: String
    var sayingAuthor: String
    var sayingSource: String
    var todayLink: String?
    var needsWelcome: Bool
    var reducedMotion: Bool

    func success(id: Int, today: String) -> BridgeSuccess {
        BridgeSuccess(
            v: bridgeProtocolVersion, id: id, displayName: displayName, today: today,
            selectedDate: selectedDate, hasCompletedFirstRun: hasCompletedFirstRun,
            psalmOneVerses: psalmOneVerses, entries: entries, week: week,
            month: month, monthTitle: monthTitle,
            dayTitle: dayTitle, observedDate: observedDate,
            showOldStyleDates: showOldStyleDates, sayingText: sayingText,
            sayingAuthor: sayingAuthor, sayingSource: sayingSource,
            todayLink: todayLink, needsWelcome: needsWelcome, reducedMotion: reducedMotion
        )
    }
}
