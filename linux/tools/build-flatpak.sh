#!/usr/bin/env bash
# Build a single-architecture Flatpak bundle.
#
# The Swift helper is already built on this Ubuntu, so its glibc matches
# org.kde.Platform 6.10. The Qt window is compiled inside that SDK.
# Usage: build-flatpak.sh /path/to/ChotkiLinuxBridge /path/to/output.flatpak
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: build-flatpak.sh /path/to/ChotkiLinuxBridge /path/to/output.flatpak" >&2
    exit 2
fi

helper=$(realpath "$1")
output=$(realpath -m "$2")
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
flatpak_dir="$repo_root/linux/flatpak"
payload="$flatpak_dir/payload"
# The builder's directories stay outside the source tree. A dir source of the
# repository would otherwise copy the build into itself.
work=$(mktemp -d /tmp/chotki-flatpak-work.XXXXXX)
bundle_repo=$(mktemp -d /tmp/chotki-flatpak-repo.XXXXXX)
state=$(mktemp -d /tmp/chotki-flatpak-state.XXXXXX)
trap 'rm -rf "$work" "$bundle_repo" "$state"' EXIT
runtime=org.kde.Platform//6.10
sdk=org.kde.Sdk//6.10

[[ -x "$helper" ]] || { echo "Swift helper is missing: $helper" >&2; exit 1; }
core_bundle="$(dirname "$helper")/ChotkiCore_ChotkiCore.bundle"
[[ -d "$core_bundle" ]] || { echo "Swift core resource bundle is missing: $core_bundle" >&2; exit 1; }
command -v flatpak >/dev/null
command -v flatpak-builder >/dev/null
command -v python3 >/dev/null
flatpak info "$runtime" >/dev/null
flatpak info "$sdk" >/dev/null

machine=$(uname -m)
case "$machine" in
    x86_64) file_marker=x86-64 ;;
    aarch64) file_marker=aarch64 ;;
    *) echo "Unsupported machine: $machine" >&2; exit 1 ;;
esac
file "$helper" | grep -q "$file_marker"

runtime_files=$(flatpak info --show-location "$runtime")/files
[[ -d "$runtime_files" ]] || { echo "KDE runtime files are missing" >&2; exit 1; }

rm -rf "$payload"
mkdir -p "$payload/swift" "$payload/compat" "$payload/icons" "$payload/Resources/sayings"

install -m755 "$helper" "$payload/ChotkiLinuxBridge"
cp -a "$core_bundle" "$payload/"
for resource in calendar/manifest.json calendar/kjv.json psalter.json saint-lives.json; do
    if [[ ! -f "$payload/ChotkiCore_ChotkiCore.bundle/$resource" &&
          ! -f "$payload/ChotkiCore_ChotkiCore.bundle/Resources/$resource" ]]; then
        echo "Core bundle is missing $resource" >&2
        exit 1
    fi
done

swift_license=""
while IFS= read -r library; do
    [[ "$library" == */lib/swift/linux/* ]] || continue
    install -m755 "$library" "$payload/swift/$(basename "$library")"
    swift_usr=${library%%/lib/swift/linux/*}
    swift_license="$swift_usr/share/swift/LICENSE.txt"
done < <(ldd "$helper" | awk '$2 == "=>" && $3 ~ /^\// {print $3}' | sort -u)
[[ -n "$swift_license" && -f "$swift_license" ]] || {
    echo "Swift runtime license was not found" >&2
    exit 1
}

# Keep a host library only when the runtime does not already provide that
# soname. libicu from Ubuntu 24.04 is the usual one. The helper alone sees
# these, through chotki-helper, so they do not shadow the window's Qt.
runtime_has() {
    local soname="$1"
    find "$runtime_files" -name "$soname" -print -quit | grep -q .
}
while IFS= read -r library; do
    base=$(basename "$library")
    case "$base" in
        libc.so*|libm.so*|libdl.so*|librt.so*|libpthread.so*|libresolv.so*|ld-linux*|linux-vdso*|libstdc++.so*|libgcc_s.so*|libsqlite3.so*)
            continue ;;
        libswift*)
            continue ;;
    esac
    if runtime_has "$base"; then
        continue
    fi
    install -m755 "$library" "$payload/compat/$base"
done < <(ldd "$helper" | awk '$2 == "=>" && $3 ~ /^\// {print $3}' | sort -u)

install -m644 "$repo_root/LICENSE" "$payload/LICENSE"
install -m644 "$swift_license" "$payload/Swift-LICENSE.txt"
install -m644 "$repo_root/linux/app/ui/fonts/LICENSE.txt" "$payload/XCharter-LICENSE.txt"
lgpl=/usr/share/common-licenses/LGPL-3
[[ -f "$lgpl" ]] || { echo "The LGPL-3 text is not on this system" >&2; exit 1; }
install -m644 "$lgpl" "$payload/LGPL-3.txt"
install -m644 "$flatpak_dir/org.chotki.Chotki.desktop" "$payload/org.chotki.Chotki.desktop"
install -m644 "$flatpak_dir/org.chotki.Chotki.metainfo.xml" "$payload/org.chotki.Chotki.metainfo.xml"
cat > "$payload/Qt-LGPL-NOTICE.txt" <<'NOTICE'
Qt LGPL notice

The window loads Qt from the shared runtime org.kde.Platform 6.10.
This bundle does not ship those libraries. The modules in use are Qt Core,
Qt GUI, Qt Widgets, Qt Network, Qt DBus, Qt QML, Qt Quick, Qt Quick Controls,
Qt Quick Layouts, and Qt Quick Templates. They are used under the GNU Lesser
General Public License, version 3. Chotki does not modify Qt. The corresponding
source is the org.kde.Platform 6.10 runtime published by KDE. Replacing that
runtime replaces Qt without rebuilding Chotki. The license text is LGPL-3.txt
in this directory.
NOTICE
cat > "$payload/RUNTIME.txt" <<'RUNTIME'
Chotki Linux Flatpak

This label is 1.0 beta. The bundle version is 1.0-beta. It does not follow
the macOS build number. There is one bundle for x86_64 and one for aarch64.

The Swift libraries the helper links are in /app/lib/chotki/swift. A library
the KDE runtime does not provide is in /app/lib/chotki/compat, and only the
helper's launcher adds that directory. Qt comes from org.kde.Platform 6.10.
The rope's tones play through /app/bin/chotki-play.

The record stays in the Flatpak data directory, under Chotki. Removing this
bundle does not delete that directory. A deb install keeps its record in
XDG_DATA_HOME/Chotki, which is a different directory.
RUNTIME

cp -a "$repo_root/macos/Sources/Chotki/Resources/sayings/." "$payload/Resources/sayings/"
install -m644 "$repo_root/macos/Sources/Chotki/Resources/progress.jpg" \
    "$payload/Resources/progress.jpg"

icon_src="$repo_root/ios/Chotki/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
resize_icon() {
    local size="$1" dest="$2"
    python3 - "$icon_src" "$size" "$dest" <<'PY'
import sys
from PIL import Image
size = int(sys.argv[2])
image = Image.open(sys.argv[1]).convert("RGBA")
image.resize((size, size), Image.Resampling.LANCZOS).save(sys.argv[3])
PY
}
# flatpak build-export rejects an icon larger than 512.
for size in 48 64 128 256 512; do
    install -d "$payload/icons/hicolor/${size}x${size}/apps"
    resize_icon "$size" \
        "$payload/icons/hicolor/${size}x${size}/apps/org.chotki.Chotki.png"
done

cat > "$payload/chotki-helper" <<'SH'
#!/bin/sh
set -eu
export LD_LIBRARY_PATH="/app/lib/chotki/swift:/app/lib/chotki/compat${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec /app/lib/chotki/ChotkiLinuxBridge "$@"
SH
cat > "$payload/chotki" <<'SH'
#!/bin/sh
set -eu
export CHOTKI_ARTWORK_ROOT=/app/share/chotki/Resources
# Offscreen review sets the platform itself. The portal theme is for a session,
# where the backup chooser has to see the host's files.
if [ "${QT_QPA_PLATFORM:-}" != offscreen ]; then
    export QT_QPA_PLATFORMTHEME=xdgdesktopportal
fi
mode=--normal
if [ "${1:-}" = --review ]; then mode=--review; shift; fi
exec /app/lib/chotki/chotki-linux "$mode" /app/bin/chotki-helper "$@"
SH
chmod 755 "$payload/chotki" "$payload/chotki-helper"

mkdir -p "$(dirname "$output")"
flatpak-builder --user --disable-rofiles-fuse --force-clean \
    --state-dir="$state" --repo="$bundle_repo" \
    "$work" "$flatpak_dir/org.chotki.Chotki.yml"

window="$work/files/lib/chotki/chotki-linux"
player="$work/files/bin/chotki-play"
file "$window" "$player" "$work/files/lib/chotki/ChotkiLinuxBridge" | tee /tmp/chotki-flatpak-file.txt
test "$(grep -c "$file_marker" /tmp/chotki-flatpak-file.txt)" -eq 3
# The runtime has no ldd. A NEEDED soname must exist in the bundle or the runtime.
missing=0
check_needed() {
    local binary="$1" extra="$2" soname
    while IFS= read -r soname; do
        [[ -n "$soname" ]] || continue
        if find "$work/files" $extra "$runtime_files" -name "$soname" -print -quit | grep -q .; then
            continue
        fi
        echo "Unresolved $soname from $binary" >&2
        missing=1
    done < <(readelf -d "$binary" | awk '/NEEDED/ { gsub(/[][]/, "", $NF); print $NF }')
}
check_needed "$window" ""
check_needed "$player" ""
check_needed "$work/files/lib/chotki/ChotkiLinuxBridge" "$work/files/lib/chotki/swift $work/files/lib/chotki/compat"
if [[ "$missing" -ne 0 ]]; then
    echo "A Flatpak binary has an unresolved library" >&2
    exit 1
fi
test -f "$work/files/share/chotki/Resources/sayings/order.txt"
test -f "$work/files/share/chotki/Resources/progress.jpg"
test -f "$work/files/share/metainfo/org.chotki.Chotki.metainfo.xml"
test -x "$work/files/bin/chotki"

flatpak build-bundle "$bundle_repo" "$output" org.chotki.Chotki
echo "$output"
