# Linux desktop port

The Phase 1 Qt/QML shell talks to a persistent Swift process that imports the
canonical `core/` package. One line of versioned JSON is sent per request and
response. The UI process owns the window and Linux behavior; the Swift helper
owns record access and existing Chotki decisions. Phase 1 proved the shell
and package loop. Phase 2 is in progress; this is not yet a usable Linux edition.

## Build and review in the Ubuntu guest

Install Swift 6.4, SQLite development headers, CMake, Ninja, a C++ compiler,
Qt 6 Quick/declarative development packages, Qt Quick QML modules, and `rsync`.
The UTM share is mounted read-only at `/mnt/utm/chotki-1`. Run:

```sh
/mnt/utm/chotki-1/linux/tools/build-guest.sh
/mnt/utm/chotki-1/linux/tools/review-guest.sh
```

The build script copies `core/` and `linux/app/` into
`~/chotki-linux-build` before compiling. Override the source and staging
locations with `CHOTKI_SOURCE_ROOT` and `CHOTKI_STAGE_ROOT`. No compiler
output is written to the shared source tree.

The review helper uses `~/.cache/chotki-linux-review/chotki.sqlite`, seeded
with a sample name and six sample rules. Normal mode uses `XDG_DATA_HOME/Chotki/chotki.sqlite`,
falling back to `~/.local/share/Chotki/chotki.sqlite`. The two modes also use
different single-instance sockets. Do not use normal mode for screenshots or
automated tests.

For a synthetic Home screenshot, run the built window with `--review`, the
helper path, then `--screenshot /tmp/chotki-home.png`. Screenshot capture is
rejected in normal mode. The image remains outside Git.

## What has been checked

- Ubuntu 26.04.1 ARM64: Swift helper and Qt shell compile and launch on GNOME.
- Core greeting/date and bundled Psalm data reach the shell through the helper.
- A duplicate launch exits and keeps a single window and helper.
- Killing the helper starts a new helper and reconnects the shell.
- Closing the window also closes the helper.
- A Qt input test clicks the Prayers entry and observes the route change.
- The first Phase 2 Home slice reads actual core practice entries and saying
  text, selects dates, scrolls the visible week independently, and toggles rule
  completion through the Swift helper. An isolated protocol test checks that
  a completion can be toggled and restored and that the normal XDG record is
  never seeded with review data.
- The synthetic ARM64 Home screenshot was inspected against the macOS
  reference. The original daily artwork now loads from the existing macOS
  library, with the same 365-day selection order. The package includes the
  artwork and its source metadata. The bundled core calendar supplies the
  day heading and feast/fast cues. Vector navigation and category icons now
  replace the temporary text symbols. The image is rendered with rounded
  corners and a fading overlay. A core-derived dot marks a settled day in the
  week, and a Today link returns to the current week. Further card polish and artwork motion
  and the remaining routes still need Phase 2 work.

GitHub Actions [run 37708377872](https://github.com/rjmac83/chotki/actions/runs/37708377872)
passed `amd64` compilation, the bridge/core check, Qt mouse and keyboard
navigation, and a headless shell launch on Ubuntu 24.04. After reestablishing
UTM's guest input capture, a real mouse click and a `Ctrl+2` key press also
changed routes in GNOME.

An early `arm64` alpha `.deb` built and installed on the Ubuntu 26.04 guest;
its installed review window launched. The package script
bundles the Swift runtime libraries used by the helper and declares system
Qt/QML packages. The reviewer package is 0.1.0~alpha2. SQLite stays the
Ubuntu library the helper links. The Qt LGPL notice, the LGPL-3 text, and a
runtime note ship beside the Swift, XCharter, and app licenses. Removing the
package leaves `XDG_DATA_HOME/Chotki` in place. The clean-install check is the
GitHub workflow, recorded in `linux/COMPLETION.md`. The same GitHub run built an `amd64` `.deb`, installed it on
a separate Ubuntu 24.04 runner, and launched the installed review window. The
package is available as that run's `chotki-linux-amd64-alpha` artifact and
is also copied into the local gitignored `linux/dist/` folder. This is a
technical proof of packaging and window startup, not a release candidate. The Phase 2
Home slice passed [amd64 CI run 37709648812](https://github.com/rjmac83/chotki/actions/runs/37709648812).
Its installed-window smoke test missed a gap found during later ARM review:
the `.deb` omitted the Swift core resource bundle. The package now includes
that bundle, and the clean-install CI gate asks the installed helper for a
real Psalm-backed snapshot. [Run 37710245451](https://github.com/rjmac83/chotki/actions/runs/37710245451)
passed that stronger amd64 gate. The installed ARM64 package was also
reviewed in a synthetic screenshot with its artwork and commitments visible.
The next CI gate renders a screenshot from the installed `amd64` package and
requires the helper to connect before capture.
