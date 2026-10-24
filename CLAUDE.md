# Working on Chotki

Read this before changing anything. It is the orientation document; `design.md`
holds the reasoning, `checklist.md` the build order, and `context.local.md` the
personal context (gitignored — never commit it, never quote it publicly).

`retrospective.md` is the other one to read first: what went wrong building the
macOS app, which assumptions caused it, and the working rules that came out of
it. The section below on mistakes is the short version; the retrospective says
why they happened. `android/` holds the port plan and the specification the
Kotlin reimplementation is written against.

## What this is

An app for keeping an Orthodox prayer rule and honestly measuring whether
it is kept, on macOS, Android, and iOS. macOS has a menu bar popover **and** a
full window with a Dock icon. Written for Ryan; Android and macOS are published
as 1.0 beta, build 31 at
`github.com/rjmac83/chotki` for a private community to test.

## Where things are

| | |
|---|---|
| Project and repo | The vault, on an **external drive** — check it is mounted before anything else |
| His live data | `~/Library/Application Support/Chotki/chotki.sqlite` (+ `-wal`, `-shm`) |
| Daily backups | `~/Library/Application Support/Chotki/backups/` |
| Installed app | `/Applications/Chotki.app` |
| Liturgical data | Shipped in the app for 2026–2031 on macOS, iOS, Windows and Android (`core/.../Resources/calendar/`, built by `core/Tools/calendar-bundle.py`); `orthocal.info` — free, no key, the only network call any version makes — answers later dates |

`core/` is a pure SwiftPM package: Foundation and SQLite only. CI builds and
tests it on Linux every push, and a guard job fails the build if it ever
imports AppKit, SwiftUI, UserNotifications or similar.

`macos/` should hold only what is genuinely platform-specific: views, the
notifier, launch at login, the menu bar and window, the timer that drives
reminders, sound playback, icon drawing. **Anything that decides something
belongs in core.** `Practice` answers what is due on a day, whether a day is
settled, whether a rule is paused, and which repairs a loaded record needs.
`ReminderTicker` decides what to show and what to withdraw. If a new type in
`macos/` imports nothing from Apple, it is in the wrong place.

Two exceptions, deliberate: `ReminderDriver` (a `Timer` on a run loop) and
`SettingsStorage` (the Application Support path and the old `UserDefaults`
migration). Both import only Foundation, but both are platform glue rather
than decisions — what they used to decide now lives in `ReminderTicker` and
the `Store` — so do not move them.

### On porting

Swift runs properly on Windows and Linux, so those ports inherit `core`
unchanged and rewrite only the interface. **Swift does not run on Android in
any practical way** — an Android version means a Kotlin reimplementation.

That makes core more important, not less. Core plus its test suites is the
*specification* a reimplementation is written against — inventoried, with the
parity gate, in `android/PARITY.md`, and sequenced in `android/PORT.md`: every decision stated
once, with tests that say what it must do. Behaviour left in the platform layer
has to be rediscovered by whoever writes the port, and it is exactly the layer
where every bug found by hand has been.

## Constraints that are not negotiable

These are enforced by tests, not left to judgement. Read the corresponding
sections of `design.md` before touching anything near them.

- **Encouraging, never shaming.** No red, no "failed", no broken-streak
  language, no comparison against a target or a better past self. Pausing
  removes days from the record rather than counting them against anyone. If a
  change would make this feel more like a habit-streak tracker, it is wrong
  however well it tests.
- **The app never congratulates anyone for praying.** Keeping a day is answered
  with thanksgiving — "Glory to God for all things" — not applause.
- **Descriptive, never prescriptive.** The app reports what the church calendar
  marks and names who to ask. It never tells anyone what they must do, and never
  issues dietary instruction.
- **Nothing is enabled by default.** Taking a rule on is always deliberate.
- **Participation is never assumed.** Fasting and feasts are each
  hidden / shown / observed, defaulting to *shown*. People have health
  conditions and no parish within reach; neither is a failure.
- **Text from the calendar is never re-cased.** App headings use proper casing;
  orthocal's words are shown as it writes them.

## Building, installing, verifying

```bash
cd macos && swift build          # or ./build-app.sh release
./install.sh                     # builds, installs to /Applications, launches
```

**Always use `install.sh`.** Building into `dist/` and then launching
`/Applications` leaves someone testing yesterday's binary — that has already
happened and cost a whole exchange.

Tests: `swift test` in both `core/` and `macos/` (453 core and 84 Mac tests as of 6 October 2026, counting Swift Testing's total; the
3 October figure of 474 core was not reproducible). CI runs
core on macOS and Linux, the portability guard, and the macOS suite.

### Looking at the interface

**Reach for `CHOTKI_RENDER_WINDOW=<prefix>` first.** It puts the real
`MainWindowView`, and then the real `RootView` at popover size, into an
off-screen `NSWindow` and asks the view hierarchy to draw itself. Because that
goes through AppKit rather than `ImageRenderer`, it draws **ScrollView contents
and real AppKit controls** — which is most of this app. It also prints the items
of every pop-up menu it finds (`menu: ...`), the one thing no screenshot can
show. It draws the view; it never reads the display.

`CHOTKI_RENDER=<prefix>` is the older path: `ImageRenderer` on content views in
isolation. Still useful for a single view in a known state, but it draws every
scrolled screen as an empty panel, which is how a missing feature once got
signed off here. Use synthetic practice and committed public calendar fixtures only, as required
by `project-rules.md`. Never open or copy the live database for previews.
`CHOTKI_EXPORT_ICON=<dir>` writes the iconset.

**What neither can do:**

- `ImageRenderer` (`CHOTKI_RENDER`) draws no `ScrollView` contents and no AppKit
  controls. That is why each screen is split into `XView` (scroll chrome) and
  `XViewContent`.
- **Neither is the live app.** They prove layout and copy. They cannot prove
  clicking, typing, notifications, or that a view is reachable at all. An
  animation or a `ScrollViewReader` scroll may simply not appear — if it does
  not, that is not evidence either way, so do not ship it on the strength of a
  render.

## Mistakes already made here — do not repeat them

- **Verified a hand-composed view instead of the real one.** Rendering
  `ZStack { Backdrop; Content }` proved the marks drew, and said nothing about
  whether any screen used them. The window had none. Render the *actual* view.
- **Two surfaces, one fix.** The popover and the window are different view
  trees. A change to one is not a change to both — the navigation buttons and
  the marks were each dead in the window while working in the popover.
- **Tests wrote to his real machine** twice: preference files in
  `~/Library/Preferences`, and an empty backup into Application Support.
  Anything a test constructs must be told not to touch the world.
- **A screenshot nearly carried his private data** into a public README. The
  current render harness uses synthetic practice and committed public calendar fixtures.
- **Never run the Intel slice on his Mac.** The release is universal; the
  x86_64 half must never be launched here — no `arch -x86_64`, no Rosetta, not
  once to see whether it starts. Forcing it raises a Rosetta install prompt on
  his machine, and a second Chotki opens his live record alongside the copy he
  is already using: one SQLite database, two writers. Verify that half
  statically — `lipo -archs`, and the CI job that fails a release bundle missing
  a slice. That it has never been executed anywhere is said plainly in the
  README and the release notes; that is the honest position, not a gap to close
  quietly. He may ask for an emulator run later.
- **The render harness opened his live database — and `SQLiteStore(path:)`
  migrates on open.** `seededStore()` read the liturgical cache straight out of
  `~/Library/Application Support/Chotki/chotki.sqlite`, under a comment saying
  the original is never opened for writing. It was: every render run applied
  whatever migrations the working copy had and the installed app did not. Caught
  on 1 September 2026, when schema 7 turned up in his record before the build
  carrying it had ever been installed. Nothing was lost, because that migration
  only added — the next one that rewrites or drops a column would not have been
  so forgiving. The subsequent 30 September rule prohibits even copying live data for
  previews: use synthetic practice and public fixtures. **Treat opening a store as a write.**
- **Never screen-capture his display.** It caught a private messaging window
  once. Use the render harness.
- **Python edits that do not assert fail silently.** Several patches quietly
  no-oped and looked successful. Always `assert old in s`.
- **Never mask build output.** `>/dev/null` hid a failing build and shipped a
  stale bundle.
- **A new file in `core/` is invisible to the `macos/` build.** SwiftPM caches
  the dependency's source list, so the build compiles ChotkiCore *without* the
  new file and reports `cannot find 'X' in scope` for a public type that is
  plainly there. `swift package --package-path macos clean` fixes it; touching
  `Package.swift` does not.
- **The database is WAL mode.** A file-level copy must include `-wal` and
  `-shm` or it silently loses recent data.

## State as of 3 October 2026

Three platforms, all in daily testing by Ryan.

| | |
|---|---|
| macOS | 1.0 beta, build 34 (24 October 2026); universal (arm64 + x86_64), Developer ID signed and **notarised** DMG via `macos/release-dmg.sh`; Intel slice never run |
| Android | 1.0 beta, build 31; sideload, signed with his own key; ships the calendar |
| iOS | 1.0 beta, build 31; redesigned phone interface, free provisioning for seven days, no public download |

**Published is not delivered.** The author hands builds to people himself.
Do not infer that a named person has a build from its publication.

Outstanding, in rough priority:

1. **Notarisation** — **done for macOS** (24 October 2026): the DMG is Developer
   ID signed, notarised and stapled. What remains is iOS, which still cannot reach
   TestFlight from here, so the iOS build cannot yet be handed to anyone else.
2. **A priest's review** of the glossary and the patristic attributions. He has
   said this will happen before the app goes further.
3. **Landscape remains outstanding despite the beta release.** Asked for on 26 August: the phones
   are portrait-locked, and the landscape layout for a phone or a tablet should
   be *the macOS layout* rather than a third design. macOS is already the wide
   arrangement — sidebar, calendar and the day side by side — so this is
   choosing between two existing layouts on width, not drawing a new one.
   Nothing about it is started.
4. **Confirming the reckoning** with his parish. A person who has not named a
   church follows the OCA, on the New Calendar. A named church follows that
   church. See `church-practice.md`. This is confirmation rather than a blocker.
5. **A Linux port** — **deferred by Ryan on 26 August 2026**, deliberately. Not
   until beta builds are with a wider set of users and their feedback is coming
   in; it is an afterthought and a light-week job, not a next step. Do not
   propose starting it. See the note below for what it would cost when he does.

Done since, and no longer outstanding:

- **The universal binary.** `swift build --arch arm64 --arch x86_64` works with
  Xcode installed; it took one line in `build-app.sh`. Release builds are
  universal, debug builds stay single-arch, and CI fails if a release bundle
  loses a slice.

### What a Linux port would actually cost

`core/` runs on Linux today — CI builds and tests it there every push, and
`HTTPFetching` already imports `FoundationNetworking` conditionally. Every seam
a platform has to fill is a named protocol: `Notifier`, `LaunchAtLogin`,
`Store`, `Clock`, `HTTPFetching`. The bell and the tick are *synthesised* in
core (`Sound/BellTone.swift`); only playback is platform.

So the port is not the app. **The port is the views, and SwiftUI does not exist
on Linux** — all ~4,000 lines of it would be rewritten against GTK or similar,
the way Android's Kotlin reimplementation was. iOS is the better guide to size
than macOS: the same screens came to 2,800 lines there once the platform
wiring was excluded.

Skipping the tray is right and removes the worst of it: `checklist.md` already
records that GNOME needs a shell extension for any tray app at all, which no
stack choice fixes. A plain windowed app runs the same on GNOME, KDE and XFCE,
because GTK is a library rather than a desktop dependency.

**Do not repeat the "you would be building blind" objection.** It was mine, and
it was wrong once the tooling was checked. There is no Docker, Podman, Colima or
Lima on this machine, so CI is the only Linux available *by default* — and CI
proves a thing compiles, never that it works, which is the wrong half for a
port whose every bug has been an interface bug. But **UTM is installed**, and
`/Applications/UTM.app/Contents/MacOS/utmctl` carries `exec` (run a command in
the guest, exit code returned), `file push` / `file pull`, and `ip-address`.
With an Ubuntu guest that is a working loop, and SSH on top of it is more
ergonomic than `exec` for real work.

The point of the VM is not the shell. It is that a screenshot tool inside the
guest, copied back out, restores the look-at-it loop that every other platform
had — the loop that found the empty prayers screen on iOS and the clipped icon
on Android. Without it Ryan becomes the test harness at VM-boot latency; with
it, Linux is an ordinary port.

If it starts: ARM64 Ubuntu, not x86_64 (UTM runs ARM64 natively on Apple Silicon
and emulates x86_64 at a fraction of the speed; Swift ships official aarch64
Linux builds). Desktop, not server — a server image has no display server, and
no display server means no screenshots. Install `qemu-guest-agent` or `utmctl
exec` and `ip-address` do nothing. Key auth only: never handle his password,
and hand him anything needing `sudo` to run himself.

And the first move is still a spike, not a phase: prove a maintained Swift GUI
toolkit for Linux exists at all and can draw one real screen. Nothing else is
worth writing until that is answered, and it is the part most likely to sink it.

## Adding a prayer, a reading or any other text

New text brings its glossary with it. A word a newcomer would stop at needs an
entry; "so" does not, "Theotokos" does. `GlossaryCoverageTests` enforces it
mechanically — it scans everything bundled and fails on a term of art the
glossary cannot explain.

Spotting the gap is mechanical. **Writing the definition is not mine to do**:
what an entry should say about a religious term goes to Ryan or a priest. Put
the term in `awaitingAnEntry` and in `checklist.md`, which the same suite keeps
in step, so the debt is visible rather than buried in a test file.
