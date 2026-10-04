#!/usr/bin/env bash
# Starts a packaged game the way a friend's machine would and fails if it
# does not come up: packaging/start-check.sh <executable>
#
# The environment is emptied (no Qt on PATH, no DYLD_*/LD_* paths, no
# QT_PLUGIN_PATH or QML_IMPORT_PATH), so the game has only what its package
# carries. QT_QPA_PLATFORM=minimal is clay_app's start check: any QML warning
# while Main.qml and the title load exits 1, else Main.qml quits with 0.
set -uo pipefail

exe=$1
log=$(mktemp)
case "$(uname -s)" in
    Darwin) trace="DYLD_PRINT_LIBRARIES=1" ;;
    *) trace="LD_DEBUG=libs" ;;
esac
env -i HOME="$HOME" PATH=/usr/bin:/bin QT_QPA_PLATFORM=minimal "$trace" \
    "$exe" > "$log" 2>&1
code=$?

# Every library has to come from the package or the system.
pkg=$(cd "$(dirname "$exe")/.." && pwd)
case "$(uname -s)" in
    Darwin) loaded=$(sed -n 's/^dyld\[[0-9]*\]: <[^>]*> //p' "$log") ;;
    *) loaded=$(sed -n 's/.*calling init: //p' "$log") ;;
esac
foreign=$(printf '%s\n' "$loaded" | grep -v -e "^$pkg" -e '^/System/' -e '^/usr/lib/' \
          -e '^/lib' -e '^/usr/lib64/' -e '^$' || true)

grep -v -e '^dyld\[' -e 'calling init' -e '^ *[0-9]*:' "$log"
echo "exit code: $code"
echo "libraries loaded: $(printf '%s\n' "$loaded" | grep -c .)"
if [ -n "$foreign" ]; then
    echo "loaded from outside the package:"
    printf '%s\n' "$foreign"
    code=1
fi
rm -f "$log"
exit $code
