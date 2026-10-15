#!/bin/sh
# Koe installer.
#
#   curl -fsSL koe.fm | sh
#
# Downloads the latest Koe.app from GitHub, checks that it is signed by its
# developer, puts it in /Applications (or ~/Applications) and opens it. Run it
# again to update. Koe 2 needs an Apple silicon Mac on macOS 14 or later.
#
# Options, as environment variables:
#   KOE_VERSION=2.0.0   install that release instead of the latest
#   KOE_ZIP=./Koe.zip   install from a local zip (for development)
set -eu

REPO="gwendall/koe-mac"
TEAM_ID="NQCA86NEA3" # the Developer ID that signs every release

if [ -t 1 ]; then
  bold=$(printf '\033[1m'); pink=$(printf '\033[38;5;205m'); dim=$(printf '\033[2m'); reset=$(printf '\033[0m')
else
  bold=""; pink=""; dim=""; reset=""
fi
say() { printf '%s\n' "$*"; }
fail() { printf '%s\n' "${bold}koe:${reset} $*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "Koe is a macOS app."
[ "$(id -u)" != 0 ] || fail "run this as yourself, without sudo: curl -fsSL koe.fm | sh"
# Rosetta reports x86_64 for a translated shell: ask the hardware.
[ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" = 1 ] || fail "Koe 2 needs an Apple silicon Mac (it runs on the Neural Engine)."
major=$(sw_vers -productVersion | cut -d. -f1)
[ "$major" -ge 14 ] || fail "Koe needs macOS 14 Sonoma or later (this Mac runs $(sw_vers -productVersion))."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

if [ -n "${KOE_ZIP:-}" ]; then
  cp "$KOE_ZIP" "$tmp/Koe.zip"
else
  if [ -n "${KOE_VERSION:-}" ]; then
    url="https://github.com/$REPO/releases/download/v${KOE_VERSION#v}/Koe.zip"
  else
    url="https://github.com/$REPO/releases/latest/download/Koe.zip"
  fi
  say "${pink}${bold}koe${reset} ${dim}downloading $url${reset}"
  curl -fsSL "$url" -o "$tmp/Koe.zip" || fail "could not download $url"
fi

ditto -x -k "$tmp/Koe.zip" "$tmp" || fail "the download is not a valid zip"
app="$tmp/Koe.app"
[ -d "$app" ] || fail "the zip holds no Koe.app"
codesign --verify --deep --strict "$app" 2>/dev/null || fail "Koe.app's signature does not verify, not installing it"
team=$(codesign -dv "$app" 2>&1 | sed -n 's/^TeamIdentifier=//p')
[ "$team" = "$TEAM_ID" ] || fail "Koe.app is signed by '$team', not by Koe's developer ($TEAM_ID), not installing it"

if [ -w /Applications ]; then dest=/Applications; else dest="$HOME/Applications"; mkdir -p "$dest"; fi

# A dictation under way is kept on disk and finished at the next launch.
osascript -e 'tell application id "fm.koe.mac" to quit' >/dev/null 2>&1 || true
# Koe 0.1 (fm.koe.desktop) lived at the same path: Koe 2 takes its place.
killall Koe 2>/dev/null || true
rm -rf "$dest/Koe.app"
ditto "$app" "$dest/Koe.app"
open "$dest/Koe.app"

version=$(defaults read "$dest/Koe.app/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "?")
say ""
say "  ${pink}${bold}KOE ${version}${reset} is in your menu bar, at $dest/Koe.app"
say "  Hold fn, talk, let go: your words land where your cursor is."
say ""
say "  Uninstall: curl -fsSL koe.fm/uninstall | sh"
say ""
