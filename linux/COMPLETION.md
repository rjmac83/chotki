# Completing the Linux port

Written 2026-10-10, at the handoff from Codex. `linux/PORT.md` remains the record of Phases 0 and 1 and the original gates. This file is the plan for the work that is still open. Do not start a slice until the slice before it has met its gate.

## Where the work lives

- Working tree: `/Volumes/2TB/grok-vault/chotki-linux`
- Branch: local `linux`, created from `origin/codex/linux-port` at `0879899`
- Upstream: `origin/linux`. A plain push of this branch does not move `codex/linux-port`.
- Remote: `https://github.com/rjmac83/chotki.git`
- The `chotki-alpha` checkout stays on `main`. Its untracked design notes and mockups stay there.
- `codex/linux-port` stays at `0879899` until `linux` has been pushed and its Linux workflow is green. After that, the Codex branch is only a historical pointer.

The first commit on `linux` adds this branch to `.github/workflows/linux.yml` (the workflow currently runs on `main` and `codex/linux-port`) and is pushed with `git push -u origin linux`.

## Starting point

Phases 0 and 1 are done. An `amd64` `.deb` installs on a clean Ubuntu 24.04 runner, the helper reads the bundled core, and CI renders a review screenshot. Phase 2 has one real screen: Home. It shows a week, the selected day's commitments, completion, the bundled calendar's feast and fast cues, a settled-day mark, and the patristic saying on the daily artwork. Prayers, Reading, Progress, Library, Glossary, and Settings are labeled placeholders.

The macOS window is the reference for behavior and presentation. `core/` decides. QML draws and the Swift helper adapts. A screen that can be seen and cannot be used is unfinished.

## Rules that bind every slice

- Review runs and tests use the isolated review record. They never open `~/.local/share/Chotki` or the Mac record.
- The helper keeps calling `Practice`, `LiturgicalService`, `SQLiteStore`, and the other core types. New behavior goes into `core/` only when every platform should share it. A Linux-only shortcut in QML is a defect.
- The bundled calendar covers 2026–2031. orthocal.info is asked only outside that range, with the app's public User-Agent. Scripture is the bundled King James text.
- Reflections stay retired. Do not restore that route, its store tables, or its copy.
- The window is the product. Reminders, settings, navigation, and Quit work with no tray. A tray, if it is added at all, is a later optional menu and is never the only way in.
- There is no menu-bar companion. That is a Mac surface.
- The Linux label stays an alpha, independent of the Mac 1.0 beta build number, until Phase 5 says otherwise.
- Each slice updates `linux/PORT.md` with what was actually checked, and adds a bridge test or a Qt input test for the action it claims.

## Phase 2 — Finish the window

The Phase 2 gate in `PORT.md` still stands: a synthetic record can be created, edited, lived with for a day, exported, and restored through the window, and each screen has been reviewed beside the Mac at normal and scaled sizes.

Work in this order. Later slices depend on earlier destinations.

### 2.1 Bridge, before any new screen

The JSON boundary is already the right shape and it will not survive Library, the editor, and Reading as a pile of optional keys. Make it typed before it grows.

- Give requests and responses a small Codable schema in the helper, and a matching struct on the Qt side. Keep newline framing and the version field. Correlate each response with its request id. A late error must not clear a newer success.
- Reset the helper restart count when a `hello` succeeds. Today the third death in the life of the process gives up for good.
- Stamp `completedAt` when a rule is marked kept, as the Mac does. Unmarking still deletes the occurrence.
- A dispensed rule stays untoggleable. The error for that case says the day was not asked, which is different from a rule that is not on the day.
- Point `check_bridge.py` at a temporary review directory. The shared `~/.cache/chotki-linux-review` record is for human review, not for a test that writes.
- `--screenshot` fails if another review instance already holds the socket, and it waits until the snapshot fields are present, not merely until `hello` has returned.
- Add the missing Home icons for Fasting, Services, and Life.
- Show the whole saying. The card currently stops at two lines.
- Keep the fast-day color visible on the selected day.
- Add `linux` to the workflow branches and push the branch.

**Gate.** The existing Home actions still pass on Ubuntu 24.04 `amd64`: bridge check, sidebar and Home clicks, package install, and a screenshot that contains the sample commitments. A killed helper reconnects more than three times. The review test does not write the human review database.

**Checked on the ARM64 guest (2026-10-10):** the bridge test, including a temporary review directory, `completedAt`, and the dispensed-day refusal; the sidebar test; four helper deaths with a reconnect each time; an offscreen window that stayed up. The Ubuntu 24.04 `amd64` half of this gate is the GitHub workflow.

### 2.2 Prayers and the rope

Mac route: sidebar Prayers. With no prayer selected, the rope. A prayer rule opens `PrayerView` for that rule. The Psalter is a further page on this same route and is built with Reading.

- Draw the rope from `RopeCircleLayout` and play cues from `PrayerScreen.cue`. The platform draws and plays. It does not decide where a bead sits or which knots tock.
- Count knots, including the words on screen and the rope alone.
- Opening the app from a process that was not running plays the rope and the cross once. A second activation of an already-running instance does not. Reduced motion skips the mark.
- Morning and evening cards on Home will land here once 2.5 is done. The Jesus Prayer opens on the rope.
- The knot is complete. There is no applause.

**Gate.** A review record can count a prayer to its target, hear the bead cue, leave, and return to the same count. A Qt test clicks the rope and reads the new count back from the helper. Restarting the process plays the opening mark once.

**Checked on the ARM64 guest (2026-10-10):** the bridge test counted a prayer to 33, heard a tock on each bead and a bell on the last knot, refused a second knot inside the same second, and read the same count back after another request. Choosing the rope alone and the morning rule did not reset the count, and none of this wrote an occurrence. The Qt test clicked the rope, read 1 back from the helper, left for Home, returned to the same count, then heard the tock and the bell. The status line at the end is "the knot is complete". A new process showed the opening mark once; killing the helper did not play it again, and reduced motion did not play it. The sidebar test, four helper restarts, an offscreen window, and a 1100×860 review screenshot still passed. The Ubuntu 24.04 `amd64` half of this gate is the GitHub workflow.

### 2.3 Reading and the Psalter

Mac route: sidebar Reading, plus the Psalter reached from Prayers.

- Gospel, Epistle, Vespers, Matins, and the life of the day are separate sections. Opening a reading rule expands only the section it names.
- Scripture comes from the bundled King James file, paragraphs broken on the Bible's own marks, with a blank line between passages. No pilcrow.
- The life is the Prologue from Ochrid, shown for the observed church day, with the CC BY-SA 4.0 footer and the old-calendar and new-calendar dates. The text is not altered. There is no February 29 life.
- Completion of a reading is marked only after a deliberate scroll reaches the end of that section. Opening a disclosure does not count. Stood-down and dispensed days are left alone.
- The Psalter reads from `Psalter` in core, and a psalter rule completes through the same occurrence path as any other kept rule.

**Gate.** The review record can open each reading section, reach its end, and see that rule kept. A protocol test covers one scripture completion and proves a dispensed reading is not marked.

**Checked on the ARM64 guest (2026-10-10):** the bridge test opened Gospel, Epistle, Vespers, Matins, and the life, each by itself, and wrote no occurrence until a section was finished. Finishing the Gospel kept that rule and left the Epistle unmarked. A stood-down Epistle stayed stood down. The life carried the CC BY-SA 4.0 note and its calendar dates, and February 29 offered no life. On Bright Week the Wednesday and Friday fast stayed dispensed and unmarked, and the Psalter appointed nothing. Finishing a kathisma kept that rule. The Qt test opened each section, ignored a programmatic scroll, and kept the Gospel only after a wheel reached its end, leaving the Epistle and the life unmarked. The same scroll kept a kathisma. The sidebar test, the rope, four helper restarts, an offscreen window, and a 1100×860 review screenshot still passed. The Ubuntu 24.04 `amd64` half of this gate is the GitHub workflow.

### 2.4 Library and the editor

This is the slice that makes the Phase 2 gate possible. Until it exists, the only rules on Linux are the ones the review seeder writes.

- Library lists `RuleLibrary` templates in core's order: services, prayer, reading, fasting, life, then rules of one's own. Nothing is on until it is taken on.
- Taking a rule on opens the editor first. The editor sets the recurrence, the time, and who suggested it, and only then saves.
- When a spiritual father's name is stored, the editor offers that name by a checkbox. Checking it records the current name on the rule. Clearing the name in Settings leaves names already stored on rules as they are.
- Pause and resume use activations. Archive is the removal path the Mac already has. Scoped edits use the core edit planner.
- Home's "Add a New Rule" and the dotted Add placard both open Library. The whole placard is the button.
- Search in the library finds a template by its title.

**Gate.** From an empty normal record in a temporary `XDG_DATA_HOME`, the window can take on two library rules, edit one, pause one, and see only the active rule on Home. The bridge test performs the same steps without Qt.

**Checked on the ARM64 guest (2026-10-10):** from an empty normal record, the bridge test listed the library in core's order, found Morning prayers by title, and opened the editor before anything was saved. Saving morning prayers at 07:00 and evening prayers at 21:30 put both on Home. Editing the morning rule to 08:00 kept its id. Pausing it left both rules on that day, because a pause still counts the day it is made, and the next day showed only Evening prayers. Preparing the paused morning rule resumed it without opening the editor. A stored spiritual father's name was copied onto the evening rule and stayed there after the setting was cleared. A scoped edit started a new rule from that day on. Removing the morning rule took it off the library's taken list. Writing a custom rule showed the caution first, and setting it aside hid it from the library while leaving it on Home. The Qt test opened Library from Add a New Rule and from the dotted placard, took on both prayers, edited the morning time to 08:00, paused the evening rule, and on the next day showed only Morning prayers at 08:00. The sidebar test, the rope, reading, four helper restarts, an offscreen window, and a 1100×860 review screenshot still passed. The Ubuntu 24.04 `amd64` half of this gate is the GitHub workflow.

### 2.5 Home actions that need the other rooms

- The first click on a card opens its destination. Morning and evening prayers select their sequence. The Jesus Prayer opens the rope. A reading card opens the named section. Expansion, when the summary overflows, is a separate control and does not swallow that click.
- The card's further actions match the Mac menu: mark kept, mark kept late, clear the day, stand down, and open the editor. Standing down writes the skipped occurrence the Mac writes. Unticking deletes the row. It does not write a skip.
- When the last asked rule on a day becomes settled, the window says "Glory to God for all things" and then lets it fade. A day on which everything was stood down does not settle.
- The week strip and the card strip scroll on an ordinary wheel. The Today link follows core `TodayLink`: it appears once the visible week has moved off today.

**Gate.** The Qt navigation test, against the real helper and a temporary review record, marks a rule kept, stands one down, opens Prayers from a card, and returns to Home with the settled state the core reports.

**Checked on the ARM64 guest (2026-10-10):** the Qt test, against the real helper and a temporary review record, marked Evening prayers kept and stood the Gospel down. The gold dot matched the settled state core reported, and that day was not settled. Evening prayers opened Prayers on the evening sequence with the rope hidden. The Jesus Prayer opened the rope. The Gospel opened Reading at band 0. The Today link follows core `TodayLink` for the selected day: it appeared only after a non-today day was selected, read ← Today or Today →, and hid again once today was selected. The Wednesday fast on 2026-10-07 flipped in place, and its back face contained "ordinary weekly fast." Edit Rule… opened the morning editor. On Bright Week, 2027-05-05, the fast offered "Lifted by the Church Today" and hid mark kept and mark kept late. The sidebar test, the rope, reading, the library, four helper restarts, an offscreen window, and a 1100×860 review screenshot of 124684 bytes still passed. The Ubuntu 24.04 `amd64` half of this gate is the GitHub workflow.

### 2.6 Progress

- The report is `Practice.report`. Today is outside it. The window shows the same prose the Mac shows, including a paused rule removed from both sides of the count.
- No red, no "failed", no streak. Progress artwork stays still, with its quotation and caption inside the pane.
- The report can be opened at the 30-day range the Mac uses.

**Gate.** A fixture with one kept day and one missed day renders the core report's counts, and the missed day is not colored as a failure.

**Checked on the ARM64 guest (2026-10-10):** the report is `Practice.report` over 30 days, and today is outside it. A morning rule active from three days ago, kept on that day, missed the day after, and stood down yesterday, rendered "Morning prayers slipped once." and "One day was stood down and is not counted either way." The count was "1 of 2", in the same muted colour as any other count. The page did not say "failed" and did not show a streak. The figure was 50%, with "Kept, over the 30 days to then". The quotation of Saint John Climacus and the icon caption sat inside the progress pane, and the artwork did not pan. The bridge check, the sidebar test, the rope, reading, home actions, the library, four helper restarts, an offscreen window, and a 1100×860 review screenshot of 523486 bytes still passed. The Ubuntu 24.04 `amd64` half of this gate is the GitHub workflow.

### 2.7 Glossary

- Entries come from the bundled glossary. A term in a prayer, a reading, or a rule opens the entry, and Back returns to the section that sent it.
- The glossary is introductory. The screen does not present it as a ruling.

**Gate.** A Qt test follows a term from a prayer to its entry and back to that prayer.

**Checked on the ARM64 guest (2026-10-10):** Amen in The Beginning opened the bundled entry. The note read "Introductory, not a ruling." The pronunciation was AH-meen and the body began "Amen is not punctuation." See also opened Prayer rule and stayed in the glossary. Back returned to The Beginning. About This Rule on Morning prayers opened Prayer rule, and Back returned to Home. The glossary did not say "failed". The bridge check passed against the helper. The sidebar test, the rope, reading, home actions, progress, the library, four helper restarts, an offscreen window, and a 1100×860 review screenshot of 523486 bytes still passed. The Ubuntu 24.04 `amd64` half of this gate is the GitHub workflow.

### 2.8 Settings, onboarding, and the record

Settings sections, in the Mac's order: You, Your Church, The Calendar, Reminders, Prayer Rope, Your Record, General.

- You: display name, spiritual father's name, and Clear under the father field.
- Your Church: the named church, or no church shown when none is named. An unnamed record follows the Orthodox Church in America. A church with no Akathist dates uses the OCA's and says so.
- The Calendar: old-style dates, and each fast and feast observance as hidden, shown, or observed. They start at shown.
- Reminders: the lead time and the master switch. Delivery itself is Phase 3. The switch must already persist.
- Prayer Rope: the choices the Mac stores for sound and count.
- Your Record: export a backup, restore by merge, and the daily backup directory under the XDG data dir. Restore merges. It does not replace.
- General: reduced motion, links to About Chotki and Privacy, and the Linux alpha version string.
- Onboarding is the first-run path. Someone who already has rules is not shown it again. The library is how a rule is chosen. The app states that it is not a parish.

**Gate.** A temporary normal record can set a name and a church, export, import into a second empty directory, and see the merged rules. Reduced motion persists across a helper restart.

**Checked on the ARM64 guest (2026-10-11):** a temporary normal record opened on Welcome. The paragraphs included "not a substitute for a priest." The name Helen and the Romanian Orthodox Church continued onto Home, and the greeting contained Helen. Settings showed the Orthodox Church in America akathist note for that church. Reduced motion stayed on after the helper was killed, and the motion counter advanced, so the switch was read from the new helper. The bridge check exported that record, imported it into a second empty directory, and kept both a morning rule and an evening rule added after the first import. A relative backup path was refused. Reduced motion was still on when a new helper opened the same directory, and the daily backup file was under that record's backups directory. Home shows the clock style the record stores. The review morning times stayed 07:00 and 08:00. The sidebar test, the rope, reading, home actions, progress, the glossary, the library, four helper restarts, an offscreen window, and a 1100×860 review screenshot of 511232 bytes still passed. The Ubuntu 24.04 `amd64` half of this gate is the GitHub workflow.

### 2.9 Visual pass

Do this after the screens exist, so the pass covers the real window.

- Palette, XCharter for reading, sidebar width, and spacing taken from the Mac window.
- The month grid appears beside the day once the window is wide enough, and it shows one month at a time.
- Daily artwork pans slowly onto the curated focal point and holds there for the rest of that day. Use the existing saying order and focus metadata. Progress art does not pan.
- Icons are drawn in a scalable form, sharp on a hi-dpi display.
- Long card titles shrink to fit. Vertical pages fade at the edges instead of cutting on a hard line.
- Compare screenshots with the current Mac window at 1× and at 2×. Record any Linux gesture that differs, in this file, and keep the capability.

**Gate.** Side-by-side review of Home, Prayers, Reading, Library, Progress, Glossary, and Settings at both scales, with notes of what was accepted as different.

**Checked on the ARM64 guest (2026-10-11):** Home, Prayers, Reading, Library, Progress, Glossary, and Settings were compared at 1100×860 and at 2200×1720. The ground, panel, parchment, gold, muted, faint, line, and the Sunday ochre match the Mac window, and reading text is XCharter. The sidebar is 188 points wide and folds to 58 from the mark, or with Ctrl+Shift+S. At this width the week stays above the day and one month of the selected date sits beside it. Days outside that month are blank. No Sunday in the month is a fast. A review grab holds the saying on its resting crop; the progress picture stays still. Compact card titles fit the width, and the vertical pages dissolve into the ground at the top and bottom. The icons stayed sharp at 2×. The bridge check, the nine window tests, an offscreen window, and a 1100×860 review screenshot of 406850 bytes passed. The Ubuntu 24.04 `amd64` half of this gate is the GitHub workflow.

The Mac window folds the week into that month with a chevron. Linux keeps the week, which the day controls already use, and adds the month beside the day once the day column is at least 660 points wide. There is no chevron, and the Today link stays on the week. The Mac collapses the sidebar with the sidebar symbol and Command-Control-S. A card still opens with the Expand label rather than an expand icon. Backup export and restore stay a path; the file dialogs are Phase 3. There is no Dock switch and no login item.

## Phase 3 — Session services

The window already has to be complete. This phase connects it to the session.

- Drive reminders from the core scheduler and ticker. A notification can mark the rule kept or snooze it. Withdrawing a notification follows the Mac.
- Sound uses the desktop audio path. Reduced motion and a missing audio device skip playback and leave the record correct.
- Launch at login is a desktop autostart entry the user can turn off from Settings.
- File dialogs for backup export and restore. Links open in the default browser.
- Keyboard shortcuts for the seven sidebar sections stay, and each new primary action gets a visible shortcut where the Mac has one.
- Closing the window quits. Quit stops the helper. A killed helper still reconnects, and the restart count still resets after a good `hello`.
- If a tray is added, detect that the shell has one. The menu is Open, Silence or Enable notifications, Settings, and Quit. No tray means the window is unchanged.

**Gate.** On a real GNOME session, a synthetic rule fires a notification, Mark kept writes the occurrence, and Quit leaves no helper behind. The same build then runs the reminder action on Plasma and on Xfce, or records the exact session where an action is unavailable and still completes from the window.

**Checked on the ARM64 guest (2026-10-11):** the bridge check, the nine window tests, an offscreen window, and a 1100×860 review screenshot of 406850 bytes passed. On the running GNOME Wayland session the window opened through XWayland. A synthetic rule for that minute posted a notification titled "A session reminder," with the body "At 11:37" and the actions Mark complete and Snooze an hour. The daemon reports actions, body, body-markup, icon-static, persistence, and sound. A pointer click on Mark kept in the window wrote an occurrence for 2026-10-11 with status completed and a completedAt. The shell listed those action buttons without a size, so the keep was taken on the window. SIGTERM of the window left no helper. The window logged that a tray is available and stayed visible. Plasma and Xfce are not running on this guest. The file chooser on this guest is zenity. Open at login is the Settings switch. It writes an XDG autostart file only when the reader turns it on. The window has no Dock switch. The Ubuntu 24.04 `amd64` half of this gate is the GitHub workflow.

## Phase 4 — The package is the product

An alpha `.deb` already installs and opens. This phase makes that package the thing a reviewer can trust.

- Ship the optimized helper and window, the Swift runtime they actually link, the Qt and QML modules they actually load, SQLite, the core bundle, the calendar, prayers, artwork, fonts, licenses, the icon, and the `.desktop` file.
- Keep the runtime policy written down: Swift libraries bundled, Qt taken from Ubuntu 24.04 packages. Bump the package version on every `.deb` that is handed to someone.
- User data stays under `XDG_DATA_HOME/Chotki`. Uninstall removes `/usr/lib/chotki` and the desktop entry and leaves that directory in place. Upgrade and reinstall keep it.
- Confirm the LGPL obligations for the Qt modules that are linked, and ship the notices beside the existing Swift, XCharter, and app licenses.
- The clean-install CI job runs the synthetic daily flow against the installed package: take on a rule, mark it kept, export, restore into a fresh data directory.

**Gate.** A clean Ubuntu 24.04 `amd64` VM with no compilers installs the `.deb`, runs that flow, upgrades without losing the record, and uninstalls without deleting it.

**Checked on the ARM64 guest (2026-10-11):** the flow script, against the existing debug helper, took on Morning prayers, marked it kept for 2026-10-11, exported the record, and restored that completed occurrence into a second data directory. That helper still reports Linux alpha 0.1.0~alpha1. The package was not installed on the guest. The package script bundles the Swift libraries the release binaries link, takes Qt, QML, and SQLite from Ubuntu packages, and writes the Qt LGPL notice, the LGPL-3 text, and the runtime note beside the Swift, XCharter, and app licenses. The version handed to a reviewer is 0.1.0~alpha2, and it does not follow the macOS build number. There is no `postrm`, so removing the package leaves the data directory in place. The Ubuntu 24.04 `amd64` half of this gate is the GitHub workflow. That job installs the `.deb` and its runtime dependencies without adding a compiler, runs the same flow, reinstalls, upgrades to a local 0.1.0~alpha3 that is not uploaded, and removes the package. The record checksum is required to stay the same, and Depends must not name a compiler.

## Phase 5 — Accept or hold

- Run the installed package on GNOME, Plasma, and Xfce. Check startup, scaling, fonts, focus, scrolling, resize, notifications, dialogs, sound, the theme, reduced motion, and the path with no tray.
- Run the core suite and the Linux UI tests on the candidate.
- Inspect the architecture, `ldd`, the package file list, and the licenses.
- A person compares the screenshots and uses the window with a mouse and a keyboard.

**Gate.** No missing daily action and no record corruption. The `.deb` target is the one that was installed clean. Differences across desktops are written down. Only then decide whether to publish a Linux alpha. Until that decision, the branch stays source plus a CI artifact.

**Checked on the ARM64 guest (2026-10-11):** the core suite passed, 453 tests in 81 suites. The bridge check and the nine window tests passed. The window binary contains XCharter Roman and XCharter Bold. Offscreen, the process stayed up and logged that a tray is unavailable. Review grabs of Home, Prayers, Reading, Library, Progress, Glossary, and Settings were 1100×860, and the same pages at a scale of 2 were 2200×1720. The Home grab is 407374 bytes. On the running GNOME Wayland session the window opened through XWayland at 1100×860, logged that a tray is available, and stayed visible. Resizing that viewable window made it 900×700, and it stayed mapped. A name search also finds an unmapped 1×1 window titled Chotki. SIGTERM of the window left no helper. A synthetic rule posted a notification titled "A session reminder," body "At 14:07," with Mark complete and Snooze an hour, and the daemon accepted it. The daemon reports actions, body, body-markup, icon-static, persistence, and sound. `pw-play` played the helper's tick. `aplay` is installed. The file chooser is zenity, and it launched; kdialog is absent. The session locale is `en_US.UTF-8`, the theme is Yaru-dark, color-scheme is prefer-dark, animations are on, and the text scale is 1. The window keeps its own palette. Keyboard focus and scrolling are the window tests. Reduced motion is the settings test. This guest has no passwordless sudo, so the `amd64` package was not installed here. Plasma and Xfce are not installed. The Ubuntu 24.04 `amd64` half of this gate is the GitHub workflow. That job runs the core suite, requires `x86-64`, and fails if `ldd` reports a missing library, both for the release binaries and for the installed package. The offscreen launch must log that a tray is unavailable.

**Decision: hold.** The daily actions that were run here completed, and the record checks from Phase 4 still stand. Plasma, Xfce, and a person's comparison of this window with the Mac are still open. The branch stays source plus a CI artifact. This is not a published release.

On 2026-10-11 the welcome page in that package could not be finished: the church names were an unscrolling list, so Continue sat below the window, the shell repeated the title Welcome, and the edge fade was drawn over the page. The list is now a dropdown, the shell title is hidden while that page is up, and the fade is not drawn there. The words still come from Welcome. The hold is unchanged.

## Package targets

The release artifact is an `amd64` `.deb` built on Ubuntu 24.04. That job stays in GitHub CI. This ARM guest does not cross-compile it.

ARM is a second package of the same app, built natively on the Ubuntu guest. The 2026-10-10 guest build produced an `aarch64` shell and helper there, and an offscreen launch stayed up. An `arm64` `.deb` follows the same packaging script once the window is complete.

Linux on mobile is the same `aarch64` application with a layout that fits a phone-sized screen. It is not a third codebase. It waits until the desktop window can carry a day.

## Out of scope for this alpha

- Fedora, Arch, a Flatpak, or an AppImage.
- A tray that hides the window.
- Accounts, sync, or any network call besides orthocal.info for dates outside the bundled calendar.
- New artwork. The existing library and its focal metadata are the set. Additions need a separate approval.
- The retired reflections journal.

## Next slice

Nothing further until a person has compared the window with the Mac and the same build has been run on Plasma and on Xfce. The decision above is to hold.
