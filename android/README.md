# Chotki for Android

## Current state — 3 October 2026

Android is 1.0 beta, build 32. The Kotlin core and Compose interface are implemented; the older planning discussion below records the port's original decisions. Shared text is exported from Swift and checked for parity. Home uses the approved 365-image Mac library through generated WebP assets. A named church supplies calendar and tradition; no affiliation follows OCA on the New Calendar while older saved churches remain unchanged.

## Portable image packaging

`syncDailyImages` generates the phone library with Python 3.10+ and pinned Pillow 12.0.0. It corrects all EXIF orientations, fits images inside 1280 × 1920 without enlargement, and writes WebP at quality 75 and method 6. Mac originals, image order, and focal positions are preserved. There is no `sips` or `cwebp` dependency.

From the repository root, prepare the isolated environment once:

```sh
python3 -m venv android/.image-tools
android/.image-tools/bin/python -m pip install --only-binary=:all: -r android/tools/image-requirements.txt
android/.image-tools/bin/python -m unittest discover -s android/tools -p 'test_*.py'
```

Use a Python 3.10+ executable for the first command; the macOS system Python 3.9 is too old. On Windows, the environment's interpreter is `android/.image-tools/Scripts/python.exe`. Gradle discovers this project environment automatically. Alternatively, select an interpreter with `CHOTKI_IMAGE_PYTHON` or `-PimagePython=/absolute/path/to/python`; the Gradle property takes precedence. Install the same requirements into that interpreter's environment.

The build fails early for a missing/wrong Pillow version or absent WebP support. Gradle tracks the script, requirements, selected interpreter, and actual encoder versions. The converter also checks source/output hashes so old timestamps or damaged generated files cannot silently reuse stale images. Its cache identity includes Pillow/libwebp versions and conversion settings.

The Ubuntu app-build job creates the same environment, runs synthetic tests for all eight EXIF orientations, and verifies all 365 images inside both debug and release APKs. To verify locally after assembly:

```sh
android/.image-tools/bin/python android/tools/verify_sayings.py \
  macos/Sources/Chotki/Resources/sayings \
  android/app/build/outputs/apk/debug/app-debug.apk \
  android/app/build/outputs/apk/release/app-release.apk
```

WebP bytes may differ from the earlier encoder. Source artwork and crop coordinates do not change. Updating Pillow requires updating the pin and regenerating/reviewing the library.

## The one thing to understand first

Swift does not run on Android in any practical way. This is a **reimplementation
in Kotlin**, not shared code — so `core/` and its 280 tests stop being an
implementation and become a *specification*. Everything this app decides is
stated there once. A Kotlin core that passes a translation of those tests is the
same application underneath, and anything left undone shows up as a missing
test rather than as a bug Ryan finds three weeks later.

## Toolchain on this machine — verified 24 August 2026

Checked, not assumed:

| | |
|---|---|
| Android Studio | ✅ 2026.1 |
| SDK | ✅ `~/Library/Android/sdk`, 1.8 GB, licences accepted |
| Platform | ✅ `android-37.0`, `android.jar` present |
| Build tools | ✅ 36.0.0 |
| `adb` | ✅ 1.0.41 (37.0.1) |
| JDK | ✅ JetBrains Runtime **25**, bundled in Studio |
| Emulator binary | ✅ present |
| **System images** | ❌ **none — the emulator has nothing to boot** |
| **AVDs** | ❌ none |
| **Command-line tools** | ❌ no `sdkmanager`, no `avdmanager` |
| **Connected device** | ❌ nothing on `adb devices` |

**We can build. We cannot yet run anything.** That gap has to close before any
phase can end the way `PORT.md` says it should — with something demonstrated
rather than asserted.

### Emulator first, the phone later (decided 24 August 2026)

The S21 FE is Ryan's daily driver and carries financial apps that refuse to run
while Developer options are enabled. That is a real constraint and a common one,
not something to talk him out of: the port is built and verified against an
emulator, and the phone comes in near the end.

**Match the emulator to the phone: an arm64 system image at API 33** (Android
13). Not the newest available — the whole point is to reproduce what the target
device does, and API 33 is where `POST_NOTIFICATIONS` becomes a runtime
permission. A newer image would hide exactly the behaviour worth catching.

**What this defers, and it must not be forgotten.** OneUI decides for itself
when to stop an app's background work, and no emulator reproduces it. So
reminder *reliability on the actual phone* stays unverified until Phase 11 —
which means it is a real risk carried the whole way, not a detail. Everything
else about reminders can be proved on the emulator: whether they are scheduled,
what they say, when they fire, what happens across a reboot.

When the time comes, Developer options can be switched off again between
sessions; most apps that object check at launch. That is Ryan's call to make
then, not a reason to enable it now.

### The emulator that exists — verified 24 August 2026

`adb` works end to end: `devices`, `exec-out screencap` (a valid 1440x3120 PNG)
and `input` injection all confirmed. The interface can be driven from the shell,
which is the requirement.

The AVD itself is **Pixel_7_Pro, arm64, 1440x3120 at 560dpi**, running
`system-images/android-37.2-beta3/google_apis_playstore_ps16k`. Three things
about that image are worth knowing:

- **API 37, not 33.** Four versions above the target phone. Useful — newer
  Android is stricter, so anything passing here will very likely pass on 13 —
  but it is not the device being aimed at.
- **A beta-channel image** (`37.2-beta3`), though the build reports itself as
  released. Not what to settle a behaviour question on.
- **The Play Store variant**, which is locked: no `adb root`.

**Not blocking.** Phases 1 to 7 are pure Kotlin and need no device at all. But
before Phase 8 there should be a second AVD: **API 33, `google_apis` rather than
`google_apis_playstore`, arm64**. That is the one that matches the phone, and
the one reminder behaviour gets judged on.

Also worth noting for later: `ps16k` is a 16 KB page-size image, which is
stricter than most real devices. Any native library the app pulls in — a bundled
SQLite, for instance — must be 16 KB aligned or it will not load. An argument
for using the platform's own SQLite and shipping no native code at all.

### Command-line tools

Not installed, and not obvious in the interface. **Settings (⌘,) → Languages &
Frameworks → Android SDK → the *SDK Tools* tab → "Android SDK Command-line
Tools (latest)"**. From the welcome screen instead: **More Actions → SDK
Manager**, same tab. Tick "Show Package Details" if the entry is not visible.

Without it there is no `sdkmanager` or `avdmanager`, so SDK packages and
emulators can only be managed through the GUI — which makes Ryan the bottleneck
for something that should be a shell command.

## The stack

Settled by the answers below, except where a row says otherwise.

| | Proposed | Why |
|---|---|---|
| Language | Kotlin | The only sane option; Swift is out |
| Modules | `:core` (pure Kotlin/JVM), `:app` (Android) | Mirrors the Swift split, and the same CI guard applies |
| UI | Jetpack Compose, Material 3 | Declarative, closest to the SwiftUI already written |
| Database | SQLDelight, or raw `androidx.sqlite` | Same schema and migration ladder as macOS. **Not Room**, which wants to own a schema this one already has. No longer needed for file interchange — kept because the schema is part of the specification |
| Dates | No date library | `CalendarDate` is timezone-free integer arithmetic and depends on nothing. Keep it that way |
| HTTP | OkHttp or Ktor, behind `HttpFetching` | Same interface as Swift, so tests stay offline |
| JSON | kotlinx.serialization | Orthocal decoding, and possibly shared content |
| Reminders | `AlarmManager` + `NotificationManager` | Exact alarms need permission from Android 12 |
| Background | `WorkManager` | Daily liturgical fetch, backups |
| Min SDK | **26 (Android 8)** — see the note under question 2 | The floor, not the target. Covers essentially every device in use; the test device runs far newer |
| Target SDK | Latest stable | Required by Play eventually, and it is what the runtime-permission behaviour is written against |
| Tests | JUnit + `kotlin.test`; Compose UI tests | The 280 core tests translate; UI must be *driven*, not screenshotted |
| Repo | This one, as `android/` | One history, one licence, shared content in view |

## Open questions for Phase 0

Answers change the work; guesses would be expensive.

1. **Feature scope for v1** — everything the Mac app does, or a subset to start?
   Launch-at-login has no Android equivalent and drops out either way.

   My answer: everything the Mac app has, please.

2. **Which device**, and which Android version does it run? That sets the real
   minimum, and the emulator profile to test against.

    My answer: The app should run cleanly on the largest number of Android devices currently in use today. I have an S21 FE running Android 13 (Kernel version 4.19.113-29223811) and OneUI 5.1. To my understanding this is fairly old, and should suffice as a minimum requirement sicne most Android devices in use today will have at least this versionor above.

3. **Should the database be interchangeable** with the macOS one — copy the file
   across and it opens? That is nearly free if decided now, and awkward later.
   Note this is *not* sync; syncing between devices is a separate, much larger
   feature.

    My answer: We're not going to worry about sync at all for now. The idea will be that you'll run it on one device, and this device will *the* device the user uses for this app.

4. **Distribution** — a direct APK, as with the Mac alpha, or
   the Play Store? Play means a developer account, a review process, and a
   privacy policy; direct means asking people to permit installing from an
   unknown source.

    My answer: Direct APK for now. I will worry about a developer account and the rest later.

5. **Shared content as JSON?** Exporting prayers, glossary, library and readings
   to JSON that both platforms read would make drift impossible — but it changes
   the macOS app too. Worth it if Windows and Linux ports are still planned.

 My answer: As the app may see feature updates and changes that will have to be implemented across platforms, we should account for this in the most efficient way going forward.

6. **Where the priest review stands.** The glossary and prayer texts still need
   it, and duplicating unreviewed content onto a second platform doubles what
   has to be corrected later.


 My answer: I've yet to find a priest running Apple Silicon. Part of why I'm moving forward with the Android SDK now is that this will make it more accessible to more priests -- it'll help me find one to review it.

## Progress

| Phase | State |
|---|---|
| 1 — Scaffolding and the guard | **Done.** Gradle 9.7.1, Kotlin 2.4.0, `:core` only, green on Linux CI |
| 2 — `CalendarDate` and time | **Done.** 17 tests: the 14 from the Swift suite, plus 3 differential |
| 3 — The model and recurrence | **Done.** 50 tests, including two differential fixtures |
| 4 — The store | **Done.** 73 tests. Settings and the liturgical cache wait for their types |
| 5 — Practice and progress | **Done.** 113 tests, including a 141-day scoring fixture |
| 6 — The liturgical layer | **Done.** 158 tests, against the same recorded orthocal responses |
| 7 — Reminders | **Done.** 196 tests. Everything that decides *when* is now ported |
| 8 — Content | **Done.** 214 tests. Generated from Swift, drift caught by CI |
| 9 — Android platform layer | **Done.** 214 JVM tests, 20 on-device. Store, notifications and alarms all verified on API 33 |
| 10 — The interface | **Done.** All seven places, custom rules, editing, and the prayer rope. 55 instrumented tests |
| 11 — The phone | Not started |

## Decisions — settled 24 August 2026

| | |
|---|---|
| Scope | Everything the Mac app does |
| Content | **Shared JSON**, adopted during development so later additions land on every platform at once |
| History | **No import.** Android starts blank. The Mac stays Ryan's personal instance; Android is the beta, and goes to other testers |
| Sync | None, now or planned |
| Widget | Not in v1 |
| Menu-bar equivalent | See below |
| `minSdk` | **26.** Build against the latest, test on 33 |
| Distribution | Direct APK |
| Priest review | Pending; Android is partly how a reviewer gets found |

### What replaces the menu bar (my call, as asked)

**Nothing extra in v1.** The menu bar gave two things: the rule always within
reach, and a glance without opening anything. On Android those are already
covered — the launcher icon reaches the app in one tap, and the *glance* is what
a notification is for. Building a second always-on surface would duplicate the
reminders rather than add to them.

So: the app opens on today's rule, exactly as the popover did. If a true
equivalent is wanted later, it is a **Quick Settings tile** rather than a
widget — that is the system-level "always there" affordance on Android, it is
far less work than a widget, and it can be added without disturbing anything.

### One consequence of starting blank

No import means no real data on Android, and this app's harder bugs have all
been about accumulated history — progress that stops at yesterday, activation
windows, the three-way edit. A fresh install exercises none of it.

So the Kotlin core needs **generated history in its tests** — the Swift suite's
"A simulated month" does exactly this — and the emulator needs a seeded
database to develop against. Otherwise the first real test of the scoring is
whoever installs the APK.

## What the answers settle — and what they do not

**Settled.** Full feature parity. One device, no sync. Direct APK. Content moves
to a single shared source. The priest review waits on Android reaching a priest.

**Three things need doing before any code**, and all three are Ryan's:

1. **Android Studio and the SDK.** Still not installed. `brew install --cask
   android-studio`, then let its first run fetch the SDK. The licences are
   Google's and have to be accepted by him.
2. **A JDK the Android Gradle Plugin supports.** The only JDK here is 26, which
   it will not build with. Android Studio's bundled runtime covers the IDE;
   `brew install openjdk@21 gradle` covers the command line, which is where the
   work actually happens.
3. **USB debugging on the S21 FE**, if it is to be tested on the real device
   rather than only an emulator. It should be — see the OneUI note below.

### The minimum version needs correcting

The answer to question 2 says Android 13 is "fairly old" and would suffice as a
minimum. It is the reverse: Android 13 is from 2022 and sits on the *new* side
of what is in use. Setting the floor there would exclude a large share of
devices, including most that are more than a few years old — the opposite of
the stated goal.

`minSdk` is a **floor, not a target**. At 26 the app runs on Android 8 and
everything above it, the S21 FE included. So: floor at 26, build against the
latest, and test on Android 13 because that is the device in hand. Android
Studio shows Google's current distribution figures when a project is created;
worth a look then rather than trusting either of our guesses.

### Three risks specific to that device

Named because each one fails *silently*, which is this project's recurring way
of going wrong.

- **`POST_NOTIFICATIONS` is a runtime permission from Android 13.** Not
  requested, notifications simply never appear — no error, no crash. The test
  device is exactly the version where this starts to matter.
- **Exact alarms need permission from Android 12.** A prayer reminder that
  arrives whenever the system feels like it is not a reminder for a rule kept at
  a set hour.
- **OneUI kills background work aggressively.** Samsung's battery optimisation
  is well known for stopping alarms on apps it decides are idle. The app will
  need to ask for an exemption and explain why, and reminders must be verified
  over several real days on the real device, not once on an emulator.

### Two things the answers do not cover

- **His existing history.** "No sync" is settled, but he has had a rule going on
  the Mac since 19 August, and if the phone becomes *the* device that record
  should go with it. A one-time export and import is a fraction of the work of
  sync, and the schema is identical, so it is nearly free — but it has to be
  decided before the Android store is written, not after.
- **What replaces the menu bar.** Full parity means the features, not the
  shapes: Android has no menu bar popover and no login items. The natural
  equivalent is a home-screen widget showing today's rule. Worth knowing whether
  that belongs in v1 or later.

### The shared-content decision needs one more turn

Question 5 asked whether content should move to shared JSON; the answer says to
handle cross-platform updates in the most efficient way. That points at one
source of truth — prayers, glossary, rule library and patristic readings
extracted to JSON, shipped as a resource, decoded by both platforms. It is the
right answer for an app that will keep changing on two platforms, and it is what
stops the prayer texts drifting apart.

It also means **changing the macOS app, which currently works**, and that is not
a change to make on an inference. Confirm before Phase 1.

## Still outstanding on macOS

Not blockers for Android, but they do not disappear:

- Universal binary — complete; the public Mac download contains arm64 and x86_64. Intel execution remains unverified.
- Notarisation — needs the $99/year Apple Developer Program, Ryan's call
- Priest review of the glossary, prayer texts and patristic attributions
- Confirming the parish reckoning (named church supplies its calendar; no affiliation follows OCA on the New Calendar; older saved churches remain unchanged)
