#!/bin/sh
# Koe uninstaller.
#
#   curl -fsSL koe.fm/uninstall | sh
#
# Quits Koe and removes the app, its settings, its voice model, its recent
# recordings and its log, and its microphone and Accessibility permissions.
set -eu

say() { printf '%s\n' "$*"; }

if pgrep -x Koe >/dev/null 2>&1; then
  osascript -e 'tell application id "fm.koe.mac" to quit' >/dev/null 2>&1 || killall Koe 2>/dev/null || true
  sleep 1
fi

for app in /Applications/Koe.app "$HOME/Applications/Koe.app"; do
  [ -d "$app" ] || continue
  # Koe 0.1 has its own uninstaller; only Koe 2 goes here.
  [ "$(defaults read "$app/Contents/Info" CFBundleIdentifier 2>/dev/null)" = fm.koe.mac ] || continue
  rm -rf "$app" && say "removed $app"
done
defaults delete fm.koe.mac >/dev/null 2>&1 || true
support="$HOME/Library/Application Support/Koe"
[ -d "$support" ] && rm -rf "$support" && say "removed ~/Library/Application Support/Koe (the voice model, recordings, log)"
tccutil reset Microphone fm.koe.mac >/dev/null 2>&1 || true
tccutil reset Accessibility fm.koe.mac >/dev/null 2>&1 || true
say "Koe is uninstalled."
