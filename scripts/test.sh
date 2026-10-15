#!/bin/sh
# Runs Koe's checks: builds the app (signed ad hoc) and runs its self-test
# (keyboard, audio, typing, the ten languages, thousands of random inputs),
# checks the sources and the English table say the same lines, and the shell
# scripts through `sh -n` and shellcheck (when installed).
set -eu
cd "$(dirname "$0")/.."

# Its own copy: never the Koe that may be running from build/Koe.app.
APP=build/test/Koe.app SIGN=- scripts/build.sh >/dev/null
build/test/Koe.app/Contents/MacOS/Koe --self-test
scripts/strings-check.sh

for script in install.sh uninstall.sh scripts/*.sh; do
  [ -f "$script" ] || continue
  sh -n "$script"
done
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -s sh install.sh uninstall.sh scripts/*.sh
  echo "shellcheck clean"
fi
