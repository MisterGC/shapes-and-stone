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
# Clayground's libraries are found where the build put them, Qt's FFmpeg
# libraries in Qt's lib dir
qtlibs=$("$QMAKE" -query QT_INSTALL_LIBS)
qtplugins=$("$QMAKE" -query QT_INSTALL_PLUGINS)
export LD_LIBRARY_PATH="$build/lib:$build/bin:$qtlibs${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

cd "$out"
linuxdeploy --appdir "$appdir" \
    --executable "$build/bin/shapes_and_stone" \
    --desktop-file "$src/packaging/shapes_and_stone.desktop" \
    --icon-file "$src/packaging/shapes_and_stone.png" \
    --plugin qt

# clay_app's main adds <executable dir>/qml as an import path; the Qt plugin
# deployed the modules to usr/qml.
ln -sfn ../qml "$appdir/usr/bin/qml"

# The Qt plugin misses two plugins the game needs: SQLite, for
# Clayground.Storage, and the FFmpeg backend of Qt Multimedia, without which
# the game has no music and no sound. Copied in, with what they link.
for p in sqldrivers/libqsqlite.so multimedia/libffmpegmediaplugin.so; do
    mkdir -p "$appdir/usr/plugins/$(dirname "$p")"
    cp "$qtplugins/$p" "$appdir/usr/plugins/$p"
done

LDAI_OUTPUT="ShapesAndStone-linux-$(uname -m).AppImage" \
    linuxdeploy --appdir "$appdir" \
    --deploy-deps-only "$appdir/usr/plugins/sqldrivers" \
    --deploy-deps-only "$appdir/usr/plugins/multimedia" \
    --output appimage
echo "packaged: $out/ShapesAndStone-linux-$(uname -m).AppImage"
