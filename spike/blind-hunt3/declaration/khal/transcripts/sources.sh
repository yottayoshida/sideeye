#!/bin/sh
# Campaign-3 Seal B artifact (khal): permitted-source transcripts, regenerated
# by this script inside the pinned container (ADR 0012 source rules via ADR
# 0015/0016). Sources are the target's own --help output — the top-level help
# and every listed command's help — plus the version and package identity.
# khal is pip-installed and ships no man pages; its web documentation is
# consulted (and transcribed) separately if needed, with its own provenance.
# No source code, no traces, no bug trackers.
#
# Usage (inside the pinned container, repo mounted at /work):
#   sh /work/spike/blind-hunt3/declaration/khal/transcripts/sources.sh
set -eu
out=/work/spike/blind-hunt3/declaration/khal/transcripts

prov=$out/sources-provenance.txt
: > "$prov"
note() { printf '%s\n' "$*" | tee -a "$prov"; }

note "package: khal $(pip3 show khal 2>/dev/null | sed -n 's/^Version: //p') (pip3 show)"
note "binary: $(command -v khal) (what bare 'khal' resolves to; the sealed invocation names /usr/local/bin/khal)"
note "khal --version: $(khal --version 2>&1)"
# "ships no man pages" is a probe result, not an assumption (campaign-3 R1):
manhits=$(find /usr/share/man /usr/local/share/man -name 'khal*' 2>/dev/null | wc -l | tr -d ' ')
note "man-page probe: $manhits file(s) matching khal* under /usr/share/man and /usr/local/share/man; man khal => $(man khal 2>&1 | head -1)"

khal --help > "$out/help.txt" 2>&1
note "help.txt: rc=$? ($(wc -l < "$out/help.txt" | tr -d ' ') lines)"

for cmd in at calendar configure edit import interactive list new \
           printcalendars printformats printics search; do
    khal "$cmd" --help > "$out/help-$cmd.txt" 2>&1
    note "help-$cmd.txt: rc=$? ($(wc -l < "$out/help-$cmd.txt" | tr -d ' ') lines)"
done

for f in "$out"/help*.txt; do
    [ -s "$f" ] || { echo "FATAL: $f is empty" >&2; exit 1; }
done
note "sources: all transcripts non-empty"
