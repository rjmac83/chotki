# chotki — build checklist

Ordering principle: **de-risk before you invest, and keep the port cheap.**

Two things get proven before features are built on them. First, that a notification with actions actually delivers from an ad-hoc-signed bundle. Second, that `core/` compiles and tests on Linux — because a portable core that is never built on another platform is not portable, it is only intended to be.

Marked **[manual]** where a step needs a human — a decision, a system permission, or an account.

---

## Phase 0 — Prerequisites

- [x] Verify SwiftUI + UserNotifications compile against Command Line Tools only. Confirmed 2026-08-19, SDK 15.5, MenuBarExtra probe built clean. Xcode not needed.
- [x] Verify orthocal.info is reachable and returns usable JSON for both reckonings. Confirmed 2026-08-19.
- [x] Choose project location and split personal context out of the repo.
- [x] `brew install gh` (2.97.0), `gh auth login`. Done 2026-08-19.
- [x] Git identity set repo-locally. Done 2026-08-19.
- [ ] **[manual]** Confirm which reckoning your parish keeps. A named church supplies its calendar; no affiliation follows OCA on the New Calendar. Older saved churches are preserved.
- [x] `git init`, first commit, pushed to https://github.com/Orthobro83/chotki (public, MIT). Done 2026-08-19.

## Phase 1 — Foundations, and two spikes

Both spikes come first. Do not build on an unproven assumption.

- [x] SwiftPM workspace: `core/` package, `macos/` executable depending on it. Done 2026-08-19.
- [x] `macos/build-app.sh` — bundle, `Info.plist`, bundle ID `info.chotki.app`, `LSUIElement` true. Done 2026-08-19.
- [x] Ad-hoc code signing, verified by `codesign --verify`. Done 2026-08-19.
- [x] **SPIKE A PASSED** 2026-08-19. Authorization granted, notification delivered, and the "Mark complete" action called back through the core `Notifier` protocol. Ad-hoc signing is sufficient; no Developer ID needed for personal use.
- [x] **[manual]** Notification permission granted. Done 2026-08-19.
- [x] **SPIKE B PASSED** 2026-08-19. `core/` builds and tests on `swift:6.1` Linux in 43s. A `portability-guard` job greps `core/` for Apple-only imports and was verified to fail when an `import AppKit` was planted.
- [x] Eight-pointed cross drawn programmatically as a template `NSImage` — no asset pipeline, correct inversion in dark menu bars. Done 2026-08-19.
- [x] Launch at login via `SMAppService` behind the core `LaunchAtLogin` protocol. Verified 2026-08-19 — registered and confirmed in `sfltool dumpbtm` and login items.

Proof: **met in full 2026-08-19.** All four CI jobs green. Notification with a working action round-tripped. Launch at login registered and verified.

> **Resolved 2026-08-19.** `macos/install.sh` installs to `/Applications` and launches from there, and the app re-asserts its login item from wherever it is actually running — so moving it off the external drive fixes the registration by itself.

## Phase 2 — Core: store and recurrence engine

No interface in this phase. Semantics first, and every line of it portable.

- [x] Storage behind a `Store` protocol. `InMemoryStore` and `SQLiteStore` (raw SQLite C API — GRDB dropped, see design.md). Done 2026-08-19.
- [x] Versioned migrations; `rule`, `activation`, `occurrence` tables with a `UNIQUE(rule_id, date)` constraint making one-deviation-per-day structural. `liturgical_day` lands in Phase 3. Done 2026-08-19.
- [x] `RecurrenceEngine` — pure, deterministic, storage-free. Done 2026-08-19.
- [x] `EditPlanner` returns an `EditPlan` of mutations, applied atomically by `SQLiteStore.apply`. Done 2026-08-19.
- [x] Pause is inclusive of the day it happens; resume opens a fresh stretch and the gap is unscored. Done 2026-08-19.
- [x] `exportJSON` / `importJSON`, round-trip tested across both stores. Done 2026-08-19.
- [x] Test suite covering:
  - [x] Monthly on the 31st clamps to the last day — all 12 months produce exactly one occurrence
  - [x] Both DST transitions, every day of March/October/November, in three time zones. Nonexistent times refused rather than silently shifted
  - [x] Leap day, including the full Gregorian century rule
  - [x] A rule taken on today invents no history behind it
  - [x] A paused stretch is absent from the due set entirely
- [x] CI runs the suite on macOS and Linux. 51 tests. Done 2026-08-19.

Proof: **met 2026-08-19.** 51 tests green on macOS and Linux.

## Phase 3 — Core: liturgical layer

- [x] `Jurisdiction` — name plus reckoning, with a non-authoritative list of common jurisdictions. Originally defaulted to Julian (2026-08-19); since 2026-10-02, no affiliation follows OCA on the New Calendar and older saved churches are preserved.
- [x] `OrthocalClient` behind an `HTTPFetching` seam, `FoundationNetworking` imported conditionally for Linux. Done 2026-08-19.
- [x] `LiturgicalService.refresh` fetches the window and skips what is already held. Done 2026-08-19.
- [x] Cache-first, with an in-memory snapshot so `LiturgicalDayProvider` stays **synchronous** — the recurrence engine never awaits. `refresh` never throws; failure sets `isOffline` for the interface to reflect. Done 2026-08-19.
- [x] Liturgical recurrence types: fast days, seasons, great feasts — gated on `ObservanceSettings`, done 2026-08-19 in Phase 2.
- [x] `LiturgicalService` conforms to `LiturgicalDayProvider`, driving liturgical recurrences from cached data. Done 2026-08-19.
- [x] **Improved on the plan:** switching re-targets rather than deleting. A cached Julian day stays a correct Julian day, so switching back costs no requests. `clearLiturgicalCache` remains for a manual refresh. Done 2026-08-19.
- [x] Ten recorded fixtures in the test bundle. The suite makes no network request. Done 2026-08-19.

Proof: **met 2026-08-19.** 13 Jan 2027 decodes fast-free (Leavetaking of the Nativity) on the Old Calendar and a fast on the New. Offline refresh returns nothing, throws nothing, and cached days still answer. 71 tests green on macOS and Linux.

> Discovered building this: the API takes a **civil** date in the URL but reports the date in the requested reckoning in the body — `/api/julian/2027/1/13/` answers with 31 December 2026. The cache is keyed on the civil date; keying on the reported date would misfile every Old Calendar day by thirteen days.

## Phase 4 — Core: scheduling

- [x] `Scheduler` — pure, no sleeping, no platform. Done 2026-08-19.
- [x] 10-minute lead for timed rules, exempt from quiet hours by design. Done 2026-08-19.
- [x] Up to four reminders for untimed rules, spread across the waking day by default; `ReminderPolicy.hourly` keeps the original cadence. Done 2026-08-19.
- [x] Quiet hours, default 21:30–06:30, applied to unsolicited repetition only. Done 2026-08-19.
- [x] `Notifier` protocol with `supportsActions`, defined in Phase 1 and driven by the scheduler. Done 2026-08-19.
- [x] `cancellationIDs` covers every reminder armed for a day; completed, late, skipped, cancelled, moved and archived all silence it. Done 2026-08-19.
- [x] `Clock` protocol with `FixedClock`; the whole suite runs in milliseconds with no desktop. Done 2026-08-19.

Proof: **met 2026-08-19.** A simulated August produces 31 morning reminders, 5 Sunday Liturgy reminders, 124 untimed reminders, and not one inside the quiet window. 112 tests green on macOS and Linux.

## Phase 4b — Education (core done, interface pending)

- [x] `GlossaryEntry`, `Glossary` index, category browsing, ranked search. 49 entries covering everything the app displays. Done 2026-08-19.
- [x] `Glossary.scan` — longest-match, word-boundary, non-overlapping term detection over arbitrary text. Done 2026-08-19.
- [x] Cross-references tested to resolve, so the pane can never show a dead link. Done 2026-08-19.
- [x] Terms screen, reachable from anywhere a term appears, with a way back. Done 2026-08-19.
- [x] Browse by category and search. Done 2026-08-19.
- [x] `TermText` links terms in the commemoration and the fasting description. Applied to short text only — linking a whole scripture passage would make it harder to read, not easier. The index arithmetic is tested. Done 2026-08-19.
- [ ] **[manual]** Have a priest read the glossary content. It is introductory, not authoritative.

## Phase 4c — Reminder controls (core done, interface pending)

- [x] Master switch for notifications. Done 2026-08-19.
- [x] Per-rule enable/disable, independent of whether the rule is scored. Done 2026-08-19.
- [x] Lead times: at the time, 10 / 30 minutes, 1 / 2 hours, the evening before. Done 2026-08-19.
- [x] Several leads on one rule, each with its own id; cancellation covers all of them. Done 2026-08-19.
- [x] Schema migration v3, with the upgrade path tested against a database built as version 2. Done 2026-08-19.
- [x] Settings interface for the master switch and the default lead. Done 2026-08-19.
- [x] Per-rule reminder controls in the editor: on/off and multiple lead times. Done 2026-08-19.

## Phase 5 — macOS interface

- [x] Popover at 400pt, three-tab chrome. Done 2026-08-19.
- [x] Month grid with fast, feast and Sunday shading, today marked. Done 2026-08-19.
- [x] Day list with completion, timed rules above untimed. Done 2026-08-19.
- [x] Add and edit as in-popover screens (not sheets — see design.md), with note and source fields. Done 2026-08-19.
- [x] Rule library, 24 templates grouped by category, nothing on by default, scoped by tradition. Done 2026-08-19.
- [x] Observance settings, three plain options, no justification prompt. Done 2026-08-19.
- [x] Fasting described, never prescribed — "the calendar marks this as…", plus "customarily set aside". Done 2026-08-19.
- [x] Right-click quick menu on an `NSStatusItem`: mark the next rule kept, silence reminders, open, quit. Done 2026-08-19.
- [x] Optional old-style date line under the month name. Done 2026-08-19.
- [x] `ReminderDriver` ticks the core scheduler in process and drives `MacNotifier`; banner actions route back to the model. Done 2026-08-19.

Proof: **partly met 2026-08-19.** The interface builds, runs, and renders correctly offscreen against real cached liturgical data — verified for the rule tab, library and settings. Two Phase 5 bugs were found and fixed this way: Sunday shading depended on the liturgical cache being loaded, and the render harness lost data by copying the database without its WAL.

**Still to do — [manual]:** an interactive walkthrough. Take a rule on, keep it, edit it, pause it, resume it, and confirm a banner action clears the pending reminders. Controls could not be verified by rendering, because `ImageRenderer` does not draw AppKit-backed pickers and toggles.

## Phase 6 — Core + interface: progress

- [x] `ScoringEngine` over activation-intersected, elapsed occurrences. Done 2026-08-19.
- [x] Full weight for 30 days, then halving every 60 — old days decay but never vanish. Done 2026-08-19.
- [x] Per-rule streaks that step over stood-down days rather than breaking on them. Done 2026-08-19.
- [x] `Prose` — names the rule, the count, and a weekday pattern when every slip shares one. Never invents a pattern from a single slip. Done 2026-08-19.
- [x] Progress tab plus a detachable 90-day report window. Done 2026-08-19.
- [x] Setting hides the figure; the prose remains. Done 2026-08-19.

Proof: **met 2026-08-19.** Both properties are tested directly, along with: a day still ahead is never counted as missed, nothing due yet yields no figure rather than a zero, keeping something late earns partial credit, and a recent slip weighs more than an old one without the old one vanishing.

The Tone constraint is enforced by a test that renders six different shapes of report — nothing due, all kept, all late, all stood down, partial, sporadic — and asserts none of them contains failure, comparison, or shaming language.

Rendered check: the summary reads "Evening prayers slipped four times, all on Fridays. Read the day's Gospel slipped once. Everything else held." with the figure secondary and the per-rule breakdown showing 25 of 25 for a rule with four stood-down days.

## Phase 5b — A full app as well as a menu bar app

- [x] `showInDock` setting, switching activation policy live. Done 2026-08-19.
- [x] Main window with a sidebar; month grid beside the day's rules. Done 2026-08-19.
- [x] Dock icon drawn programmatically, like the menu bar template image. Done 2026-08-19.
- [x] Main menu including a working Edit menu. Done 2026-08-19.
- [x] Dock icon reopen brings the window back. Done 2026-08-19.
- [ ] **[manual]** Walk the window: sidebar sections, the wider Rule layout, and editing text with keyboard shortcuts.

## Phase 7 — Reading tab and polish

- [x] Commemoration, tone, readings with passage text. Done 2026-08-19.
- [x] Cached-state marker on the reading tab. Done 2026-08-19.
- [x] 36 bundled passages, all from the Ante-Nicene and Nicene & Post-Nicene Fathers series or early Desert Fathers translations, one per day by day-of-year. A test rejects any source naming a modern translation still in copyright. **[manual]** Attributions await a priest's review before the app goes beyond personal use. Done 2026-08-19.
- [x] First-run onboarding offering three rules, with "start with nothing for now" as an equal option. Done 2026-08-19.
- [x] Prayer rope: 33/50/100, click or space, one dot per knot, with a synthesised chime on completion and a soft click per knot. Counts and nothing else — no timing, no record, no score. Done 2026-08-19.
- [ ] **[manual]** Walk a clean install end to end, from first launch to first kept rule.

Proof: clean install to first kept rule, walked end to end.

## Later — the port

Not scheduled. Listed so the shape is known while macOS is being built.

- Windows: WinUI or Win32 tray, ICO icon, toast notifications with actions, `LaunchAtLogin` via registry Run key.
- Linux: GTK tray via StatusNotifierItem, libnotify, `.desktop` autostart entry. GNOME needs a shell extension for any tray app — a platform limitation, not something the stack choice can fix.
- Everything in `core/` is expected to be reused unchanged. Anything that is not, is a bug in the core/UI boundary.

## Glossary entries still to write `[manual]`

newcomer will not know, where the definition is a matter for Ryan and a priest
rather than for me.
`GlossaryCoverageTests` keeps this list and this file in step — a term cannot be
dropped from the test without also being dropped from here.

- **Catholic** — the sharp one. In the Creed it means universal, and a newcomer
  reads it as Roman Catholic every time. Currently unexplained in "one holy
  catholic and apostolic Church".
- **Apostolic** — the other half of that phrase.
- **Church** — capital-C, as distinct from a building.
- **Abba** — the monastic title, in the passages from the desert fathers.

## Calendar refresh (added 6 October 2026)
- [ ] **By 31 December 2030:** ship a build whose bundled calendar runs past 2031 (the shipped one ends
      2031-12-31). See `core/Tools/CALENDAR.md`. Run `core/Tools/accuracy-check.py` before every release.

## Pause, stand down, and Reset record — due on every other platform (added 24 October 2026)

**Done on macOS only.** Android, iOS and Linux must all follow (Windows too, if its port has reached the day's cards). Flagged here and in the assistant's memory so it is raised at the start of each session until it is done.

What macOS now does, which the others must match (core is the specification; the Kotlin port needs the same decisions and tests):

- **Greyed, marked cards.** A paused rule stays on Home, greyed and marked "Paused", on the days it would have fallen; a day stood down is greyed and marked "Stood Down". "Pause This Rule" and "Stand Down for This Day" are ticked items in the right-click / long-press menu, and choosing a ticked one undoes it. "Resume This Rule" is no longer a separate item.
- **Core additions.** `AppSettings.pausedRuleIDs` (optional, no migration), `Practice.pauseDay(of:)`, `isOnPause(_:on:)`, `isPausedAndNotAsked(_:on:)`, `pausedEntries(on:)`, `entriesIncludingPaused(on:)`, `rulesNotOnPause(on:)`, `pausePlan(for:on:)`, `standDownLiftedOnResume(for:on:)`, `RecordReset`.
- **What a pause does to the record.** Days before the pause stay as recorded. The day it is paused counts if it was kept; if it was due and nothing was recorded, pausing stands that day down, so it can never read as a miss. Days between pausing and taking it back are outside the stretch and are never counted. The day it is taken back, and every day after, counts. Pausing and undoing on the same day leaves the day as it was. A paused rule is not reminded of and does not keep a day from being settled.
- **Reset record.** A quiet button with a reset icon beside "Open in a window" on the Progress view. It asks "Are you sure?" with "This will completely erase your record and cannot be undone." and Yes / Cancel. It erases every recorded day, starts every rule in force again from today (so nothing in the past can read as a miss), keeps a paused rule paused, drops rules that had only ended, and deletes the automatic backups so "cannot be undone" is true. Backups the person exported themselves are not touched.

Per platform:

- [x] **macOS** (build 34)
- [ ] **Android:** port the core additions and tests; grey the card; ticked Pause / Stand Down in the long-press menu; Reset record
- [ ] **iOS:** the same
- [ ] **Linux:** the same, when that port exists
- [ ] **Windows:** the same, if the port has reached the day's cards

Once mobile follows, `PortParityTests.everyPlatformOffersTheSameActions` can drop its macOS exception for "Resume this rule".
