#!/bin/sh
# Every line the sources say through Words.say("…") is in the English table,
# and the table holds nothing the app no longer says. The shortcut's key names
# (Shortcut.swift) go through Words.say as variables: they are counted too.
#
#   scripts/strings-check.sh          exits 1 and lists the difference
set -eu
export LC_ALL=C
cd "$(dirname "$0")/.."

said=$(mktemp) table=$(mktemp)
trap 'rm -f "$said" "$table"' EXIT

perl -ne 'while (/Words\.say\("((?:[^"\\]|\\.)*)"/g) { print "$1\n" }' app/Sources/*.swift >"$said"
perl -ne 'while (/"((?:Left|Right) (?:⌘|⌥|⌃|⇧))"/g) { print "$1\n" } print "Space\n" if /49: "Space"/' app/Sources/Shortcut.swift >>"$said"
sort -u -o "$said" "$said"
perl -ne 'print "$1\n" if /^"((?:[^"\\]|\\.)*)" = /' app/Resources/en.lproj/Localizable.strings | sort -u >"$table"

untranslated=$(comm -23 "$said" "$table")
unsaid=$(comm -13 "$said" "$table")
[ -n "$untranslated" ] && printf 'not in en.lproj:\n%s\n' "$untranslated"
[ -n "$unsaid" ] && printf 'in en.lproj, said nowhere:\n%s\n' "$unsaid"
[ -z "$untranslated$unsaid" ] || exit 1
echo "the sources and en.lproj say the same $(wc -l <"$table" | tr -d ' ') lines"
