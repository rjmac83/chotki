import Testing
import Foundation
@testable import ChotkiCore

/// Every editable part of a rule, and every setting, reachable on both platforms.
///
/// A port is finished when the feature surfaces match, not when the app runs.
/// Running the Android app could never have revealed that it had no reminder
/// controls and no clock setting: a control that was never written has nothing
/// to click and nothing to fail. Only holding it against macOS finds that, and
/// this is that comparison, made mechanical.
///
/// **What this can and cannot do, stated plainly, because it has been patched
/// four times.** It reads source text. It can tell you a control was never
/// written — which is the failure that has actually happened, repeatedly, and
/// which no amount of running the app reveals because there is nothing to tap.
/// It cannot tell you a control *works*: gutting a function's body while
/// leaving its name passes this test, and was tried.
///
/// So the division is deliberate. This guards the feature *surface* across
/// three platforms. Whether each one behaves belongs to that platform's own
/// tests — `ChotkiTests` on iOS, the instrumentation suite on Android, and the
/// macOS suite — where the record can actually be read back.
///
/// Every patch it has needed came from the same mistake in a different coat:
/// searching for a word rather than for the thing. `reminders` was found in a
/// line of copy above no controls; `jurisdiction` in a read-only line;
/// `exportJSON` in the one platform of three that spells it that way. It now
/// searches whole trees for the core call behind the door, rather than a named
/// file for a name.
@Suite("The two interfaces expose the same things")
struct PortParityTests {

    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private func source(_ path: String) throws -> String {
        try String(contentsOf: Self.root.appendingPathComponent(path), encoding: .utf8)
    }

    @Test("each iOS reading surface offers completion after its content")
    func iosReadingCompletionSurfaces() throws {
        let text = try source("ios/Chotki/ReadingViews.swift")
        func body(from start: String, to end: String) throws -> String {
            let begin = try #require(text.range(of: start))
            let finish = try #require(text.range(of: end, range: begin.upperBound..<text.endIndex))
            return String(text[begin.upperBound..<finish.lowerBound])
        }
        let scripture = try body(from: "ForEach(ReadingOrder.orderedBands", to: "disclosure(ReadingOrder.sectionTitle(band: ReadingOrder.saintLifeBand)")
        #expect(scripture.contains("readingEnd(band: band)"))
        let departed = try body(from: "if model.settings.jurisdiction.tradition.isSlavic", to: "if let week = model.liturgical.akathistWeek")
        #expect(departed.contains("readingEnd(band: ReadingOrder.departedBand)"))
        let life = try body(from: "private func lifeBody", to: "private func blockText")
        let unavailable = try #require(life.range(of: "} else {"))
        #expect(life[..<unavailable.lowerBound].contains("readingEnd(band: ReadingOrder.saintLifeBand)"))
        #expect(!life[unavailable.upperBound...].contains("readingEnd("), "unavailable content must not complete a rule")
        let akathist = try body(from: "private func akathistSection", to: "private func readingEnd")
        #expect(akathist.contains("readingEnd(band: ReadingOrder.akathistBand)"))
    }

    /// The macOS file, the Android file, and what both must mention.
    ///
    /// Each entry is a thing a person can change. Add to this whenever the
    /// model gains one — the list is the checklist, and it is the checklist
    /// because nobody keeps one in their head across two languages.
    /// Named by the type the control has to reach for, not by the field.
    ///
    /// Searching for the field name is what let this through the first time:
    /// `reminders` appeared once in the Android editor and that one appearance
    /// was a line of copy about reminders, above no controls. A control that
    /// offers a choice of leads has to mention `ReminderLead`; prose cannot.
    private let editableRuleFields = [
        (what: "the title", token: "title"),
        (what: "a note", token: "note"),
        (what: "where it came from", token: "source"),
        (what: "how often", token: "Recurrence"),
        (what: "a time of day", token: "TimeOfDay"),
        (what: "reminders", token: "ReminderLead"),
    ]

    private let editableSettings = [
        (what: "the jurisdiction", token: "jurisdiction"),
        (what: "the clock", token: "ClockStyle"),
        (what: "observances", token: "observances"),
    ]

    /// Three now, not two. The port that added the third is the one that made
    /// this test matter: iOS inherits core unchanged, so nothing can be lost in
    /// translation — but a screen can still simply not be written.
    private var editors: [(String, String)] {
        [
            ("macOS", "macos/Sources/Chotki/RuleEditorView.swift"),
            ("Android", "android/app/src/main/kotlin/org/chotki/app/ui/RuleEditor.kt"),
            ("iOS", "ios/Chotki/RuleEditor.swift"),
        ]
    }

    private var settingsScreens: [(String, String)] {
        [
            ("macOS", "macos/Sources/Chotki/SettingsView.swift"),
            ("Android", "android/app/src/main/kotlin/org/chotki/app/ui/SettingsScreen.kt"),
            ("iOS", "ios/Chotki/SettingsView.swift"),
        ]
    }

    @Test("a rule can be edited the same way on every platform")
    func ruleEditorsMatch() throws {
        for (platform, path) in editors {
            let file = try source(path)
            for field in editableRuleFields {
                #expect(
                    file.contains(field.token),
                    "\(platform) cannot edit \(field.what) — it is in the model and on the others"
                )
            }
        }
    }

    /// Whole trees, not named files.
    ///
    /// This is the third time a check here has looked in one file and missed
    /// the thing because the platform had put it in another. Naming files is
    /// how `reminders` was searched for in the Android editor and found in a
    /// line of copy; naming a file is also how the export check first reported
    /// every platform as missing it when two had it elsewhere. Ask the tree.
    private func tree(_ path: String) throws -> String {
        let root = Self.root.appendingPathComponent(path)
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { ["swift", "kt"].contains($0.pathExtension) }
            ?? []
        return try files
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .map(Self.withoutComments)
            .joined()
    }

    /// Strips comments, so a check cannot be satisfied by prose.
    ///
    /// This is the failure this suite has recorded twice and then walked into a
    /// third time: `reminders` was found in a line of copy above no controls,
    /// and `addAsRuleLabel` was found in a doc comment explaining why the button
    /// mattered — while the button itself had been removed. A mention is not an
    /// implementation, and after this it cannot pass for one.
    ///
    /// Line comments only. Block comments are rare here and stripping them
    /// correctly across two languages is more machinery than the problem needs.
    static func withoutComments(_ code: String) -> String {
        code.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> Substring in
                let trimmed = line.drop { $0 == " " || $0 == "\t" }
                if trimmed.hasPrefix("//") || trimmed.hasPrefix("*") { return "" }
                return line
            }
            .joined(separator: "\n")
    }

    @Test("the record can be kept on every platform")
    func recordCanLeaveEveryPlatform() throws {
        // Nothing is destroyed and nothing is sent anywhere, so a copy someone
        // makes themselves is the only way a record survives a new phone — and
        // on Android, the only way it survives an uninstall at all.
        //
        // Each platform names its own door differently; what they share is the
        // core call behind it.
        for (platform, path) in [
            ("macOS", "macos/Sources"),
            ("Android", "android/app/src/main"),
            ("iOS", "ios/Chotki"),
        ] {
            let code = try tree(path)
            #expect(
                code.contains("exportBackup") || code.contains("exportJSON")
                    || code.contains("exportJson"),
                "\(platform) offers no way to keep a copy of the record"
            )
            #expect(
                code.contains("importBackup") || code.contains("importJSON")
                    || code.contains("importJson") || code.contains("restoreFrom"),
                "\(platform) offers no way to put a copy back"
            )
        }
    }

    @Test("the old two-platform editor check", .disabled("folded into ruleEditorsMatch"))
    func oldEditorCheck() throws {
        let mac = try source("macos/Sources/Chotki/RuleEditorView.swift")
        let android = try source("android/app/src/main/kotlin/org/chotki/app/ui/RuleEditor.kt")

        for field in editableRuleFields {
            #expect(mac.contains(field.token), "macOS cannot edit \(field.what)")
            #expect(
                android.contains(field.token),
                "Android cannot edit \(field.what) — it is in the model and on the Mac"
            )
        }
    }

    @Test("the same settings can be changed on every platform")
    func settingsMatch() throws {
        for (platform, path) in settingsScreens {
            let file = try source(path)
            for setting in editableSettings {
                #expect(
                    file.contains(setting.token),
                    "\(platform) cannot change \(setting.what) — it is in the model and on the others"
                )
            }
        }

        let android = try source("android/app/src/main/kotlin/org/chotki/app/ui/SettingsScreen.kt")

        // Mentioning a setting is not offering it. The church and the calendar
        // were both named on this screen and both read-only — printed, not
        // chosen — and the check above passed the whole time. A control writes,
        // so count the writes.
        let offered = ["ValueRow(", "SwitchRow(", "NameField("].reduce(0) {
            $0 + android.components(separatedBy: $1).count - 1
        }
        #expect(
            offered >= editableSettings.count,
            "Android names \(editableSettings.count) settings but offers \(offered) controls"
        )
        #expect(
            android.contains("updateSettings") || android.contains("setClockStyle"),
            "Android's settings screen never writes anything back"
        )
    }

    /// The signal that gave both omissions away, had anyone looked.
    ///
    /// The Android editor carried the sentence explaining reminders while
    /// having no reminder controls. Copy describing a control that is not there
    /// means a screen was ported halfway.
    @Test("nothing explains a control that is not there")
    func noOrphanedExplanation() throws {
        let android = try source("android/app/src/main/kotlin/org/chotki/app/ui/RuleEditor.kt")

        if android.contains("reminders are spread across the waking hours") {
            #expect(
                android.contains("ReminderLead"),
                "the editor explains reminders but offers no way to set them"
            )
        }
    }

    /// Every platform that *shows* the church calendar must also *fetch* it.
    ///
    /// iOS shipped reading `liturgicalDay` from the store with nothing on the
    /// whole platform ever writing to it: no `LiturgicalService`, no fetch, no
    /// network call at all. The reading screen was permanently empty and said
    /// it would fill in when it could, which reads as a slow network rather
    /// than as a half that was never built.
    ///
    /// That is a new shape of omission for this project and worth its own
    /// check: not a missing control, but a reader with no writer. Android
    /// reached the same place by a different road — the screen was written and
    /// the INTERNET permission was not.
    @Test("every platform fetches the calendar it displays")
    func everyPlatformFetchesWhatItShows() throws {
        for (platform, path) in [
            ("macOS", "macos/Sources"),
            ("Android", "android/app/src/main"),
            ("iOS", "ios/Chotki"),
        ] {
            let code = try tree(path)
            guard code.contains("liturgicalDay") else { continue }

            #expect(
                code.contains("LiturgicalService"),
                "\(platform) shows the church calendar but never opens the service that fills it"
            )
            #expect(
                code.contains(".refresh(") || code.contains("refreshCalendar")
                    || code.contains("refreshLiturgical"),
                "\(platform) reads the calendar from the store and never asks the network for it"
            )
        }
    }

    /// The prayers screen offers everything in the book, not a slice of it.
    ///
    /// iOS offered the rope prayers and nothing else: no rules to say through,
    /// none of the prayers that are read rather than counted, and no text of
    /// any prayer anywhere on the screen. Six of the bundled prayers and all
    /// three rules were unreachable on the platform.
    ///
    /// So this asks for the groups by the call that builds each one. A screen
    /// that offers the rules has to reach for the sequences; one that separates
    /// what is counted from what is read has to filter on `isForRope` in both
    /// directions. Prose cannot do either.
    @Test("every platform offers every prayer, in every group")
    func everyPlatformOffersEveryPrayer() throws {
        for (platform, path) in [
            ("macOS", "macos/Sources"),
            ("Android", "android/app/src/main"),
            ("iOS", "ios/Chotki"),
        ] {
            let code = try tree(path)

            if platform == "Android" {
                #expect(code.contains("ChooserRow(screen)"), "Android has no prayer chooser")
            } else {
                #expect(code.contains("The rope alone"), "\(platform) does not offer the rope on its own")
            }
            #expect(
                code.contains("sequences") || code.contains("prayerSequences"),
                "\(platform) offers no rule to say through — only single prayers"
            )
            #expect(
                code.contains("forRope") || code.contains("ForRope"),
                "\(platform) does not know which prayers are said on the rope"
            )
            #expect(
                code.contains("notForRope") || code.contains("filterNot"),
                "\(platform) offers only the rope prayers — the ones that are read are unreachable"
            )
            // Choosing a prayer and never showing it is the state iOS shipped
            // in. The words come from `paragraphs`; a title alone is a menu.
            #expect(
                code.contains("paragraphs"),
                "\(platform) lets you choose a prayer and never shows its words"
            )
            // The rope rule, and the override, belong to core on every
            // platform. iOS had its own three-field struct in view state: no
            // override, no rope rule, and the count lost on every navigation.
            #expect(
                code.contains("PrayerScreen"),
                "\(platform) decides about the rope for itself instead of asking core"
            )
        }
    }

    /// An unfamiliar word leads somewhere, **wherever** it is read.
    ///
    /// This check began by asking whether a platform scanned its text anywhere
    /// at all, and Android passed it while two of its three reading surfaces
    /// were plain `Text`. One linked screen is enough to satisfy "does this
    /// platform have a glossary"; it is not remotely enough to satisfy "does
    /// the word I am looking at lead anywhere", which is the thing anyone
    /// actually wants. So it asks per surface now.
    ///
    /// A surface is any file that renders prayer paragraphs or a liturgical
    /// day's commemoration — found by what it draws rather than by its name,
    /// because naming files is how three earlier checks here missed the thing
    /// by looking in the wrong one. Move the code and the check follows it.
    ///
    /// The welcome screens are excluded deliberately: `Welcome.paragraphs` is
    /// Ryan's own prose about what the app is for, not liturgical text, and
    /// underlining half of it would be noise.
    @Test("every surface that shows the text links its terms")
    func everySurfaceLinksItsTerms() throws {
        let linking = ["TermText", "PrayerProse", "scanOnce", ".scan(", "linked("]

        for (platform, path) in [
            ("macOS", "macos/Sources"),
            ("Android", "android/app/src/main"),
            ("iOS", "ios/Chotki"),
        ] {
            let root = Self.root.appendingPathComponent(path)
            let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }
                .filter { ["swift", "kt"].contains($0.pathExtension) }
                ?? []

            for file in files {
                let code = Self.withoutComments(try String(contentsOf: file, encoding: .utf8))

                // The welcome is prose, not liturgical text.
                let prayerText = code.replacingOccurrences(of: "Welcome.paragraphs", with: "")
                    .contains("paragraphs")
                let commemoration = code.contains("summaryTitle")
                guard prayerText || commemoration else { continue }

                #expect(
                    linking.contains(where: code.contains),
                    """
                    \(platform)'s \(file.lastPathComponent) shows \
                    \(prayerText ? "prayer text" : "the commemoration") with nothing linked — \
                    a word a newcomer stops at leads nowhere on that screen
                    """
                )
            }
        }
    }

    /// Everything the Mac's right-click menu offers, offered everywhere.
    ///
    /// This is the largest gap the project has had. macOS has carried a context
    /// menu on every rule since the first version — mark kept, mark kept late,
    /// stand down for the day, edit, pause, resume — and **neither mobile
    /// platform had any of it**. iOS could not reach the editor at all: the
    /// route existed and nothing navigated to it. Android had a pencil, and
    /// `standDown` and `remove` sat on `AppState` called from nowhere.
    ///
    /// Both are now long-press, which is the gesture that means right-click on
    /// a phone. The *gesture* is per-platform; the operations are not.
    ///
    /// Checked as user-visible words rather than as method names, because the
    /// method names differ by platform and the words are the promise. A menu
    /// that says "Pause this rule" is a menu with a pause in it.
    @Test("every platform offers every action the Mac offers on a rule")
    func everyPlatformOffersTheSameActions() throws {
        let actions = [
            "Mark as kept, late",
            "Stand down for this day",
            "Pause this rule",
            "Resume this rule",
            "Edit rule",
        ]

        for (platform, path) in [
            ("macOS", "macos/Sources"),
            ("Android", "android/app/src/main"),
            ("iOS", "ios/Chotki"),
        ] {
            let code = try tree(path)
            // On the Mac, resuming is no longer a menu item of its own: "Pause
            // this rule" carries a tick while the rule is paused, and choosing
            // it again takes the rule back. The mobile platforms still say
            // "Resume this rule" until they follow.
            if platform == "macOS" {
                #expect(
                    code.contains("isOn: paused") && code.contains("model.resume("),
                    "macOS must be able to resume a paused rule from its menu"
                )
            }
            for action in actions {
                if platform == "macOS" && action == "Resume this rule" { continue }
                #expect(
                    code.lowercased().contains(action.lowercased()),
                    "\(platform) does not offer \"\(action)\" anywhere — the Mac has it on every rule"
                )
            }
            // Saying the words is not doing the thing. Pausing and resuming are
            // activation surgery, and only `EditPlanner` does it correctly —
            // writing an archive flag instead would read the same and score
            // the paused days as missed.
            #expect(
                code.contains("EditPlanner"),
                "\(platform) names pause and resume but never asks EditPlanner to do them"
            )
        }
    }

    /// The whole library, not the top third of it.
    ///
    /// iOS shipped with the bundled templates and nothing else: no Custom
    /// section, so a rule he had written and later set aside could not be found
    /// again on that platform, and no way to write one in the first place.
    @Test("every platform offers the whole library")
    func everyPlatformOffersTheWholeLibrary() throws {
        for (platform, path) in [
            ("macOS", "macos/Sources"),
            ("Android", "android/app/src/main"),
            ("iOS", "ios/Chotki"),
        ] {
            let code = try tree(path)
            #expect(
                code.contains("Write your own rule"),
                "\(platform) offers no way to write a rule of your own"
            )
            #expect(
                code.contains("customEntries"),
                "\(platform) has no Custom section — a rule set aside cannot be found again"
            )
            #expect(
                code.contains("takeUp") && code.contains("setAside"),
                "\(platform) cannot put a rule of your own back, or take it out of the library"
            )
        }
    }

    /// The day under the view moves on, everywhere.
    ///
    /// Chotki was opened on the 28th, closed, and opened again on the 29th
    /// still showing the 28th — on all three platforms at once, because all
    /// three set the selected day in their initialiser and never looked again.
    /// A rule ticked on that screen went onto the wrong day.
    ///
    /// The decision is `DayRollover`'s. What differs per platform is only when
    /// it is asked: a resident Mac has a tick and a wake notification, a phone
    /// has coming back to the foreground and a midnight broadcast. So this
    /// checks that each platform reaches for the rule and has somewhere to
    /// call it from — not the mechanism, which is properly different.
    @Test("every platform moves the day on under the view")
    func everyPlatformAdvancesTheDay() throws {
        for (platform, path) in [
            ("macOS", "macos/Sources"),
            ("Android", "android/app/src/main"),
            ("iOS", "ios/Chotki"),
        ] {
            let code = try tree(path)
            #expect(
                code.contains("DayRollover"),
                "\(platform) decides for itself whether the day has moved, or does not notice"
            )
            #expect(
                code.contains("advanceDayIfNeeded"),
                "\(platform) has the rule but nothing that applies it"
            )
        }
    }

    /// The first thing anyone sees, on both platforms.
    ///
    /// Android had no first-run screen at all — the flag was in the shared
    /// settings and nothing on that side read it — so every install opened onto
    /// an empty day with no word about what the app was for.
    @Test("both platforms show the welcome, and both read it from core")
    func welcomeIsOnBothPlatforms() throws {
        let mac = try source("macos/Sources/Chotki/OnboardingView.swift")
        let android = try source("android/app/src/main/kotlin/org/chotki/app/ui/WelcomeScreen.kt")
        let ios = try source("ios/Chotki/WelcomeView.swift")

        for (platform, file) in [("macOS", mac), ("Android", android), ("iOS", ios)] {
            #expect(file.contains("Welcome.title"), "\(platform) does not show the welcome title")
            #expect(file.contains("Welcome.paragraphs"), "\(platform) does not show the welcome text")
            #expect(file.contains("Welcome.beginLabel"), "\(platform) writes its own button label")
            #expect(
                !file.contains("Welcome to Chotki"),
                "\(platform) has the welcome text typed into it rather than read from core"
            )
        }

        // Both have to honour the flag, or the screen shows every launch.
        for (platform, path) in [
            ("macOS", "macos/Sources/Chotki/RootView.swift"),
            ("Android", "android/app/src/main/kotlin/org/chotki/app/ui/Shell.kt"),
            ("iOS", "ios/Chotki/ChotkiApp.swift"),
        ] {
            #expect(
                try source(path).contains("hasCompletedFirstRun"),
                "\(platform) shows the welcome every launch, or never"
            )
        }
    }

}

private extension PortParityTests {
    /// Where each platform's interface lives. One list, because a check that
    /// enumerates two of three platforms passes while the third is missing the
    /// feature entirely — which is the whole failure this suite exists for.
    static var appTrees: [(String, String)] {
        [
            ("macOS", "macos/Sources"),
            ("Android", "android/app/src/main"),
            ("iOS", "ios/Chotki"),
        ]
    }
}
