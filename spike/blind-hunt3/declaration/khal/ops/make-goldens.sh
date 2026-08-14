#!/bin/sh
# Campaign-3 Seal B artifact (khal): regenerates the committed golden EVENT
# files from the committed .ics inputs, via khal itself inside the pinned
# container — the fixtures are khal's own serialization (byte-deterministic
# for fixed-UID imports, normal-runs §1), not a hand-imitation. This script
# OVERWRITES the committed goldens; the gate against a silent re-baseline is
# the red suite's provenance case, which regenerates all three into scratch
# and byte-compares against the committed files on every run.
#
# Usage (inside the pinned container, repo mounted at /work):
#   sh /work/spike/blind-hunt3/declaration/khal/ops/make-goldens.sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
export HOME=$t/home

gen() { # gen <in.ics> <uid> <out-name>
    rm -rf "$t/v"; mkdir -p "$t/v/cal"
    printf '[calendars]\n[[main]]\npath = %s/v/cal\n\n[locale]\nlocal_timezone= UTC\ndefault_timezone= UTC\ntimeformat= %%H:%%M\ndateformat= %%d.%%m.\nlongdateformat= %%d.%%m.%%Y\ndatetimeformat= %%d.%%m. %%H:%%M\nlongdatetimeformat= %%d.%%m.%%Y %%H:%%M\n' "$t" > "$t/gen.conf"
    khal -c "$t/gen.conf" import --batch -a main "$here/$1" < /dev/null > /dev/null 2>&1
    cp "$t/v/cal/$2.ics" "$here/$3"
    printf '%s <- %s (event file %s.ics)\n' "$3" "$1" "$2"
}
gen grace.ics    grace-fixed-uid-001 golden-grace-event.ics
gen ada.ics      ada-fixed-uid-001   golden-ada-event.ics
gen impostor.ics impostor-uid-001    golden-impostor-event.ics
sha256sum "$here"/golden-*.ics
