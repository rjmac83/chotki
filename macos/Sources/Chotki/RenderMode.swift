import SwiftUI
import AppKit
import ChotkiCore

/// Renders the interface to PNG files without opening a window.
///
/// A development affordance for checking layout: it uses an in-memory fictional
/// practice store, so nothing real is touched, and it never reads the screen.
@MainActor
enum RenderMode {

    static func run(prefix: String) {
        do {
            let store = try seededStore()
            let model = AppModel(
                store: store, notifier: NullNotifier(), launchAtLogin: NullLaunchAtLogin(),
                storage: .none(), startsReminders: false, writesBackups: false, loadsCalendar: false
            )

            // Content views directly: ImageRenderer does not draw ScrollView
            // contents, so the scroll chrome is bypassed.
            // Populate the liturgical cache synchronously so shading is
            // representative; the app does this asynchronously at launch.
            model.selectedDate = CalendarDate(year: 2026, month: 8, day: 19)!
            model.visibleMonth = model.selectedDate
            try? model.liturgical.loadSnapshot(around: model.selectedDate)

            render(
                ZStack {
                    RuleBackdrop()
                    RuleTabViewContent(model: model)
                },
                to: "\(prefix)-rule.png"
            )
            render(ReadingViewContent(model: model),
                   to: "\(prefix)-reading.png")
            render(ProgressTabViewContent(model: model),
                   to: "\(prefix)-progress.png")
            render(LibraryViewContent(model: model),
                   to: "\(prefix)-library.png")
            if let morning = model.rules.first(where: { $0.hasPrayers }) {
                render(PrayerViewContent(model: model, ruleID: morning.id),
                       to: "\(prefix)-prayers.png")
                // The framed version. The content view composes without a
                // scroll container and so carries no border; this is the one
                // a reader actually sees.
                render(PrayerView(model: model, ruleID: morning.id)
                        .frame(height: Theme.popoverHeight)
                        .background(Theme.ground),
                       to: "\(prefix)-prayers-framed.png")
            }

            render(RopeWords(model: model, selection: "morning").padding(20), to: "\(prefix)-ropewords.png")

            // The rope follows the prayer: shown for a counted one, hidden for a
            // rule that is read through, shown when nothing is chosen.
            for (selection, name) in [("jesus-prayer", "rope"), ("morning", "rope-read"), (nil, "rope-alone")] {
                model.prayers = PrayerScreen(selection: selection, count: 21)
                render(PrayerRopeView(model: model).frame(height: Theme.popoverHeight),
                       to: "\(prefix)-\(name).png")
            }

            FileHandle.standardOutput.write(Data("rendered\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("render failed: \(error)\n".utf8))
        }
        NSApp.terminate(nil)
    }

    /// Fictional practice and a committed public calendar fixture. No personal paths are read.
    static func seededStore() throws -> any Store {
        let store = try SQLiteStore(path: ":memory:")
        let today = CalendarDate(year: 2026, month: 8, day: 19)!
        let recordToday = CalendarDate(Date(), in: .current)
        if let url = Bundle.module.url(forResource: "calendar", withExtension: "json", subdirectory: "Resources/Preview") {
            try store.saveLiturgicalDay(JSONDecoder().decode(LiturgicalDay.self, from: Data(contentsOf: url)))
        }
        var clean = AppSettings.default
        clean.displayName = "Anna"
        clean.observances = ObservanceSettings(fasting: .observed, feasts: .shown)
        clean.hasCompletedFirstRun = ProcessInfo.processInfo.environment["CHOTKI_RENDER_FIRSTRUN"] != "1"
        clean.showOldStyleDates = true
        try store.saveSettings(clean)

        // Someone who already keeps rules is not on their first run, and the
        // app marks it complete for them — so the welcome can only be drawn
        // against an empty record, which is the only state it ever appears in.
        if ProcessInfo.processInfo.environment["CHOTKI_RENDER_FIRSTRUN"] == "1" {
            return store
        }

        // A believable rule, kept mostly but not perfectly.
        let sample: [(String, TimeOfDay?, Recurrence, RuleCategory)] = [
            ("Morning prayers", TimeOfDay(hour: 6, minute: 30), .daily, .prayer),
            ("The Wednesday and Friday fast", nil,
             .weekly(days: [.wednesday, .friday]), .fasting),
            ("The day's Gospel", TimeOfDay(hour: 12, minute: 0), .daily, .reading),
            ("The life of the day's saint", nil, .daily, .reading),
            ("The Jesus Prayer", nil, .daily, .prayer),
            ("Evening prayers", TimeOfDay(hour: 21, minute: 30), .daily, .prayer)
        ]

        for (title, time, recurrence, category) in sample {
            // Prefer the real template, so the sample carries its prayers.
            let template = RuleLibrary.shared.templates.first { $0.title == title }
            let rule = template?.makeRule(source: "the library") ?? Rule(
                title: title, source: "the library", recurrence: recurrence,
                timeOfDay: time, category: category.rawValue
            )
            try store.save(rule)
            try store.save(Activation(ruleID: rule.id, from: min(today, recordToday).adding(days: -40)))

            for anchor in [recordToday, today] {
              for offset in 0...40 {
                let date = anchor.adding(days: -offset)
                // Evening prayers slip on Fridays; one stretch of the prayer
                // rope stood down; everything else held.
                if title == "Evening prayers" && date.weekday == .friday { continue }
                if title == "The Jesus Prayer" && (12...15).contains(offset) {
                    try store.save(Occurrence(ruleID: rule.id, date: date, status: .skipped))
                    continue
                }
                // Today: only the morning is done so far.
                if offset == 0 && title != "Morning prayers" { continue }
                let status: OccurrenceStatus = offset % 13 == 0 ? .completedLate : .completed
                try store.save(Occurrence(ruleID: rule.id, date: date, status: status))
              }
            }
        }

        return store
    }

    /// Renders the real window, through AppKit rather than ImageRenderer.
    ///
    /// `ImageRenderer` cannot draw the contents of a ScrollView, nor AppKit
    /// controls like a Picker's menu button. That covers most of this app: the
    /// library, the glossary, the prayers and the whole window are scrolled, and
    /// the harness has silently drawn them as empty panels — which is how a
    /// missing feature once got signed off here.
    ///
    /// Putting the view in a real window and asking the view hierarchy to draw
    /// itself gets all of it. The window is positioned far off any screen and
    /// never ordered in front of anything: this draws the view, it does not
    /// capture the display.
    /// `CHOTKI_RENDER_DATE=YYYY-MM-DD` draws another day of the shipped calendar. Fictional practice
    /// and the shipped calendar only; nothing is read from anyone's record.
    private static var renderDate: CalendarDate? {
        ProcessInfo.processInfo.environment["CHOTKI_RENDER_DATE"].flatMap { CalendarDate(iso: $0) }
    }

    static func runWindow(prefix: String) {
        do {
            let store = try seededStore()
            let model = AppModel(
                store: store, notifier: NullNotifier(), launchAtLogin: NullLaunchAtLogin(),
                storage: .none(), startsReminders: false, writesBackups: false, loadsCalendar: false
            )
            model.selectedDate = renderDate ?? CalendarDate(year: 2026, month: 8, day: 19)!
            model.visibleMonth = model.selectedDate
            // `CHOTKI_RENDER_RESTING=1` sets two fictional rules aside, so the
            // greyed cards can be looked at: one paused, one stood down for the
            // day drawn. Pair it with a CHOTKI_RENDER_DATE of today (the pause
            // day) or of the day after (a paused rule on a day it is not due).
            if ProcessInfo.processInfo.environment["CHOTKI_RENDER_RESTING"] == "1" {
                if let paused = model.rules.first(where: { $0.title == "Evening prayers" }) {
                    model.standDown(paused)
                }
                if let stoodDown = model.rules.first(where: { $0.title == "The Jesus Prayer" }) {
                    model.setStatus(.skipped, for: stoodDown, on: model.selectedDate)
                }
            }
            try? model.liturgical.loadSnapshot(around: model.selectedDate)

            let size = NSSize(width: 1100, height: 860)
            let host = MainWindowController.hostingView(model: model)
            host.frame = NSRect(origin: .zero, size: size)

            let window = NSWindow(
                contentRect: host.frame,
                styleMask: [.titled, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            window.contentView = host
            window.setFrameOrigin(NSPoint(x: -30_000, y: -30_000))
            window.orderFrontRegardless()

            func shot(_ name: String, _ arrange: () -> Void) {
                draw(host, name, prefix: prefix, arrange)
            }

            shot("window-home") { }
            // `CHOTKI_RENDER_PAUSE_AFTER=1` pauses a rule after the first draw, as
            // choosing "Pause This Rule" does, and draws again: a card that is
            // greyed only when the rule is paused before the window first draws
            // is the bug this exists to catch.
            if ProcessInfo.processInfo.environment["CHOTKI_RENDER_PAUSE_AFTER"] == "1" {
                // Through the card's own menu closure, as a right click does,
                // rather than by calling the model: the closure is what was
                // captured when the card last drew.
                func surfaces(in view: NSView) -> [RuleCardInteraction.Surface] {
                    (view as? RuleCardInteraction.Surface).map { [$0] } ?? []
                        + view.subviews.flatMap(surfaces(in:))
                }
                shot("window-home-paused-after") {
                    surfaces(in: host).first { $0.title == "Evening prayers" }?
                        .menuActions.first { $0.title == "Pause This Rule" }?.perform()
                }
            }
            if ProcessInfo.processInfo.environment["CHOTKI_RENDER_SETTLED_IMAGE"] == "1" {
                // The render flag selects the same resting crop immediately,
                // avoiding a minute-long render while leaving daily timing
                // and the live record untouched.
                inOwnWindow(
                    SayingCard(model: model).frame(width: 850, height: 270),
                    size: NSSize(width: 850, height: 270), "window-image-settled", prefix: prefix
                )
            }
            inOwnWindow(MainWindowView(model: model, initiallyCollapsed: true),
                        size: size, "window-collapsed", prefix: prefix)
            shot("window-month") { model.calendarExpanded = true }
            shot("window-narrow") {
                model.calendarExpanded = false
                window.setContentSize(NSSize(width: 620, height: 660))
            }
            window.setContentSize(size)
            shot("window-library") { model.screen = .library }
            shot("window-library-bottom") { scrollDown(host, by: 4000) }
            shot("window-prayers") {
                model.prayers = PrayerScreen(selection: "morning")
                model.screen = .prayerRope
            }
            // The rope is a ring of knots; check each offered count.
            for target in PrayerScreen.targets {
                shot("window-rope-\(target)") {
                    var screen = PrayerScreen(selection: "jesus-prayer")
                    screen.aim(at: target)
                    for _ in 0..<(target * 2 / 5) { _ = screen.advance() }
                    model.prayers = screen
                    model.screen = .prayerRope
                }
            }
            describeMenus(in: host)
            shot("window-glossary") { model.openGlossary("publican") }
            shot("window-reading") { model.openReading(band: 0) }
            shot("window-progress") { model.tab = .progress }
            shot("window-settings") { model.screen = .settings }
            describeMenus(in: host)

            // Use a correctly sized second window for the companion. Reusing
            // the desktop window left a 400-point popover centered in a black
            // 1100-point image, which hid layout faults rather than exposing them.
            window.contentView = nil
            window.orderOut(nil)
            model.navigationSurface = .companion
            model.screen = .main
            model.tab = .rule
            let popover = NSHostingView(rootView: RootView(model: model))
            popover.sizingOptions = []
            popover.frame = NSRect(x: 0, y: 0, width: Theme.popoverWidth, height: Theme.popoverHeight)
            let companion = NSWindow(
                contentRect: popover.frame,
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            companion.contentView = popover
            companion.setFrameOrigin(NSPoint(x: -30_000, y: -30_000))
            companion.orderFrontRegardless()
            draw(popover, "popover-home", prefix: prefix) { }
            draw(popover, "popover-library", prefix: prefix) { model.screen = .library }
            draw(popover, "popover-prayers", prefix: prefix) {
                model.prayers = PrayerScreen(selection: "jesus-prayer", count: 12)
                model.screen = .prayerRope
            }
            draw(popover, "popover-reading", prefix: prefix) { model.openReading(band: 0) }
            draw(popover, "popover-rope-100", prefix: prefix) {
                var screen = PrayerScreen(selection: "jesus-prayer")
                screen.aim(at: 100)
                for _ in 0..<40 { _ = screen.advance() }
                model.prayers = screen
                model.screen = .prayerRope
            }
            draw(popover, "popover-glossary", prefix: prefix) { model.openGlossary("amen") }
            companion.orderOut(nil)

            if let entry = model.entries(on: model.selectedDate).first {
                inOwnWindow(
                    EntryRow(model: model, entry: entry, expandedID: .constant(entry.rule.id))
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.ground),
                    size: NSSize(width: 360, height: 400), "window-card-expanded", prefix: prefix
                )
            }
            if let template = RuleLibrary.shared.templates.first(where: { $0.id == "lives-of-saints" }) {
                let entry = DayEntry(rule: template.makeRule(source: "the library"),
                                     date: model.selectedDate, occurrence: nil, dispensation: nil)
                inOwnWindow(
                    EntryRow(model: model, entry: entry)
                        .frame(width: 132, height: 232).background(Theme.ground),
                    size: NSSize(width: 132, height: 232), "window-saint-card", prefix: prefix
                )
            }
            model.update { $0.spiritualFatherName = "Father Seraphim" }
            inOwnWindow(
                RuleEditorView(model: model, ruleID: nil, dismiss: {}),
                size: NSSize(width: 520, height: 620), "window-editor-father", prefix: prefix
            )

            FileHandle.standardOutput.write(Data("rendered\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("window render failed: \(error)\n".utf8))
        }
        NSApp.terminate(nil)
    }

    /// Draws one view in an off-screen window of its own.
    ///
    /// Needed for anything a view raises through its own `@State`, which
    /// nothing outside it can reach. Sharing the main window for this left the
    /// hosting view unconstrained and it grew to its natural height.
    private static func inOwnWindow<Root: View>(
        _ root: Root, size: NSSize, _ name: String, prefix: String
    ) {
        // The explicit frame is the point. As the root of a window, a ScrollView
        // has nothing above it telling it how tall to be, so it reports its
        // content height and the hosting view grows to match — which drew the
        // explainer as a strip 12,786 pixels tall. In the app the split view's
        // detail column does this constraining.
        // The ground and the dark appearance come from the window in the app —
        // `MainWindowView` paints the detail column — so a view hosted on its
        // own has to be given both, or it draws dark text on white.
        let host = NSHostingView(
            rootView: root
                .frame(width: size.width, height: size.height)
                .background(Theme.ground)
        )
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.setContentSize(size)
        window.setFrameOrigin(NSPoint(x: -30_000, y: -30_000))
        window.orderFrontRegardless()
        draw(host, name, prefix: prefix) { }
        window.orderOut(nil)
    }

    /// Arrange, let SwiftUI settle, then ask the view to draw itself.
    private static func draw(
        _ host: NSView, _ name: String, prefix: String, _ arrange: () -> Void
    ) {
        arrange()
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: "\(prefix)-\(name).png"))
        FileHandle.standardOutput.write(Data("\(name)\n".utf8))
    }

    /// Scrolls the tallest scroll view in the hierarchy, so that anything which
    /// only happens part-way down — a pinned header, content passing under it —
    /// can actually be seen. SwiftUI's ScrollView is an NSScrollView underneath.
    @discardableResult
    private static func scrollDown(_ view: NSView, by amount: CGFloat) -> Bool {
        var found: [NSScrollView] = []
        func walk(_ view: NSView) {
            if let scroll = view as? NSScrollView { found.append(scroll) }
            for subview in view.subviews { walk(subview) }
        }
        walk(view)

        // The tallest content is the one worth scrolling: in the window the day
        // column holds the library, while the calendar beside it barely moves.
        guard let scroll = found.max(by: {
            ($0.documentView?.bounds.height ?? 0) < ($1.documentView?.bounds.height ?? 0)
        }) else { return false }

        // `scroll(to:)` does not clamp: ask for more than there is and it goes
        // straight past the end into blank space, which looks exactly like a
        // view that failed to draw.
        let travel = (scroll.documentView?.bounds.height ?? 0) - scroll.contentView.bounds.height
        scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, min(amount, travel))))
        scroll.reflectScrolledClipView(scroll.contentView)
        return true
    }

    /// Prints what any pop-up menu in the hierarchy actually offers.
    private static func describeMenus(in view: NSView) {
        if let popup = view as? NSPopUpButton {
            let titles = popup.itemArray.map { item -> String in
                if item.isSeparatorItem { return "──" }
                return item.title.isEmpty ? "(blank)" : item.title
            }
            let line = "menu: " + titles.joined(separator: " | ") + "\n"
            FileHandle.standardOutput.write(Data(line.utf8))
        }
        for subview in view.subviews { describeMenus(in: subview) }
    }

    private static func render(_ view: some View, to path: String) {
        // A ScrollView needs a definite height to lay out; the real popover
        // gets one from its contentSize, so give the renderer the same. The
        // ground goes on outside the frame, so a view shorter than the popover
        // leaves dark space rather than white bands.
        let renderer = ImageRenderer(
            content: view
                .frame(width: Theme.popoverWidth, height: Theme.popoverHeight, alignment: .top)
                .background(Theme.ground)
        )
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}

/// Stand-ins so rendering never schedules or registers anything.
struct NullNotifier: Notifier {
    var supportsActions: Bool { false }
    func requestAuthorization() async throws -> Bool { false }
    func show(_ request: NotificationRequest) async throws {}
    func cancel(ids: [String]) async {}
    var actionEvents: AsyncStream<NotificationActionEvent> { AsyncStream { $0.finish() } }
}

struct NullLaunchAtLogin: LaunchAtLogin {
    var isEnabled: Bool { false }
    func setEnabled(_ enabled: Bool) throws {}
}
