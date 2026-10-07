#!/usr/bin/env bash
# Checks that two games on a package's runtime find each other over LAN:
# packaging/lan-check.sh <app> <qml tool of the same Qt>
#
# The packaged game has no way to host or join but its lobby, so the check
# runs src/Game.qml in two processes of Qt's qml tool placed inside the
# package: Qt, the Clayground plugins and their libraries (libdatachannel,
# OpenSSL) all come from the package. One hosts a LAN session (the host's
# embedded signaling, no internet), the other joins it with the host's code;
# both have to get into the dungeon with the other's knight. The
# environment is emptied as in start-check.sh. Exits 0 when both did.
set -uo pipefail

pkg=$(cd "$1" && pwd)
qmltool=$2
src=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)

if [ "$(uname -s)" != Darwin ]; then
    echo "lan-check.sh knows only the macOS package so far"
    exit 1
fi
probe="$pkg/Contents/MacOS/lan-check-qml"
imports="$pkg/Contents/Resources/qml"
cp "$qmltool" "$probe"
install_name_tool -add_rpath @executable_path/../Frameworks "$probe" 2>/dev/null
codesign --force --sign - "$probe" 2>/dev/null
cleanup() {
    kill "${hostpid:-}" "${joinpid:-}" 2>/dev/null
    rm -f "$probe"
    rm -rf "$tmp"
}
trap cleanup EXIT

run() {
    env -i HOME="$HOME" PATH=/usr/bin:/bin QT_QPA_PLATFORM=minimal \
        "$probe" -I "$imports" "$src/packaging/lan-check.qml" -- "$@"
}

run > "$tmp/host.log" 2>&1 &
hostpid=$!
code=""
for _ in $(seq 1 300); do
    code=$(sed -n 's/^qml: \[Lan\] code //p' "$tmp/host.log")
    [ -n "$code" ] && break
    kill -0 "$hostpid" 2>/dev/null || break
    sleep 0.1
done
if [ -z "$code" ]; then
    echo "the host printed no LAN code"
    cat "$tmp/host.log"
    exit 1
fi
echo "host's LAN code: $code"

run "$code" > "$tmp/join.log" 2>&1 &
joinpid=$!
wait "$joinpid"; joined=$?
wait "$hostpid"; hosted=$?

grep -h '\[Lan\]' "$tmp/host.log" "$tmp/join.log"
echo "host exit: $hosted, joiner exit: $joined"
if [ "$hosted" -ne 0 ] || [ "$joined" -ne 0 ]; then
    echo "--- host log"; cat "$tmp/host.log"
    echo "--- joiner log"; cat "$tmp/join.log"
    exit 1
fi
