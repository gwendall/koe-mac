#!/bin/sh
# Builds build/Koe.app for Apple silicon (Parakeet Ultra runs on the Neural
# Engine): the app, its icon, the pixel font, signed.
#
#   scripts/build.sh                  sign with this Mac's Developer ID, or ad hoc without one
#   SIGN=- scripts/build.sh           sign ad hoc (enough to run it on this Mac)
#   VERSION=2.0.0 scripts/build.sh    stamp that version
set -eu
cd "$(dirname "$0")/.."

APP=build/Koe.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp app/Info.plist "$APP/Contents/Info.plist"
cp app/Resources/* "$APP/Contents/Resources/"

plist="$APP/Contents/Info.plist"
if [ -n "${VERSION:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION#v}" "$plist"
fi
build_number=$(git rev-list --count HEAD 2>/dev/null || echo 1)
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$plist"

swift build -c release --arch arm64 --force-resolved-versions
cp .build/arm64-apple-macosx/release/Koe "$APP/Contents/MacOS/Koe"
swift scripts/icon.swift "$APP/Contents/Resources" >/dev/null
rm -f "$APP/Contents/Resources/icon-1024.png"

identity=${SIGN:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}
if [ -z "$identity" ] || [ "$identity" = "-" ]; then
  codesign --force --sign - --identifier fm.koe.mac "$APP"
  echo "built $APP (signed ad hoc: runs on this Mac only)"
else
  for attempt in 1 2 3; do
    codesign --force --options runtime --timestamp --sign "$identity" "$APP" && break
    [ "$attempt" = 3 ] && exit 1
    echo "signing failed, retrying in 10 s"
    sleep 10
  done
  echo "built $APP (signed by $identity)"
fi
codesign --verify --deep --strict "$APP"
