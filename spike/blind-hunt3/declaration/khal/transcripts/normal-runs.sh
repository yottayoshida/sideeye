#!/bin/sh
# Campaign-3 Seal B artifact (khal): one normal (non-crash) run per candidate
# form, plus determinism and interactivity probes. Permitted observation under
# ADR 0012/0016: no crash injection, no traces, no damaged stores — every vdir
# a probe touches was written by khal itself in this same script, is empty, or
# is absent; the .ics INPUT files are hand-written well-formed iCalendar, a
# documented input class (`khal import ... .ics file`). Interactivity probes
# give the child EOF on stdin, the same condition the exploration engine
# imposes.
#
# Everything is scratch under /tmp/blind3/normal; HOME points inside it so
# khal's own cache (ambient, under $HOME — observed in campaign 1) stays in
# scratch too. The config here is normal-runs-local (same shape as the sealed
# one, its calendar path pointing at the scratch vdir).
#
# Usage (inside the pinned container, repo mounted at /work):
#   sh .../normal-runs.sh > .../normal-runs.txt 2>&1
set -u
N=/tmp/blind3/normal
rm -rf "$N"
mkdir -p "$N/home"
export HOME=$N/home

say() { printf '\n===== %s =====\n' "$*"; }
run() {  # run <label> -- cmd...
    lbl=$1; shift; [ "$1" = "--" ] && shift
    printf '$ %s\n' "$*"
    "$@" < /dev/null > "$N/out.txt" 2>&1
    rc=$?
    cat "$N/out.txt"
    printf '[%s rc=%s]\n' "$lbl" "$rc"
}
tree() { # tree <dir> — names and sizes, sorted (content shown separately)
    ( cd "$1" 2>/dev/null && find . -type f -exec wc -c {} + | sort -k2 ) || echo "(absent)"
}
mkcfg() { # mkcfg <path> <vdir>
    printf '[calendars]\n[[main]]\npath = %s\n\n[locale]\nlocal_timezone= UTC\ndefault_timezone= UTC\ntimeformat= %%H:%%M\ndateformat= %%d.%%m.\nlongdateformat= %%d.%%m.%%Y\ndatetimeformat= %%d.%%m. %%H:%%M\nlongdatetimeformat= %%d.%%m.%%Y %%H:%%M\n' "$2" > "$1"
}

# One well-formed VEVENT with a FIXED UID (the import doc keys updates on the
# UID), and an updated variant of the same UID with a different SUMMARY.
cat > "$N/ada.ics" <<'EOF'
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//blind-hunt3//normal-runs//EN
BEGIN:VEVENT
UID:ada-fixed-uid-001
DTSTAMP:20260810T000000Z
DTSTART:20260901T100000Z
DTEND:20260901T110000Z
SUMMARY:AdaMeeting
END:VEVENT
END:VCALENDAR
EOF
sed 's/SUMMARY:AdaMeeting/SUMMARY:AdaMeetingMoved/; s/DTSTAMP:20260810T000000Z/DTSTAMP:20260811T000000Z/' "$N/ada.ics" > "$N/ada-v2.ics"
cat > "$N/grace.ics" <<'EOF'
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//blind-hunt3//normal-runs//EN
BEGIN:VEVENT
UID:grace-fixed-uid-001
DTSTAMP:20260810T000000Z
DTSTART:20260902T100000Z
DTEND:20260902T110000Z
SUMMARY:GraceStandup
END:VEVENT
END:VCALENDAR
EOF
say "0. inputs"
printf -- '--- ada.ics ---\n'; cat "$N/ada.ics"
printf -- '--- ada-v2.ics (same UID, new SUMMARY) ---\n'; cat "$N/ada-v2.ics"
printf -- '--- grace.ics ---\n'; cat "$N/grace.ics"

say "1. import --batch into a fresh vdir (fixed UID): filenames and determinism"
mkdir -p "$N/a/state"; mkcfg "$N/a.conf" "$N/a/state"
run import-a -- khal -c "$N/a.conf" import --batch -a main "$N/ada.ics"
printf -- '--- vdir tree after ---\n'; tree "$N/a/state"
mkdir -p "$N/b/state"; mkcfg "$N/b.conf" "$N/b/state"
run import-b -- khal -c "$N/b.conf" import --batch -a main "$N/ada.ics"
if diff -r "$N/a/state" "$N/b/state" >/dev/null 2>&1; then
    echo "two fresh imports byte-identical (diff -r): yes"
else
    echo "two fresh imports byte-identical: NO"; diff -r "$N/a/state" "$N/b/state" 2>&1 | head -5
fi
printf -- '--- event file content ---\n'
for f in "$N/a/state"/*; do [ -f "$f" ] && cat "$f"; done

say "2. import --batch of the SAME UID with a new SUMMARY (the documented update): which file changes, and determinism"
cp -R "$N/a/state" "$N/a/state.before"
run import-update -- khal -c "$N/a.conf" import --batch -a main "$N/ada-v2.ics"
printf -- '--- vdir tree after update ---\n'; tree "$N/a/state"
if diff -r "$N/a/state.before" "$N/a/state" >/dev/null 2>&1; then
    echo "update changed nothing (diff -r): unexpected"
else
    echo "update changed the store; differing files:"; diff -rq "$N/a/state.before" "$N/a/state" 2>&1 | head -5
fi
mkdir -p "$N/c/state"; mkcfg "$N/c.conf" "$N/c/state"
run import-c1 -- khal -c "$N/c.conf" import --batch -a main "$N/ada.ics"
run import-c2 -- khal -c "$N/c.conf" import --batch -a main "$N/ada-v2.ics"
if diff -r "$N/a/state" "$N/c/state" >/dev/null 2>&1; then
    echo "import+update reproduced byte-identically in a second vdir: yes"
else
    echo "import+update NOT byte-identical across vdirs:"; diff -rq "$N/a/state" "$N/c/state" 2>&1 | head -5
fi

say "3. new (campaign-1 observed a randomly named .ics): two fresh runs, both files shown, clock referenced"
printf -- 'reference clock before: %s\n' "$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$N/d/state"; mkcfg "$N/d.conf" "$N/d/state"
run new-d -- khal -c "$N/d.conf" new -a main 01.09.2026 10:00 01.09.2026 11:00 TeamMeeting
mkdir -p "$N/e/state"; mkcfg "$N/e.conf" "$N/e/state"
run new-e -- khal -c "$N/e.conf" new -a main 01.09.2026 10:00 01.09.2026 11:00 TeamMeeting
printf -- 'reference clock after: %s\n' "$(date -u +%Y%m%dT%H%M%SZ)"
printf -- '--- vdir tree d ---\n'; tree "$N/d/state"
printf -- '--- vdir tree e ---\n'; tree "$N/e/state"
printf -- '--- file from run d ---\n'
for f in "$N/d/state"/*; do [ -f "$f" ] && cat "$f"; done
printf -- '--- file from run e ---\n'
for f in "$N/e/state"/*; do [ -f "$f" ] && cat "$f"; done
df_=$(ls "$N/d/state"); ef_=$(ls "$N/e/state")
[ "$df_" = "$ef_" ] && echo "filenames identical across runs: yes" || echo "filenames identical across runs: NO ($df_ vs $ef_)"
if cmp -s "$N/d/state/$df_" "$N/e/state/$ef_"; then
    echo "file BYTES identical across runs (names aside): yes"
else
    echo "file BYTES identical across runs (names aside): NO"
fi
for pair in "d $df_" "e $ef_"; do
    v=${pair% *}; fn=${pair#* }
    uid=$(sed -n 's/^UID://p' "$N/$v/state/$fn" | tr -d '\r')
    base=${fn%.ics}
    [ "$uid" = "$base" ] && echo "run $v: UID equals filename stem: yes ($uid)" \
                         || echo "run $v: UID equals filename stem: NO (uid=$uid file=$fn)"
done

say "4. query probes over the imported vdir (a: Ada updated + Grace below)"
run import-grace -- khal -c "$N/a.conf" import --batch -a main "$N/grace.ics"
cp -R "$N/a/state" "$N/a/state.q-before"
run list-range   -- khal -c "$N/a.conf" list 01.09.2026 03.09.2026
run search-hit   -- khal -c "$N/a.conf" search GraceStandup
run search-miss  -- khal -c "$N/a.conf" search NoSuchEvent
if diff -r "$N/a/state.q-before" "$N/a/state" >/dev/null 2>&1; then
    echo "queries changed no byte of the vdir: confirmed (diff -r)"
else
    echo "queries CHANGED the vdir:"; diff -rq "$N/a/state.q-before" "$N/a/state" | head -5
fi
printf -- '--- where khal keeps its ambient cache (under scratch HOME) ---\n'
( cd "$HOME" && find . -type f | sort | head -5 )

say "5. queries over empty and absent vdirs"
mkdir -p "$N/f/state"; mkcfg "$N/f.conf" "$N/f/state"
run list-empty -- khal -c "$N/f.conf" list 01.09.2026 03.09.2026
mkcfg "$N/g.conf" "$N/g/state-never-created"
[ -e "$N/g/state-never-created" ] && echo "PRE-CHECK FAILED: the absent vdir already exists" || echo "pre-check: the configured vdir does not exist"
run list-absent -- khal -c "$N/g.conf" list 01.09.2026 03.09.2026
if [ -d "$N/g/state-never-created" ]; then
    echo "filesystem check: the vdir NOW EXISTS (list created it); contents: $(ls -A "$N/g/state-never-created" | wc -l | tr -d ' ') entries"
else
    echo "filesystem check: the vdir still does not exist"
fi

say "6. interactivity probes (EOF stdin, 10s timeout; the engine gives no stdin)"
run import-ask -- timeout 10 khal -c "$N/a.conf" import -a main "$N/ada.ics"
run import-stdin -- timeout 10 khal -c "$N/a.conf" import --batch -a main
run edit-probe -- timeout 10 khal -c "$N/a.conf" edit GraceStandup
run interactive-probe -- timeout 10 khal -c "$N/a.conf" interactive
run configure-probe -- timeout 10 khal configure

say "7. package identity"
pip3 show khal 2>/dev/null | sed -n '1,2p'
echo "normal-runs: done"
