#!/bin/sh
# Campaign-3 Seal B artifact (khal): red-side sanity of the declared checker
# WITHOUT observing any khal failure. ADR 0016 requirement 2, stated
# precisely:
#
#   * every NATIVE STORE (vdir + event files) a REAL khal invocation reads
#     here is khal-written (a sealed golden event file), empty, or absent —
#     never mis-shaped. The .ics INPUTS the provenance case feeds `import`
#     are the committed hand-authored well-formed files, the documented
#     input class;
#   * checker branches that would need an ill-behaved target (bad exit
#     codes, extra/missing match lines, vdir-writing queries, hangs) are
#     exercised with a STUB binary via the checker's documented CHECK_KHAL
#     seam — the target does not run at all in those cases.
#
# Every red case pins BOTH the exit code AND the message of the leg that
# fired; the file-first/query-last structure makes a file-leg message proof
# that no query — hence no target — ran in that case.
#
# Usage (inside the pinned container, repo mounted at /work):
#   sh /work/spike/blind-hunt3/declaration/khal/checker-red-test.sh
set -u
export HOME=/tmp/blind3/home; mkdir -p "$HOME"
here=$(cd "$(dirname "$0")" && pwd)
ops=$here/ops
fails=0
n=0

expect() { # expect <want-rc> <must-contain> <label> -- [ENV=val ...]
    want=$1; msg=$2; name=$3; shift 3; [ "$1" = "--" ] && shift
    ( cd "$ops" && env "$@" ./check.sh "$LAST_OP" ) >/tmp/red.out 2>&1
    rc=$?
    n=$((n + 1))
    if [ "$rc" != "$want" ]; then
        echo "FAIL $name (rc=$rc, wanted $want)"; head -3 /tmp/red.out | sed 's/^/     | /'
        fails=$((fails + 1)); return
    fi
    if ! grep -qF "$msg" /tmp/red.out; then
        echo "FAIL $name (rc ok, but the pinned message is absent: '$msg')"
        head -3 /tmp/red.out | sed 's/^/     | /'
        fails=$((fails + 1)); return
    fi
    echo "ok   $name (rc=$rc) — $(tail -1 /tmp/red.out | cut -c1-90)"
}
reset() { # reset <op>
    LAST_OP=$1
    rm -rf "/tmp/blind3/hunt/$1"
    mkdir -p "/tmp/blind3/hunt/$1/state/cal"
}

# Stub target for branches a well-behaved binary cannot reach. Args mirror
# the checker's query legs: -c <conf> search <needle> → $4 is the needle.
stubdir=$(mktemp -d)
stub=$stubdir/khal
cat > "$stub" <<'STUB'
#!/bin/sh
needle=$4
good_line() { printf '02.09. 10:00-02.09. 11:00 GraceStandup\n'; }
case ${STUB_MODE:?} in
    rc3)        exit 3 ;;
    unanchored) printf ' 02.09. 10:00-02.09. 11:00 GraceStandup\n'; exit 0 ;;
    suffixed)   printf '02.09. 10:00-02.09. 11:00 GraceStandup extra\n'; exit 0 ;;
    twice)      good_line; good_line; exit 0 ;;
    scribble)   printf 'X' >> /tmp/blind3/hunt/import/state/cal/grace-fixed-uid-001.ics
                good_line; exit 0 ;;
    it-hang)    case $needle in Grace*) good_line; exit 0 ;; *) sleep 30 ;; esac ;;
    *) echo "stub: unknown STUB_MODE" >&2; exit 99 ;;
esac
STUB
chmod +x "$stub"

echo "== dispatch and file legs (no target runs — the pinned message proves the leg) =="
reset badop
( cd "$ops" && ./check.sh badop ) >/tmp/red.out 2>&1
rc=$?; n=$((n + 1))
if [ "$rc" = 1 ] && grep -qF "not in the declared inventory" /tmp/red.out; then
    echo "ok   red: undeclared operation refused (rc=1)"
else
    echo "FAIL undeclared op (rc=$rc)"; fails=$((fails + 1))
fi

reset import   # bystander absent — fail-closed
expect 1 "I-C: conserved event file /tmp/blind3/hunt/import/state/cal/grace-fixed-uid-001.ics is missing" \
    "red: missing conserved event file fails closed" --

reset import   # wrong-but-khal-written bytes at the bystander's name
cp "$ops/golden-ada-event.ics" /tmp/blind3/hunt/import/state/cal/grace-fixed-uid-001.ics
expect 1 "differs from its sealed golden" "red: conserved file with different khal-written bytes" --

echo "== I-Q / I-W / I-T branches (stub target — khal does not run) =="
reset import
cp "$ops/golden-grace-event.ics" /tmp/blind3/hunt/import/state/cal/grace-fixed-uid-001.ics
expect 1 "I-Q: bystander query exited 3" "red: query exit code surfaces" -- \
    CHECK_KHAL="$stub" STUB_MODE=rc3
expect 1 "expected exactly one anchored match line, got 0" "red: a leading-space line does not count" -- \
    CHECK_KHAL="$stub" STUB_MODE=unanchored
expect 1 "expected exactly one anchored match line, got 0" "red: a suffixed line does not count (grep -Fx)" -- \
    CHECK_KHAL="$stub" STUB_MODE=suffixed
expect 1 "expected exactly one anchored match line, got 2" "red: duplicate match lines counted" -- \
    CHECK_KHAL="$stub" STUB_MODE=twice
expect 1 "I-W: a query changed the vdir's bytes" "red: a vdir-writing query is caught" -- \
    CHECK_KHAL="$stub" STUB_MODE=scribble
cp "$ops/golden-grace-event.ics" /tmp/blind3/hunt/import/state/cal/grace-fixed-uid-001.ics
expect 1 "I-T: subject query did not terminate" "red: a hanging subject query times out" -- \
    CHECK_KHAL="$stub" STUB_MODE=it-hang CHECK_TIMEOUT=2

echo "== environment branch (a copied ops dir with the golden removed) =="
copydir=$(mktemp -d)
cp -R "$ops/." "$copydir/"
rm "$copydir/golden-grace-event.ics"
reset import
( cd "$copydir" && ./check.sh import ) >/tmp/red.out 2>&1
rc=$?; n=$((n + 1))
if [ "$rc" = 2 ] && grep -qF "environment: sealed golden" /tmp/red.out; then
    echo "ok   red: missing sealed golden is environment (rc=2), not a verdict"
else
    echo "FAIL missing-golden branch (rc=$rc)"; head -3 /tmp/red.out | sed 's/^/     | /'
    fails=$((fails + 1))
fi
rm -rf "$copydir"

echo "== golden provenance (the drift gate) =="
gp=$(mktemp -d)
for triple in "grace.ics grace-fixed-uid-001 golden-grace-event.ics" \
              "ada.ics ada-fixed-uid-001 golden-ada-event.ics" \
              "impostor.ics impostor-uid-001 golden-impostor-event.ics"; do
    in=$(echo "$triple" | cut -d' ' -f1); uid=$(echo "$triple" | cut -d' ' -f2); gold=$(echo "$triple" | cut -d' ' -f3)
    n=$((n + 1))
    rm -rf "$gp/v" "$gp/h"; mkdir -p "$gp/v/cal" "$gp/h"
    printf '[calendars]\n[[main]]\npath = %s/v/cal\n\n[locale]\nlocal_timezone= UTC\ndefault_timezone= UTC\ntimeformat= %%H:%%M\ndateformat= %%d.%%m.\nlongdateformat= %%d.%%m.%%Y\ndatetimeformat= %%d.%%m. %%H:%%M\nlongdatetimeformat= %%d.%%m.%%Y %%H:%%M\n' "$gp" > "$gp/gen.conf"
    HOME=$gp/h /usr/local/bin/khal -c "$gp/gen.conf" import --batch -a main "$ops/$in" < /dev/null >/dev/null 2>&1
    if cmp -s "$gp/v/cal/$uid.ics" "$ops/$gold"; then
        echo "ok   provenance: $gold is byte-what khal writes from $in"
    else
        echo "FAIL provenance: $gold drifted from what khal writes from $in"
        fails=$((fails + 1))
    fi
done
rm -rf "$gp"

echo "== the anchoring pattern against REAL khal output (both directions) =="
# The impostor store is khal-written and well-formed; querying it is
# documented-normal. Whatever khal's search-matching semantics are, the
# checker's exact-line match must reject the impostor's output and accept
# the golden's.
ip=$(mktemp -d); mkdir -p "$ip/cal" "$ip/h"
cp "$ops/golden-impostor-event.ics" "$ip/cal/impostor-uid-001.ics"
printf '[calendars]\n[[main]]\npath = %s/cal\n\n[locale]\nlocal_timezone= UTC\ndefault_timezone= UTC\ntimeformat= %%H:%%M\ndateformat= %%d.%%m.\nlongdateformat= %%d.%%m.%%Y\ndatetimeformat= %%d.%%m. %%H:%%M\nlongdatetimeformat= %%d.%%m.%%Y %%H:%%M\n' "$ip" > "$ip/probe.conf"
n=$((n + 1))
iq=$(HOME=$ip/h timeout 10 /usr/local/bin/khal -c "$ip/probe.conf" search GraceStandup < /dev/null 2>&1)
irc=$?
im=$(printf '%s\n' "$iq" | grep -Fxc "02.09. 10:00-02.09. 11:00 GraceStandup")
if [ "$irc" -eq 0 ] && [ "$im" -eq 0 ]; then
    echo "ok   red: the anchor rejects the impostor store's real output (line: $(printf '%s' "$iq" | tail -1 | cut -c1-60))"
else
    echo "FAIL impostor probe (rc=$irc, anchored matches=$im)"; fails=$((fails + 1))
fi
rm -rf "$ip"
gp2=$(mktemp -d); mkdir -p "$gp2/cal" "$gp2/h"
cp "$ops/golden-grace-event.ics" "$gp2/cal/grace-fixed-uid-001.ics"
printf '[calendars]\n[[main]]\npath = %s/cal\n\n[locale]\nlocal_timezone= UTC\ndefault_timezone= UTC\ntimeformat= %%H:%%M\ndateformat= %%d.%%m.\nlongdateformat= %%d.%%m.%%Y\ndatetimeformat= %%d.%%m. %%H:%%M\nlongdatetimeformat= %%d.%%m.%%Y %%H:%%M\n' "$gp2" > "$gp2/probe.conf"
n=$((n + 1))
gq=$(HOME=$gp2/h timeout 10 /usr/local/bin/khal -c "$gp2/probe.conf" search GraceStandup < /dev/null 2>&1)
grc=$?
gm=$(printf '%s\n' "$gq" | grep -Fxc "02.09. 10:00-02.09. 11:00 GraceStandup")
if [ "$grc" -eq 0 ] && [ "$gm" -eq 1 ]; then
    echo "ok   green control: the anchor accepts the golden store's real output"
else
    echo "FAIL golden anchor control (rc=$grc, anchored matches=$gm, out: $gq)"; fails=$((fails + 1))
fi
rm -rf "$gp2"

rm -rf "$stubdir"
echo ""
echo "red-suite: $n cases, $fails failure(s)"
[ "$fails" = 0 ]
