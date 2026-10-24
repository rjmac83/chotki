import AppKit
import SwiftUI

/// A native mouse surface for a rule card. SwiftUI's nested Button/contextMenu
/// combination inside the horizontally scrolling strip did not receive mouse
/// events in the installed app, despite its action passing direct-call tests.
@MainActor
struct RuleCardInteraction: NSViewRepresentable {
    struct MenuAction {
        let title: String
        /// Shown with a tick when the thing it does is already so. Choosing it
        /// then undoes it, which is what "unselect" means in a menu.
        var isOn = false
        let perform: () -> Void
    }

    let title: String
    let showsCompletion: Bool
    let showsExpansion: Bool
    let showsGlossary: Bool
    let menuActions: [MenuAction]
    let open: () -> Void
    let toggleCompletion: () -> Void
    let expand: () -> Void
    let openGlossary: () -> Void

    func makeNSView(context: Context) -> Surface { Surface() }

    func updateNSView(_ view: Surface, context: Context) {
        view.title = title
        view.showsCompletion = showsCompletion
        view.showsExpansion = showsExpansion
        view.showsGlossary = showsGlossary
        view.menuActions = menuActions
        view.open = open
        view.toggleCompletion = toggleCompletion
        view.expand = expand
        view.openGlossary = openGlossary
    }

    final class Surface: NSView {
        var title = ""
        var showsCompletion = false
        var showsExpansion = false
        var showsGlossary = false
        var menuActions: [MenuAction] = []
        var open: (() -> Void)?
        var toggleCompletion: (() -> Void)?
        var expand: (() -> Void)?
        var openGlossary: (() -> Void)?
        var menuPresenter: ((NSMenu, NSEvent) -> Void)?
        private var monitor: Any?
        private var pressedAt: CGPoint?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
                pressedAt = nil
            } else if monitor == nil {
                // SwiftUI's containing scroll document handles mouse events
                // before AppKit hit-testing reaches nested representable views.
                // Monitor only this card's visible rectangle, and consume the
                // event once it belongs to the card.
                monitor = NSEvent.addLocalMonitorForEvents(
                    matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown]
                ) { [weak self] event in
                    guard let self, event.window === self.window,
                          !self.isHiddenOrHasHiddenAncestor else { return event }
                    let point = self.convert(event.locationInWindow, from: nil)
                    let inside = self.bounds.contains(point) && self.visibleRect.contains(point)
                    switch event.type {
                    case .leftMouseDown:
                        guard inside else { return event }
                        self.pressedAt = point
                        return nil
                    case .leftMouseUp:
                        guard let start = self.pressedAt else { return event }
                        self.pressedAt = nil
                        guard inside, hypot(point.x - start.x, point.y - start.y) < 8 else { return nil }
                        self.mouseUp(with: event)
                        return nil
                    case .rightMouseDown:
                        guard inside else { return event }
                        self.rightMouseDown(with: event)
                        return nil
                    default: return event
                    }
                }
            }
        }

        override var acceptsFirstResponder: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func isAccessibilityElement() -> Bool { true }
        override func accessibilityRole() -> NSAccessibility.Role? { .button }
        override func accessibilityLabel() -> String? { title }
        override func accessibilityPerformPress() -> Bool { open?(); return true }

        enum Hit { case open, completion, expansion, glossary }

        func hit(at point: CGPoint) -> Hit {
            if showsCompletion && point.x >= bounds.width - 42 && point.y >= bounds.height - 42 {
                return .completion
            }
            if showsExpansion && point.x >= bounds.width - 36 && point.y <= 40 {
                return .expansion
            }
            if showsGlossary && point.x <= 125 && point.y <= 38 {
                return .glossary
            }
            return .open
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
        }

        override func mouseUp(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            guard bounds.contains(point) else { return }
            switch hit(at: point) {
            case .open: open?()
            case .completion: toggleCompletion?()
            case .expansion: expand?()
            case .glossary: openGlossary?()
            }
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 36 || event.keyCode == 49 { open?() }
            else { super.keyDown(with: event) }
        }

        override func rightMouseDown(with event: NSEvent) {
            let menu = makeMenu()
            if let menuPresenter { menuPresenter(menu, event) }
            else {
                let point = convert(event.locationInWindow, from: nil)
                // Show after this event is consumed. A menu opened while the
                // right button is still down can be dismissed by its matching
                // mouse-up before the user can choose an action.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                    guard let self, self.window != nil else { return }
                    menu.popUp(positioning: nil, at: point, in: self)
                }
            }
        }

        func makeMenu() -> NSMenu {
            let menu = NSMenu(title: title)
            for (index, item) in menuActions.enumerated() {
                if item.title == "—" { menu.addItem(.separator()); continue }
                let native = NSMenuItem(title: item.title, action: #selector(runMenuAction(_:)), keyEquivalent: "")
                native.target = self
                native.tag = index
                native.state = item.isOn ? .on : .off
                menu.addItem(native)
            }
            return menu
        }

        @objc private func runMenuAction(_ sender: NSMenuItem) {
            guard menuActions.indices.contains(sender.tag) else { return }
            menuActions[sender.tag].perform()
        }
    }
}
