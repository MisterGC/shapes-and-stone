#!/usr/bin/env bash
# Packages the built game into a zip a friend without Qt can start:
# packaging/package-macos.sh <build dir> <out dir> [<macdeployqt>]
#
# Workaround: clay_app has no deploy step, so the game runs macdeployqt
# itself and repairs what it leaves behind. It waits on clayground#380, a
# packaging step in clay_app (see README, BUILD).
set -euo pipefail

build=$(cd "$1" && pwd)
mkdir -p "$2"
out=$(cd "$2" && pwd)
deploy=$(command -v "${3:-macdeployqt}")
src=$(cd "$(dirname "$0")/.." && pwd)
app="$out/Shapes and Stone.app"

rm -rf "$app"
cp -R "$build/bin/shapes_and_stone.app" "$app"
# clay_app copies bin/qml into the app while the build may still be writing
# it: Clayground.Svg is no clay_plugin, so the copy does not wait for it and
# a clean build can leave it out. Copied again from the finished build;
# waits on clayground#381.
cp -R "$build/bin/qml/." "$app/Contents/Resources/qml/"

# -qmldir: the game's QML, scanned for the modules it imports.
# -qmlimport: where Clayground's QML modules were built.
"$deploy" "$app" -qmldir="$src/src" -qmlimport="$build/bin/qml" -verbose=1

# macdeployqt takes every SQL driver along; the game needs only SQLite
# (Clayground.Storage), the others link to client libraries a friend lacks.
find "$app/Contents/PlugIns/sqldrivers" -name '*.dylib' ! -name 'libqsqlite.dylib' -delete

# The start check (QT_QPA_PLATFORM=minimal: load, fail on any QML warning,
# quit) runs on the package too, on a machine without Qt; macdeployqt takes
# only the cocoa platform along.
qtplugins=$("$(dirname "$deploy")/qtpaths" --query QT_INSTALL_PLUGINS)
cp "$qtplugins/platforms/libqminimal.dylib" "$app/Contents/PlugIns/platforms/"

# Clayground's libraries keep the build's rpaths (the Qt kit, the build
# tree): on this machine they would load Qt from outside the package.
# The executable's @executable_path/../Frameworks is all they need.
find "$app" -type f \( -name '*.dylib' -o -perm -u+x \) | while read -r f; do
    file -b "$f" | grep -q Mach-O || continue
    otool -l "$f" | awk '/LC_RPATH/{getline; getline; print $2}' | while read -r r; do
        case "$r" in @*) ;; *) install_name_tool -delete_rpath "$r" "$f" ;; esac
    done
done

# Changing a binary breaks its signature; Apple Silicon starts nothing
# unsigned. Signed ad hoc: no Apple developer id, Gatekeeper asks once.
codesign --force --deep --sign - "$app"

python3 "$src/packaging/check-macos.py" "$app"

zip="$out/ShapesAndStone-macos-$(uname -m).zip"
rm -f "$zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
echo "packaged: $zip"
