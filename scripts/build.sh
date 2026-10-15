#!/bin/sh
# Builds build/Koe.app for Apple silicon (Parakeet Ultra runs on the Neural
# Engine): the app, llama.cpp's framework, its icon, the pixel font, signed.
#
#   scripts/build.sh                  sign with this Mac's Developer ID, or ad hoc without one
#   SIGN=- scripts/build.sh           sign ad hoc (enough to run it on this Mac)
#   VERSION=2.0.0 scripts/build.sh    stamp that version
set -eu
cd "$(dirname "$0")/.."

# APP=<path>.app builds elsewhere (scripts/test.sh does, beside a Koe in use).
APP=${APP:-build/Koe.app}
# Never under a running Koe: macOS would stop trusting it while it still holds
# the keyboard, and the Mac would stop answering keys and clicks.
if pgrep -f "$(pwd)/$APP/Contents/MacOS/Koe" >/dev/null 2>&1 || pgrep -f "^$APP/Contents/MacOS/Koe" >/dev/null 2>&1; then
  echo "build: $APP is running. Quit Koe first (or set APP= to build elsewhere)." >&2
  exit 1
fi
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp app/Info.plist "$APP/Contents/Info.plist"
cp -R app/Resources/* "$APP/Contents/Resources/"

plist="$APP/Contents/Info.plist"
# The version: VERSION's, else the last release's tag, so a local build
# reads as the release it comes from (and never as an older one that would
# try to update itself over a build from source).
version=${VERSION:-$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)}
if [ -n "$version" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${version#v}" "$plist"
fi
build_number=$(git rev-list --count HEAD 2>/dev/null || echo 1)
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$plist"

# KOE_EVAL=1: adds the eval door (Koe.swift); never for a release.
eval_flags=
[ "${KOE_EVAL:-}" = 1 ] && eval_flags="-Xswiftc -DKOE_EVAL"
# shellcheck disable=SC2086
swift build -c release --arch arm64 --force-resolved-versions $eval_flags
cp .build/arm64-apple-macosx/release/Koe "$APP/Contents/MacOS/Koe"
# llama.cpp, for polishing (app/Sources/Polish.swift): its Apple silicon half.
mkdir -p "$APP/Contents/Frameworks"
ditto .build/arm64-apple-macosx/release/llama.framework "$APP/Contents/Frameworks/llama.framework"
lib="$APP/Contents/Frameworks/llama.framework/Versions/A/llama"
lipo "$lib" -thin arm64 -output "$lib.arm64" && mv "$lib.arm64" "$lib"
swift scripts/icon.swift "$APP/Contents/Resources" >/dev/null
rm -f "$APP/Contents/Resources/icon-1024.png"

identity=${SIGN:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}
# No Developer ID: a local self-signed "Koe Local Development" certificate,
# if this Mac has one, keeps macOS's permissions across rebuilds (an ad hoc
# signature is a new app to macOS each time).
if [ -z "$identity" ] && security find-identity -p codesigning | grep -q '"Koe Local Development"'; then
  codesign --force --options runtime --sign "Koe Local Development" "$APP/Contents/Frameworks/llama.framework"
  codesign --force --options runtime --entitlements app/Koe-local.entitlements --sign "Koe Local Development" --identifier fm.koe.mac "$APP"
  codesign --verify --deep --strict "$APP" 2>/dev/null || true
  echo "built $APP (signed with Koe Local Development: permissions survive rebuilds)"
  exit 0
fi
if [ -z "$identity" ] || [ "$identity" = "-" ]; then
  codesign --force --sign - "$APP/Contents/Frameworks/llama.framework"
  codesign --force --sign - --identifier fm.koe.mac "$APP"
  echo "built $APP (signed ad hoc: runs on this Mac only)"
else
  for attempt in 1 2 3; do
    codesign --force --options runtime --timestamp --sign "$identity" "$APP/Contents/Frameworks/llama.framework" &&
      codesign --force --options runtime --timestamp --entitlements app/Koe.entitlements --sign "$identity" "$APP" && break
    [ "$attempt" = 3 ] && exit 1
    echo "signing failed, retrying in 10 s"
    sleep 10
  done
  echo "built $APP (signed by $identity)"
fi
codesign --verify --deep --strict "$APP"
