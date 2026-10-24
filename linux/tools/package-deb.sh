#!/usr/bin/env bash
set -euo pipefail

# Package already-built release binaries on the target Ubuntu architecture.
#
# Runtime policy: the Swift libraries the helper actually links are bundled.
# Qt, QML, and SQLite stay the Ubuntu packages named in Depends. The Linux
# version is 1.0~beta. It does not follow the macOS build number.
# Bump CHOTKI_PACKAGE_VERSION for every package handed to a reviewer.
if [[ $# -ne 3 ]]; then
    echo "Usage: package-deb.sh /path/to/chotki-linux /path/to/ChotkiLinuxBridge output-dir" >&2
    exit 2
fi

window=$(realpath "$1")
helper=$(realpath "$2")
output=$(realpath -m "$3")
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
arch=$(dpkg --print-architecture)
version=${CHOTKI_PACKAGE_VERSION:-1.0~beta}
package="$output/chotki_${version}_${arch}.deb"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

command -v dpkg-deb >/dev/null
command -v dpkg-query >/dev/null
command -v ldd >/dev/null
[[ -x "$window" && -x "$helper" ]] || { echo "Release binaries are missing" >&2; exit 1; }
core_bundle="$(dirname "$helper")/ChotkiCore_ChotkiCore.bundle"
[[ -d "$core_bundle" ]] || { echo "Swift core resource bundle is missing: $core_bundle" >&2; exit 1; }

install -d "$stage/DEBIAN" "$stage/usr/bin" "$stage/usr/lib/chotki/swift" \
    "$stage/usr/share/applications" \
    "$stage/usr/share/icons/hicolor/1024x1024/apps" \
    "$stage/usr/share/doc/chotki" \
    "$stage/usr/share/chotki/Resources/sayings"
install -m755 "$window" "$stage/usr/lib/chotki/chotki-linux"
install -m755 "$helper" "$stage/usr/lib/chotki/ChotkiLinuxBridge"
cp -a "$core_bundle" "$stage/usr/lib/chotki/"
# Prayer texts are compiled into the helper. The calendar, scripture, Psalter,
# and saint lives travel in the core bundle, in either the flat or archived layout.
for resource in calendar/manifest.json calendar/kjv.json psalter.json saint-lives.json; do
    if [[ ! -f "$stage/usr/lib/chotki/ChotkiCore_ChotkiCore.bundle/$resource" &&
          ! -f "$stage/usr/lib/chotki/ChotkiCore_ChotkiCore.bundle/Resources/$resource" ]]; then
        echo "Core bundle is missing $resource" >&2
        exit 1
    fi
done
icon_src="$repo_root/ios/Chotki/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
install -m644 "$icon_src" \
    "$stage/usr/share/icons/hicolor/1024x1024/apps/org.chotki.Chotki.png"
install -d "$stage/usr/share/pixmaps"
install -m644 "$icon_src" \
    "$stage/usr/share/pixmaps/org.chotki.Chotki.png"
# The hicolor index names 48 through 512. A lone 1024 is not in that index,
# so the dock and the overview never see it.
resize_icon() {
    local size="$1" dest="$2"
    if command -v convert >/dev/null 2>&1; then
        convert "$icon_src" -resize "${size}x${size}" "$dest"
    elif command -v magick >/dev/null 2>&1; then
        magick "$icon_src" -resize "${size}x${size}" "$dest"
    elif python3 -c "import PIL" >/dev/null 2>&1; then
        python3 - "$icon_src" "$size" "$dest" <<'PY'
import sys
from PIL import Image
size = int(sys.argv[2])
image = Image.open(sys.argv[1]).convert("RGBA")
image.resize((size, size), Image.Resampling.LANCZOS).save(sys.argv[3])
PY
    else
        echo "Need ImageMagick or Python PIL to scale the Chotki icon" >&2
        return 1
    fi
}
for size in 48 64 128 256 512; do
    install -d "$stage/usr/share/icons/hicolor/${size}x${size}/apps"
    resize_icon "$size" \
        "$stage/usr/share/icons/hicolor/${size}x${size}/apps/org.chotki.Chotki.png"
done
cat > "$stage/DEBIAN/postinst" <<'POST'
#!/bin/sh
set -e
if [ -x /usr/bin/gtk-update-icon-cache ]; then
    gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor || true
fi
POST
chmod 755 "$stage/DEBIAN/postinst"
install -m644 "$repo_root/LICENSE" "$stage/usr/share/doc/chotki/LICENSE"
install -m644 "$repo_root/linux/app/ui/fonts/LICENSE.txt" \
    "$stage/usr/share/doc/chotki/XCharter-LICENSE.txt"
cp -a "$repo_root/macos/Sources/Chotki/Resources/sayings/." \
    "$stage/usr/share/chotki/Resources/sayings/"
install -m644 "$repo_root/macos/Sources/Chotki/Resources/progress.jpg" \
    "$stage/usr/share/chotki/Resources/progress.jpg"

cat > "$stage/usr/bin/chotki" <<'SH'
#!/bin/sh
set -eu
export LD_LIBRARY_PATH="/usr/lib/chotki/swift${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export CHOTKI_ARTWORK_ROOT=/usr/share/chotki/Resources
mode=--normal
if [ "${1:-}" = --review ]; then mode=--review; shift; fi
exec /usr/lib/chotki/chotki-linux "$mode" /usr/lib/chotki/ChotkiLinuxBridge "$@"
SH
chmod 755 "$stage/usr/bin/chotki"

cat > "$stage/usr/share/applications/org.chotki.Chotki.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Chotki
Comment=An Orthodox rule of prayer
Exec=chotki
Icon=org.chotki.Chotki
Terminal=false
Categories=Education;Religion;
StartupWMClass=Chotki
DESKTOP

mapfile -t libraries < <(ldd "$window" "$helper" | awk '$2 == "=>" && $3 ~ /^\// {print $3}' | sort -u)
dependencies=()
swift_license=""
for library in "${libraries[@]}"; do
    if [[ "$library" == */lib/swift/linux/* ]]; then
        install -m755 "$library" "$stage/usr/lib/chotki/swift/$(basename "$library")"
        swift_usr=${library%%/lib/swift/linux/*}
        swift_license="$swift_usr/share/swift/LICENSE.txt"
    else
        resolved=$(realpath "$library")
        owner=$(dpkg-query -S "$resolved" 2>/dev/null | head -n1 | cut -d: -f1 || true)
        [[ -n "$owner" ]] || { echo "No package owns $resolved" >&2; exit 1; }
        dependencies+=("$owner")
    fi
done
[[ -n "$swift_license" && -f "$swift_license" ]] || {
    echo "Swift runtime license was not found" >&2
    exit 1
}
install -m644 "$swift_license" "$stage/usr/share/doc/chotki/Swift-LICENSE.txt"
dependencies+=(qt6-qpa-plugins qml6-module-qtquick qml6-module-qtquick-controls \
    qml6-module-qtquick-layouts qml6-module-qtquick-templates \
    qml6-module-qtquick-window \
    qml6-module-qtqml-models \
    qml6-module-qtqml-workerscript)
depends=$(printf '%s\n' "${dependencies[@]}" | sort -u | paste -sd, -)
if ldd "$helper" | grep -q 'libsqlite3\.so'; then
    printf '%s\n' "$depends" | grep -q sqlite || {
        echo "The helper links SQLite, and no SQLite package is in Depends" >&2
        exit 1
    }
fi

qt_packages=()
while IFS= read -r package_name; do
    case "$package_name" in
        libqt6*|qt6-*|qml6-*) qt_packages+=("$package_name") ;;
    esac
done < <(printf '%s\n' "$depends" | tr ',' '\n')
[[ ${#qt_packages[@]} -gt 0 ]] || { echo "No Qt package is in Depends" >&2; exit 1; }
lgpl=/usr/share/common-licenses/LGPL-3
[[ -f "$lgpl" ]] || { echo "The LGPL-3 text is not on this system" >&2; exit 1; }
install -m644 "$lgpl" "$stage/usr/share/doc/chotki/LGPL-3.txt"

{
    echo "Qt LGPL notice"
    echo
    echo "The window loads Qt dynamically and this package does not ship those libraries."
    echo "The modules in use are Qt Core, Qt GUI, Qt Widgets, Qt Network, Qt DBus,"
    echo "Qt QML, Qt Quick, Qt Quick Controls, Qt Quick Layouts, and Qt Quick Templates."
    echo "They are used under the GNU Lesser General Public License, version 3."
    echo "Chotki does not modify Qt. The corresponding source is the Ubuntu source"
    echo "package for each binary package below, available with apt-get source."
    echo "A modified Qt can be substituted on the system without rebuilding Chotki."
    echo "The license text is LGPL-3.txt in this directory."
    echo
    echo "Ubuntu packages:"
    printf '  %s\n' "${qt_packages[@]}"
} > "$stage/usr/share/doc/chotki/Qt-LGPL-NOTICE.txt"

cat > "$stage/usr/share/doc/chotki/RUNTIME.txt" <<RUNTIME
Chotki Linux runtime

Package version: $version
This label is 1.0 beta. It does not follow the macOS build number.
Bump it for every package handed to a reviewer.

The Swift libraries the helper links are bundled in /usr/lib/chotki/swift.
Qt and QML are not bundled. They come from the Ubuntu packages named in Depends.
SQLite is the system library the helper links, also from Ubuntu.
Prayer texts are compiled into the helper. The calendar, scripture, Psalter,
and saint lives are in the core bundle beside the helper.
Artwork and the progress image are in /usr/share/chotki/Resources.
XCharter is stored in the window. Its license is XCharter-LICENSE.txt.

The record stays in \$XDG_DATA_HOME/Chotki, or in ~/.local/share/Chotki when
that variable is unset or is not an absolute path. Removing, reinstalling,
or upgrading this package does not delete that directory.
RUNTIME

cat > "$stage/DEBIAN/control" <<CONTROL
Package: chotki
Version: $version
Section: education
Priority: optional
Architecture: $arch
Maintainer: Chotki project <noreply@github.com>
Depends: $depends
Description: Chotki Linux desktop alpha
 A desktop shell for the Chotki prayer rule.
 This alpha is for review. It is not a published release.
CONTROL

mkdir -p "$output"
dpkg-deb --build --root-owner-group "$stage" "$package"
dpkg-deb --info "$package"
echo "$package"
