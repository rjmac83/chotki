import SwiftUI
import AppKit
import ChotkiCore

struct RuleTabView: View {
    @ObservedObject var model: AppModel
    var pinsCalendar = false
    var compact = false
    var onOpenLibrary: (() -> Void)? = nil
    var body: some View {
        // The width has to come from the space the window actually gave this
        // column. Measuring the column after the cards have laid themselves
        // out reports that wider size back, and the page grows to match.
        GeometryReader { proxy in
            VStack(spacing: 0) {
                HomeCalendar(model: model, compact: compact)
                ScrollView {
                    DayPanel(model: model, compact: compact, onOpenLibrary: onOpenLibrary, viewportWidth: proxy.size.width)
                        .chotkiScrollContent()
                }.scrollContentBackgroundHidden().softVerticalScrollEdges()
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct RuleTabViewContent: View {
    @ObservedObject var model: AppModel
    var pinsCalendar = false
    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                HomeCalendar(model: model, compact: true)
                DayPanel(model: model, compact: true, viewportWidth: proxy.size.width)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
    }
}

struct DayAndLibrary: View {
    @ObservedObject var model: AppModel
    var inset: CGFloat = 0
    var masksAbove = false
    var body: some View { DayPanel(model: model) }
}

struct DayPanel: View {
    @ObservedObject var model: AppModel
    var compact = false
    var onOpenLibrary: (() -> Void)? = nil
    var viewportWidth: CGFloat = 0
    @State private var expandedRuleID: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var inset: CGFloat { compact ? 16 : 24 }
    private func openLibrary() {
        if let onOpenLibrary { onOpenLibrary() }
        else { model.screen = .library }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let day = model.liturgical.cachedDay(for: model.selectedDate) {
                if let title = day.title {
                    Text(title).font(Theme.reading(compact ? 13 : 15)).foregroundStyle(Theme.muted)
                }
                if model.rules.contains(where: \.isFastingRule), day.isFast,
                   model.settings.observances.fasting.isVisible {
                    VStack(alignment: .leading, spacing: 5) {
                        TermText(model: model, text: "The calendar marks this as \(day.fastDescription).",
                                 size: compact ? 13 : 15, serif: true, colour: Theme.violet)
                        if !day.abstentions.isEmpty {
                            Text("Customarily set aside: \(day.abstentions.joined(separator: ", ")).")
                                .font(.system(size: 12)).foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(Format.longDate(model.selectedDate)).font(.system(size: compact ? 14 : 16, weight: .semibold))
                Spacer(minLength: 8)
                if model.settings.showOldStyleDates {
                    let old = model.liturgical.cachedDay(for: model.selectedDate)?.observedDate ?? model.selectedDate.adding(days: -13)
                    Text("\(old.day) \(Format.shortMonth(old.month)) o.s.").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
            }.foregroundStyle(Theme.parchment)
            if model.entriesIncludingPaused(on: model.selectedDate).isEmpty {
                VStack(spacing: 14) {
                    Button { openLibrary() } label: {
                        Image(systemName: "plus").font(.system(size: 24)).padding(16)
                            .overlay(Circle().stroke(Theme.goldDim))
                    }.buttonStyle(.plain).foregroundStyle(Theme.gold).help("Open the Library")
                        .overlay { NativeClickRegion(action: openLibrary) }
                    Text(model.rules.isEmpty ? "Create Your First Rule" : "Nothing on the rule for this day.")
                        .font(Theme.reading(22)).foregroundStyle(Theme.parchment)
                }.frame(maxWidth: .infinity).padding(.vertical, 24)
            } else {
                HStack(spacing: 8) {
                    Text("Today's Commitments").foregroundStyle(Theme.muted)
                    Button("Add a New Rule") { openLibrary() }.buttonStyle(.plain).foregroundStyle(Theme.gold)
                        .overlay { NativeClickRegion(action: openLibrary) }
                }.font(.system(size: 12))
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(model.entriesIncludingPaused(on: model.selectedDate)) { entry in
                                EntryRow(model: model, entry: entry, expandedID: $expandedRuleID)
                                    .id(entry.rule.id)
                            }
                            Button { openLibrary() } label: {
                                Label("Add", systemImage: "plus").font(.system(size: 14))
                                    .frame(width: 120, height: 232)
                                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.goldDim, style: StrokeStyle(lineWidth: 1, dash: [4])))
                                    .contentShape(RoundedRectangle(cornerRadius: 22))
                            }.buttonStyle(.plain).foregroundStyle(Theme.gold)
                                .accessibilityLabel("Open the Library to Add a Rule")
                                .overlay { NativeClickRegion(action: openLibrary) }
                        }.padding(.vertical, 4).chotkiScrollContent().horizontalWheelScroll()
                    }.scrollIndicators(.hidden)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        .frame(width: viewportWidth > inset * 2 ? viewportWidth - inset * 2 : nil)
                        .onChange(of: expandedRuleID) { id in
                            guard let id else { return }
                            DispatchQueue.main.async {
                                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.42)) {
                                    proxy.scrollTo(id, anchor: .center)
                                }
                            }
                        }
                }
            }
            if let thanksgiving = model.thanksgiving {
                Text(thanksgiving).font(Theme.reading(16)).foregroundStyle(Theme.gold).transition(.opacity)
            }
            SayingCard(model: model, compact: compact)
        }.padding(.horizontal, inset).padding(.top, 8).padding(.bottom, 24)
            .onChange(of: model.selectedDate) { _ in model.clearThanksgiving(); expandedRuleID = nil }
    }
}

struct EntryRow: View {
    @ObservedObject var model: AppModel
    let entry: DayEntry
    @Binding var expandedID: UUID?
    @State private var flipped = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let ink = Color(red: 0.102, green: 0.098, blue: 0.086)
    private let mutedInk = Color(red: 0.37, green: 0.35, blue: 0.31)
    init(model: AppModel, entry: DayEntry, expandedID: Binding<UUID?> = .constant(nil)) {
        self.model = model
        self.entry = entry
        _expandedID = expandedID
    }
    private var expanded: Bool { expandedID == entry.rule.id }
    /// The rule is on pause as of this day: paused by the person, on or after
    /// the day it was paused.
    private var isPaused: Bool { model.isOnPause(entry.rule, on: entry.date) }
    /// Set aside, for the day or for good: shown greyed, and marked.
    private var isResting: Bool { isPaused || entry.isStoodDown }
    /// A day after the pause was never asked of anyone, so there is nothing to
    /// keep and no circle to tick.
    private var isAfterPause: Bool {
        model.pauseDay(of: entry.rule).map { entry.date > $0 } ?? false
    }
    private func setExpanded(_ value: Bool) { expandedID = value ? entry.rule.id : nil }
    private var category: RuleCategory? { entry.rule.category.flatMap(RuleCategory.init(rawValue:)) }
    private var summary: String {
        RuleLibrary.shared.templates.first { $0.title == entry.rule.title }?.summary ?? entry.rule.note ?? "A rule of your own."
    }
    private var glossarySlug: String? { entry.rule.glossarySlug }
    private var fastExplanation: String {
        if let reason = entry.dispensation { return "Not observed during \(reason)." }
        if let slug = glossarySlug,
           let entry = Glossary.shared(for: model.settings.jurisdiction.tradition).entry(slug: slug) {
            return entry.short
        }
        return summary
    }
    private var symbol: String {
        switch category {
        case .prayer: return "circle.hexagonpath"
        case .reading: return "book"
        case .fasting: return "cup.and.saucer"
        case .services: return "cross"
        default: return "pencil"
        }
    }
    private var recordedAttribution: String? {
        entry.rule.suggestedByLabel(currentFather: model.settings.spiritualFatherName)
    }
    private func measuredHeight(_ value: String, size: CGFloat, width: CGFloat) -> CGFloat {
        let font = Theme.readingFace.flatMap { NSFont(name: $0, size: size) } ?? NSFont.systemFont(ofSize: size)
        return ceil((value as NSString).boundingRect(
            with: NSSize(width: width, height: 10_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        ).height)
    }
    private var description: String { flipped ? fastExplanation : summary }
    var compactTitleSize: CGFloat {
        [18, 17, 16, 15, 14, 13, 12, 11].first {
            measuredHeight(entry.rule.title, size: CGFloat($0), width: 104) <= 68
        }.map(CGFloat.init) ?? 11
    }
    private var needsExpansion: Bool {
        let titleHeight = measuredHeight(entry.rule.title, size: compactTitleSize, width: 104)
        let descriptionHeight = measuredHeight(summary, size: 13, width: 104)
        let available = 232 - 28 - 20 - 13 - titleHeight - (recordedAttribution == nil ? 13 : 29) - 32
        return titleHeight > 64 || descriptionHeight > min(64, available) - 2
    }
    private var expandedHeight: CGFloat {
        let titleHeight = measuredHeight(entry.rule.title, size: 18, width: 272)
        let descriptionHeight = measuredHeight(description, size: 13, width: 272)
        return max(232, 28 + 20 + 13 + titleHeight + descriptionHeight +
                   (recordedAttribution == nil ? 13 : 29) + 40)
    }
    var body: some View {
        ZStack(alignment: .topTrailing) {
            if expanded {
                face(back: false, expanded: true).onTapGesture { open() }
            } else {
                ZStack {
                    face(back: false, expanded: false)
                        .opacity(flipped ? 0 : 1)
                        .rotation3DEffect(.degrees(flipped ? -180 : 0), axis: (x: 0, y: 1, z: 0))
                        .allowsHitTesting(!flipped)
                        .onTapGesture { open() }
                    face(back: true, expanded: false)
                        .opacity(flipped ? 1 : 0)
                        .rotation3DEffect(.degrees(flipped ? 0 : 180), axis: (x: 0, y: 1, z: 0))
                        .allowsHitTesting(flipped)
                        .onTapGesture { open() }
                }
            }
            if needsExpansion && !expanded {
                Button { setExpanded(true) } label: { Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(mutedInk)
                    .frame(width: 24, height: 24)
                }.buttonStyle(.plain).offset(x: -8, y: 195)
            }
            if flipped, let glossarySlug {
                Button { model.openGlossary(glossarySlug) } label: { Text("Learn More")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.goldDim).underline()
                    .frame(width: 112, height: 22, alignment: .leading)
                }.buttonStyle(.plain).offset(x: -6, y: 198)
                    .accessibilityLabel("Learn more about \(glossarySlug)")
            }
            if (!flipped || expanded) && !isAfterPause {
                Button {
                    model.toggleKept(entry)
                    if expanded { setExpanded(false) }
                } label: { ZStack {
                    Circle().fill(entry.showsAsSatisfied ? Theme.gold : .clear)
                    Circle().stroke(Theme.goldDim, lineWidth: 1)
                    if entry.showsAsSatisfied { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(ink) }
                }.frame(width: 21, height: 21).padding(10) }
                .opacity(isResting ? 0.55 : 1)
                .buttonStyle(.plain).accessibilityLabel(entry.isKept ? "Clear \(entry.rule.title) for this day" : "Mark \(entry.rule.title) kept")
            }
            RuleCardInteraction(
                title: entry.rule.title,
                showsCompletion: (!flipped || expanded) && !entry.isDispensed && !isAfterPause,
                showsExpansion: needsExpansion && !expanded,
                showsGlossary: flipped && glossarySlug != nil,
                menuActions: menuActions,
                open: open,
                toggleCompletion: {
                    model.toggleKept(entry)
                    if expanded { setExpanded(false) }
                },
                expand: { setExpanded(true) },
                openGlossary: { if let glossarySlug { model.openGlossary(glossarySlug) } }
            )
            .frame(width: expanded ? 300 : 132, height: expanded ? expandedHeight : 232)
            .zIndex(3)
        }
        .zIndex(expanded ? 1 : 0)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.42), value: flipped)
        .animation(reduceMotion ? nil : .spring(response: 0.48, dampingFraction: 0.82), value: expanded)
    }
    var menuActions: [RuleCardInteraction.MenuAction] {
        typealias Action = RuleCardInteraction.MenuAction
        var actions: [Action] = []
        if !entry.isDispensed {
            let destination: String
            switch entry.rule.reference {
            case .rope: destination = "Go to the Rope"
            case .prayers: destination = "Read the Prayers"
            case .reading: destination = entry.rule.title.lowercased().contains("life of the day") ? "Read the Saint’s Life" : "Read the Day’s Readings"
            case .psalter: destination = "Read Today’s Kathisma"
            default: destination = "Open"
            }
            actions.append(Action(title: destination, perform: openDestination))
            if needsExpansion { actions.append(Action(title: expanded ? "Collapse Card" : "Expand Card", perform: { setExpanded(!expanded) })) }
            if !isAfterPause {
                actions.append(Action(title: "—", perform: {}))
                actions.append(Action(title: entry.isKept ? "Clear This Day" : "Mark as Kept", perform: { model.toggleKept(entry) }))
                if !entry.isKept { actions.append(Action(title: "Mark as Kept, Late", perform: { model.markKeptLate(entry) })) }
                // Ticked while it is so; choosing it again lifts the stand-down.
                actions.append(Action(title: "Stand Down for This Day", isOn: entry.isStoodDown, perform: {
                    if entry.isStoodDown { model.clearOccurrence(entry) }
                    else { model.setStatus(.skipped, for: entry.rule, on: entry.date) }
                }))
            }
        } else {
            actions.append(Action(title: "Lifted by the Church Today", perform: {}))
        }
        if let slug = entry.rule.glossarySlug { actions.append(Action(title: "About This Rule", perform: { model.openGlossary(slug) })) }
        actions.append(Action(title: "—", perform: {}))
        actions.append(Action(title: "Edit Rule…", perform: { model.screen = .editor(entry.rule.id) }))
        // Ticked while the rule is paused; choosing it again takes the rule back.
        let paused = model.isPausedOnPurpose(entry.rule)
        actions.append(Action(title: "Pause This Rule", isOn: paused, perform: {
            if paused { model.resume(entry.rule) } else { model.standDown(entry.rule) }
        }))
        return actions
    }
    private func face(back: Bool, expanded: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(entry.rule.isFastingRule ? Theme.violet : Theme.goldDim)
                .font(.system(size: 15)).frame(height: 20)
            Text(category?.displayName ?? "Custom").font(.system(size: 11)).foregroundStyle(mutedInk)
            Text(entry.rule.title).font(Theme.reading(expanded ? 18 : compactTitleSize)).foregroundStyle(ink)
                .lineLimit(expanded ? nil : 4).fixedSize(horizontal: false, vertical: true)
                .layoutPriority(2)
            Text(back ? fastExplanation : summary)
                .font(Theme.reading(13)).foregroundStyle(mutedInk)
                .lineLimit(expanded ? nil : back ? 5 : 4)
                .fixedSize(horizontal: false, vertical: expanded)
            Spacer(minLength: 0)
            if !back {
                if let recordedAttribution {
                    Text(recordedAttribution)
                        .font(.system(size: 10)).foregroundStyle(mutedInk).lineLimit(expanded ? nil : 2)
                }
                Text(isPaused ? "Paused" : entry.isDispensed ? "Lifted Today" : entry.isStoodDown ? "Stood Down" :
                     entry.rule.timeOfDay.map { Format.time($0, model.settings.clockStyle) } ?? "All Day")
                    // The mark has to be readable through the greying, which is the
                    // whole point of it, so it is heavier than the time it replaces.
                    .font(.system(size: 11, weight: isResting ? .semibold : .regular))
                    .foregroundStyle(isResting ? ink : mutedInk).layoutPriority(1)
            }
        }.padding(14).frame(width: expanded ? 300 : 132,
                            height: expanded ? expandedHeight : 232, alignment: .topLeading)
            .background(Theme.parchment, in: RoundedRectangle(cornerRadius: 22))
            .contentShape(RoundedRectangle(cornerRadius: 22))
            // Greyed, not struck through and not red: setting a rule aside is a
            // legitimate act, and the card should look rested rather than failed.
            .saturation(isResting ? 0 : 1)
            .opacity(isResting ? 0.6 : 1)
    }

    func open() {
        if expanded { setExpanded(false); return }
        openDestination()
    }

    private func openDestination() {
        if entry.rule.isFastingRule { flipped.toggle(); return }
        if let id = entry.rule.ropePrayerID { model.openRope(counting: id); return }
        if let id = entry.rule.sequenceID { model.openRope(counting: id); return }
        switch entry.rule.reference {
        case .reading: model.openReading(band: ReadingOrder.band(ofTitle: entry.rule.title))
        case .psalter: model.screen = .psalter
        case .prayers: model.screen = .prayers(entry.rule.id)
        default: model.screen = .editor(entry.rule.id)
        }
    }
}

extension View {
    func scrollContentBackgroundHidden() -> some View { scrollContentBackground(.hidden) }
}
