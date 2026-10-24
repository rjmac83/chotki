import SwiftUI
import AppKit
import ChotkiCore

@main
struct ChotkiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // A menu bar app has no windows of its own. The status item is built by
        // the delegate, because SwiftUI's MenuBarExtra cannot tell a right click
        // from a left one and the quick menu needs that distinction.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var model: AppModel?
    private let reportWindow = ReportWindowController()
    private let mainWindow = MainWindowController()

    private func trace(_ line: String) {
        guard ProcessInfo.processInfo.environment["CHOTKI_TRACE"] == "1" else { return }
        let url = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Logs/chotki-trace.log")
        let entry = "\(Date().formatted(date: .omitted, time: .standard))  \(line)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile(); handle.write(Data(entry.utf8)); try? handle.close()
        } else {
            try? Data(entry.utf8).write(to: url)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        trace("launched, activationPolicy=\(NSApp.activationPolicy().rawValue)")
        if let path = ProcessInfo.processInfo.environment["CHOTKI_EXPORT_PHONE_ICON"] {
            IconExport.runPhone(to: path)
            return
        }

        if let directory = ProcessInfo.processInfo.environment["CHOTKI_EXPORT_MENUBAR"] {
            IconExport.runMenuBar(to: directory)
            return
        }

        if let directory = ProcessInfo.processInfo.environment["CHOTKI_EXPORT_ICON"] {
            IconExport.run(to: directory)
            return
        }

        if let prefix = ProcessInfo.processInfo.environment["CHOTKI_RENDER_WINDOW"] {
            RenderMode.runWindow(prefix: prefix)
            return
        }
        if let prefix = ProcessInfo.processInfo.environment["CHOTKI_RENDER"] {
            RenderMode.run(prefix: prefix)
            return
        }

        // A review launch carries its own fictional, in-memory record. This is
        // selected by an argument before StoreLocation or any live service is
        // constructed, so a reviewer can safely exercise the actual controls.
        let reviewSample = CommandLine.arguments.contains("--review-sample") ||
            (Bundle.main.object(forInfoDictionaryKey: "ChotkiReviewSample") as? Bool == true)
        let notifier: any Notifier = MacNotifier()
        if !reviewSample { Task { _ = try? await notifier.requestAuthorization() } }

        let store: any Store
        do {
            store = try reviewSample ? RenderMode.seededStore() : SQLiteStore(path: StoreLocation.databasePath())
        } catch {
            // Without a store there is nothing to show. Say so plainly rather
            // than launching into a broken window.
            presentFatal("Chotki could not open its database.\n\n\(error)")
            return
        }

        let model = AppModel(
            store: store, notifier: notifier,
            launchAtLogin: reviewSample ? NullLaunchAtLogin() : MacLaunchAtLogin(),
            storage: reviewSample ? .none() : SettingsStorage(),
            startsReminders: !reviewSample, writesBackups: !reviewSample,
            loadsCalendar: !reviewSample, isReviewSample: reviewSample
        )
        if reviewSample {
            model.selectedDate = CalendarDate(year: 2026, month: 8, day: 19)!
            model.visibleMonth = model.selectedDate
            try? model.liturgical.loadSnapshot(around: model.selectedDate)
            model.notice = "Review sample — fictional practice. Nothing here changes your Chotki record."
        }
        self.model = model
        // A launch is a process that was not running. Sleep, and a window
        // merely brought forward, are not launches and do not come through here.
        model.coldOpen = true
        model.openDetachedReport = { [weak self, weak model] in
            guard let self, let model else { return }
            self.reportWindow.show(model: model)
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: Theme.popoverWidth, height: Theme.popoverHeight)

        let hosting = NSHostingController(rootView: RootView(model: model))
        // Without this the hosting controller reports SwiftUI's preferred size
        // back to the popover, so a tab with little in it shrinks the window and
        // every other tab is left scrolling inside a window that never grew back.
        hosting.sizingOptions = []
        popover.contentViewController = hosting
        self.popover = popover

        // The Dock icon and window are optional; the menu bar item is not.
        applyDockPresence(model.settings.showInDock)
        model.onDockPresenceChanged = { [weak self] show in
            self?.applyDockPresence(show)
        }
        model.openMainWindow = { [weak self, weak model] in
            guard let self, let model else { return }
            self.popover?.performClose(nil)
            self.mainWindow.show(model: model)
        }
        if model.settings.showInDock {
            mainWindow.show(model: model)
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = CrossIcon.menuBarImage()
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        self.statusItem = item
        trace("policy=\(NSApp.activationPolicy().rawValue) windows=\(NSApp.windows.count) dockIcon=\(NSApp.applicationIconImage != nil) mainMenu=\(NSApp.mainMenu != nil)")
        trace("status item created, button=\(item.button != nil), screens=\(NSScreen.screens.count)")

        // Development affordance: open the popover at launch so the interface
        // can be inspected without a click. Never set in normal use.
        // A lid closed on the 28th and opened on the 29th. The reminder
        // timer does resume after sleep, but not necessarily at once, and
        // this is the case the whole fix is about — so ask on wake too.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [model] _ in
            MainActor.assumeIsolated { model.advanceDayIfNeeded() }
        }

        if ProcessInfo.processInfo.environment["CHOTKI_OPEN_AT_LAUNCH"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.togglePopover()
                // Activating the app could plausibly dismiss a transient
                // popover. Check it is still up a moment later.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    guard let self else { return }
                    let shown = self.popover?.isShown ?? false
                    let key = self.popover?.contentViewController?.view.window?.isKeyWindow ?? false
                    self.trace("after activation: shown=\(shown) keyWindow=\(key)")
                }
            }
        }
    }

    /// Switches between a full app and a menu bar accessory, live.
    private func applyDockPresence(_ show: Bool) {
        NSApp.setActivationPolicy(show ? .regular : .accessory)
        if show {
            NSApp.applicationIconImage = CrossIcon.appIcon()
            MainMenu.install()
        } else {
            NSApp.mainMenu = nil
        }
    }

    /// Clicking the Dock icon brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if let model, model.settings.showInDock { mainWindow.show(model: model) }
        return true
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showQuickMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            if mainWindow.isOpen { model?.navigationSurface = .window }
        } else {
            // A notice belongs to the moment it was raised. Without this,
            // "Backup written to…" sat there for the rest of the session.
            model?.notice = nil
            model?.reload()
            model?.navigationSurface = .companion
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // An accessory app's popover does not become key on its own, so text
            // fields silently swallow every keystroke — clicks work, typing does
            // not. Activating first is what makes the search field usable.
            NSApp.activate(ignoringOtherApps: true)
            popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
            trace("popover shown=\(popover.isShown) buttonWindow=\(button.window != nil) frame=\(button.window?.frame ?? .zero)")
        }
    }

    /// The quick menu: mark the next thing kept without opening anything.
    private func showQuickMenu() {
        guard let model, let item = statusItem else { return }
        let menu = NSMenu()

        let today = model.today
        let outstanding = model.outstandingEntries(on: today)

        if let next = outstanding.first {
            let mark = NSMenuItem(
                title: "Mark \"\(next.rule.title)\" as kept",
                action: #selector(markNextKept), keyEquivalent: ""
            )
            mark.target = self
            menu.addItem(mark)
            menu.addItem(.separator())
        }

        // Neutral phrasing, and never a count of what is outstanding.
        let summary = NSMenuItem(
            title: outstanding.isEmpty ? "Nothing further today" : "\(outstanding.count) still on today's rule",
            action: nil, keyEquivalent: ""
        )
        summary.isEnabled = false
        menu.addItem(summary)
        menu.addItem(.separator())

        let open = NSMenuItem(title: "Open Chotki", action: #selector(openFromMenu), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        if model.settings.showInDock {
            let window = NSMenuItem(title: "Open window", action: #selector(openWindowFromMenu), keyEquivalent: "")
            window.target = self
            menu.addItem(window)
        }

        let mute = NSMenuItem(
            title: model.settings.reminders.notificationsEnabled ? "Silence reminders" : "Turn reminders back on",
            action: #selector(toggleReminders), keyEquivalent: ""
        )
        mute.target = self
        menu.addItem(mute)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func markNextKept() {
        guard let model else { return }
        let outstanding = model.outstandingEntries(on: model.today)
        guard let next = outstanding.first else { return }
        model.toggleKept(next)
    }

    @objc private func openFromMenu() {
        togglePopover()
    }

    @objc private func openWindowFromMenu() {
        guard let model else { return }
        mainWindow.show(model: model)
    }

    @objc private func toggleReminders() {
        model?.update { $0.reminders.notificationsEnabled.toggle() }
    }

    private func presentFatal(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Chotki could not start"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.runModal()
        NSApp.terminate(nil)
    }
}
