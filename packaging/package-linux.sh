#!/usr/bin/env bash
# Packages the built game into an AppImage a friend without Qt can start:
# packaging/package-linux.sh <build dir> <out dir>
#
# Needs linuxdeploy and linuxdeploy-plugin-qt on PATH and QMAKE pointing at
# the Qt the game was built with.
#
# Workaround: clay_app has no deploy step, so the game runs linuxdeploy
# itself. It waits on a clayground issue for a packaging step in clay_app
# (see README, BUILD).
set -euo pipefail

build=$(cd "$1" && pwd)
mkdir -p "$2"
out=$(cd "$2" && pwd)
src=$(cd "$(dirname "$0")/.." && pwd)
appdir="$out/AppDir"

rm -rf "$appdir"
# The game's QML for the import scan, Clayground's built QML modules as
# where to find what it imports. The minimal platform is for the start
# check (QT_QPA_PLATFORM=minimal) on a machine without Qt.
export QML_SOURCES_PATHS="$src/src"
export QML_MODULES_PATHS="$build/bin/qml"
export EXTRA_PLATFORM_PLUGINS="libqminimal.so"
# Clayground's libraries are found where the build put them
export LD_LIBRARY_PATH="$build/lib:$build/bin${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

cd "$out"
linuxdeploy --appdir "$appdir" \
    --executable "$build/bin/shapes_and_stone" \
    --desktop-file "$src/packaging/shapes_and_stone.desktop" \
    --icon-file "$src/packaging/shapes_and_stone.png" \
    --plugin qt

# clay_app's main adds <executable dir>/qml as an import path; the Qt plugin
# deployed the modules to usr/qml.
ln -sfn ../qml "$appdir/usr/bin/qml"

LDAI_OUTPUT="ShapesAndStone-linux-$(uname -m).AppImage" \
    linuxdeploy --appdir "$appdir" --output appimage
echo "packaged: $out/ShapesAndStone-linux-$(uname -m).AppImage"
