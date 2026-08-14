#!/bin/sh
# Campaign-2 Seal B artifact (abook): red-side sanity of the declared checker
# WITHOUT observing any abook failure. The khard burn's structural rule,
# applied twice over (stated precisely — R1 of this declaration caught the
# blanket form overclaiming):
#
#   * every NATIVE STORE a REAL abook invocation reads here is abook-written
#     (a sealed golden), empty, or absent — never mis-shaped. The vCard
#     INPUTS the provenance case feeds --convert are the committed
#     hand-authored well-formed files, the same documented-normal input class
#     the normal runs recorded (vcard is a documented informat);
#   * checker branches that would need an ill-behaved target (bad exit codes,
#     extra/missing match lines, byte-writing queries, hangs) are exercised
#     with a STUB binary via the checker's documented CHECK_ABOOK seam — the
#     target does not run at all in those cases.
#
# Every red case pins BOTH the exit code AND the message of the leg that
# fired (the khard R1 lesson: an unpinned red is green for the wrong reason),
# and the file-first/query-last structure makes a file-leg message proof that
# no query — hence no target — ran in that case.
#
# Usage (inside the pinned container, repo mounted at /work):
#   sh /work/spike/blind-hunt2/declaration/abook/checker-red-test.sh
set -u
export HOME=/tmp/blind2/home; mkdir -p "$HOME"
here=$(cd "$(dirname "$0")" && pwd)
ops=$here/ops
tab=$(printf '\t')
fails=0
n=0

expect() { # expect <want-rc> <must-contain> <label> -- [ENV=val ...] op
    want=$1; msg=$2; name=$3; shift 3; [ "$1" = "--" ] && shift
    ( cd "$ops" && env "$@" sh ./check.sh "$LAST_OP" ) >/tmp/red.out 2>&1
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
    rm -rf "/tmp/blind2/hunt/$1"
    mkdir -p "/tmp/blind2/hunt/$1/state"
}

# ---- a stub target for the branches a well-behaved binary cannot reach.
# MODE selects the misbehavior; the conserved-store query is answered
# correctly in I-T modes so the failure lands on the leg under test.
stubdir=$(mktemp -d)
stub=$stubdir/abook
cat > "$stub" <<'STUB'
#!/bin/sh
# Red-suite stub. Args mirror the checker's query legs:
#   --datafile <file> --mutt-query <needle>
df=$2; needle=$4
good_line() { printf '\ngrace@example.com\tGrace Hopper\t \n'; }
case ${STUB_MODE:?} in
    rc3)        exit 3 ;;
    unanchored) printf '\n grace@example.com\tGrace Hopper\t \n'; exit 0 ;;
    twice)      good_line; good_line; exit 0 ;;
    scribble)   printf 'X' >> "$df"; good_line; exit 0 ;;
    it-rc7)     case $needle in grace@*) good_line; exit 0 ;; *) exit 7 ;; esac ;;
    it-hang)    case $needle in grace@*) good_line; exit 0 ;; *) sleep 30 ;; esac ;;
    it-create)  case $needle in grace@*) good_line; exit 0 ;;
                *) printf 'made\n' > "$df"; printf 'Not found\n'; exit 1 ;; esac ;;
    it-scribble) case $needle in grace@*) good_line; exit 0 ;;
                *) printf 'X' >> "$df"; printf 'Not found\n'; exit 1 ;; esac ;;
    *) echo "stub: unknown STUB_MODE" >&2; exit 99 ;;
esac
STUB
chmod +x "$stub"

echo "== dispatch and file legs (no target runs — the pinned message proves the leg) =="
reset badop
( cd "$ops" && sh ./check.sh badop ) >/tmp/red.out 2>&1
rc=$?; n=$((n + 1))
if [ "$rc" = 1 ] && grep -qF "not in the declared inventory" /tmp/red.out; then
    echo "ok   red: undeclared operation refused (rc=1)"
else
    echo "FAIL undeclared op (rc=$rc)"; fails=$((fails + 1))
fi

reset import   # conserved store absent — fail-closed, not fail-open
mkdir -p /tmp/blind2/hunt/import/state/keep /tmp/blind2/hunt/import/state/book
expect 1 "I-C: conserved store /tmp/blind2/hunt/import/state/keep/addressbook is missing" \
    "red: missing conserved store fails closed" --

reset import   # wrong-but-well-formed store (abook-written golden-pair in keep)
mkdir -p /tmp/blind2/hunt/import/state/keep /tmp/blind2/hunt/import/state/book
cp "$ops/golden-pair.addressbook" /tmp/blind2/hunt/import/state/keep/addressbook
expect 1 "differs from its sealed golden" "red: conserved store with different abook-written bytes" --

echo "== I-Q branches (stub target — abook does not run) =="
reset export
mkdir -p /tmp/blind2/hunt/export/state/book
cp "$ops/golden-pair.addressbook" /tmp/blind2/hunt/export/state/book/addressbook
expect 1 "I-Q: bystander query exited 3" "red: query exit code surfaces" -- \
    CHECK_ABOOK="$stub" STUB_MODE=rc3
expect 1 "expected exactly one anchored match line, got 0" "red: unanchored line does not count" -- \
    CHECK_ABOOK="$stub" STUB_MODE=unanchored
expect 1 "expected exactly one anchored match line, got 2" "red: duplicate match lines counted" -- \
    CHECK_ABOOK="$stub" STUB_MODE=twice
expect 1 "I-Q: the query changed the conserved store's bytes" "red: a writing query is caught" -- \
    CHECK_ABOOK="$stub" STUB_MODE=scribble
# scribble mutated the store; restore it for any later case
cp "$ops/golden-pair.addressbook" /tmp/blind2/hunt/export/state/book/addressbook

echo "== I-T branches (stub target; conserved leg answered correctly) =="
reset import
mkdir -p /tmp/blind2/hunt/import/state/keep /tmp/blind2/hunt/import/state/book
cp "$ops/golden-grace.addressbook" /tmp/blind2/hunt/import/state/keep/addressbook
expect 1 "I-T: outfile query exited 7, outside the observed-normal {0,1}" "red: outfile query exit outside {0,1}" -- \
    CHECK_ABOOK="$stub" STUB_MODE=it-rc7
expect 1 "outside the observed-normal {0,1}" "red: a hanging outfile query times out (rc 124)" -- \
    CHECK_ABOOK="$stub" STUB_MODE=it-hang CHECK_TIMEOUT=2
expect 1 "I-T: the query created the outfile" "red: a query that creates the outfile is caught" -- \
    CHECK_ABOOK="$stub" STUB_MODE=it-create
cp "$ops/golden-grace.addressbook" /tmp/blind2/hunt/import/state/book/addressbook
expect 1 "I-T: the query changed the outfile's bytes" "red: a query that writes the outfile is caught" -- \
    CHECK_ABOOK="$stub" STUB_MODE=it-scribble

echo "== environment branch (a copied ops dir with the golden removed) =="
copydir=$(mktemp -d)
cp -R "$ops/." "$copydir/"
rm "$copydir/golden-grace.addressbook"
reset import
mkdir -p /tmp/blind2/hunt/import/state/keep /tmp/blind2/hunt/import/state/book
( cd "$copydir" && sh ./check.sh import ) >/tmp/red.out 2>&1
rc=$?; n=$((n + 1))
if [ "$rc" = 2 ] && grep -qF "environment: sealed golden" /tmp/red.out; then
    echo "ok   red: missing sealed golden is environment (rc=2), not a verdict"
else
    echo "FAIL missing-golden branch (rc=$rc)"; head -3 /tmp/red.out | sed 's/^/     | /'
    fails=$((fails + 1))
fi
rm -rf "$copydir"

echo "== golden provenance (the drift gate R1 asked for) =="
# The committed goldens must BE what abook writes from the committed inputs —
# regenerated here into scratch and byte-compared, so a changed input or a
# changed generator output cannot silently re-baseline the fixtures.
gp=$(mktemp -d)
for pair in "grace.vcf golden-grace.addressbook" "pair.vcf golden-pair.addressbook" "impostor.vcf golden-impostor.addressbook"; do
    in=${pair% *}; gold=${pair#* }
    n=$((n + 1))
    rm -f "$gp/g"
    /usr/bin/abook --convert --informat vcard --infile "$ops/$in" \
        --outformat abook --outfile "$gp/g" < /dev/null >/dev/null 2>&1
    if [ $? -eq 0 ] && cmp -s "$gp/g" "$ops/$gold"; then
        echo "ok   provenance: $gold is byte-what abook writes from $in"
    else
        echo "FAIL provenance: $gold drifted from what abook writes from $in"
        fails=$((fails + 1))
    fi
done
rm -rf "$gp"

echo "== the anchoring pattern against REAL abook output (both directions) =="
# The impostor store is abook-written and well-formed; querying it is
# documented-normal. Its match line must NOT satisfy the checker's anchor.
n=$((n + 1))
iq=$(timeout 10 /usr/bin/abook --datafile "$ops/golden-impostor.addressbook" --mutt-query grace@example.com < /dev/null 2>&1)
irc=$?
im=$(printf '%s\n' "$iq" | grep -c "^grace@example.com${tab}Grace Hopper${tab}")
if [ "$irc" -eq 0 ] && [ "$im" -eq 0 ]; then
    echo "ok   red: the anchor rejects the impostor's real match line ($(printf '%s' "$iq" | tail -1 | cut -c1-60))"
else
    echo "FAIL impostor probe (rc=$irc, anchored matches=$im)"; fails=$((fails + 1))
fi
n=$((n + 1))
gq=$(timeout 10 /usr/bin/abook --datafile "$ops/golden-grace.addressbook" --mutt-query grace@example.com < /dev/null 2>&1)
grc=$?
gm=$(printf '%s\n' "$gq" | grep -c "^grace@example.com${tab}Grace Hopper${tab}")
if [ "$grc" -eq 0 ] && [ "$gm" -eq 1 ]; then
    echo "ok   green control: the anchor accepts the golden's real match line"
else
    echo "FAIL golden anchor control (rc=$grc, anchored matches=$gm)"; fails=$((fails + 1))
fi

rm -rf "$stubdir"
echo ""
echo "red-suite: $n cases, $fails failure(s)"
[ "$fails" = 0 ]
