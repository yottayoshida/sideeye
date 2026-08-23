#!/bin/sh
# What the world outside himalaya does with the empty message — the three
# things external-recovery.txt wrote down as NOT MEASURED, plus the fourth
# it left open (emptying the trash). #272.
#
# This is a leg-external, non-claim measurement. PROTOCOL.md's Reporting
# section puts it outside claim eligibility on purpose: it decides nothing
# about criterion 1 and everything about what the report may honestly say
# about severity.
#
# TWO IMAGES, ON PURPOSE. The damage is produced by sideeye-cohort4
# untouched — the stock reproduction's shape, one strace injection, no
# shim, no engine, no seccomp, no interposer — into a bind mount. The
# syncer and the readers run in a separate image that never contains the
# target. The pinned himalaya is a glibc-dynamic self-build, and adding a
# mail stack on top of its image would pull dependencies able to replace
# the shared libraries it resolves against; that would silently change
# what "the measured target" means. Image ids and versions are recorded
# below rather than trusted.
#
# EVERY LEG CARRIES ITS CONTROL. A run whose sync is simply broken would
# report "the empty entry did not arrive", which is indistinguishable from
# a real negative. So no sentence about the empty entry is written unless
# the healthy message travelled the same path in the same run.
#
# The first version of this also required the syncer's own output to name
# the damaged file. mbsync names no individual file at any verbosity
# tried, so that guard failed on its first real run — correctly, because
# identifying the arrivals by size is an inference. It is replaced by
# isolation: each entry is carried ALONE, so a count of one is about that
# entry and nothing else. Identification by size survives only as the
# combined run's narration, never as a marker a guard reads.
#
# --selftest drives each guard through the same predicate the run uses and
# requires the specific diagnostic, not merely a non-zero exit.
set -u

C4_IMAGE=${C4_IMAGE:-sideeye-cohort4:latest}
TOOLS_IMAGE=${TOOLS_IMAGE:-sideeye-c4-tools:latest}
MSGID='1700000000.#0M0P1.probehost'
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

fails=0
ok()  { echo "ok   $*"; }
bad() { echo "FAIL $*"; fails=$((fails + 1)); }

# --- production predicates (the selftest drives these, not copies) ------

# The named thing must appear in the tool's own output. Used for the one
# claim that matters: that the syncer looked at THIS file.
assert_contains() { # <file> <needle> <label>
    if [ ! -s "$1" ]; then
        bad "$3: the output file is empty or missing, so nothing was measured"
        return 1
    fi
    if grep -qF -- "$2" "$1"; then
        ok "$3: the output names $2"
        return 0
    fi
    bad "$3: the output does not name $2"
    return 1
}

# rc taken from the command, never through a pipe. This repository has
# recorded that trap nine times, and this run hit it once more before the
# guard existed.
assert_rc() { # <got> <want> <label>
    if [ "$1" = "$2" ]; then
        ok "$3: rc=$1 as required"
        return 0
    fi
    bad "$3: rc=$1, required $2"
    return 1
}

# An input this script cannot produce for itself. Absence must name the
# way to obtain it rather than degrade the measurement silently.
require_input() { # <path> <how-to-get-it>
    if [ -e "$1" ]; then
        ok "input present: $1"
        return 0
    fi
    bad "input missing: $1 — obtain it with: $2"
    return 1
}

# The source read for the help audit must be the pinned tree, not whatever
# is on the disk.
assert_digest() { # <actual> <expected> <label>
    if [ "$1" = "$2" ]; then
        ok "$3: digest matches the committed pin"
        return 0
    fi
    bad "$3: digest $1 does not match the committed pin $2"
    return 1
}

# --- selftest -----------------------------------------------------------

if [ "${1:-}" = "--selftest" ]; then
    echo "== selftest: every guard driven through the predicate the run uses"
    sfail=0
    d=$(mktemp -d "$HOME/outward-selftest-XXXXXX") || d=""
    [ -n "$d" ] && [ -d "$d" ] || { echo "selftest cannot run: mktemp -d failed" >&2; exit 2; }
    printf 'some output naming NOTHING useful\n' > "$d/present.txt"
    : > "$d/empty.txt"

    # Each drill runs the SAME function the run uses, in a subshell so its
    # failure counter cannot leak, and requires the specific diagnostic —
    # a guard that merely returns non-zero could be refusing for any reason.
    expect_refusal() { # <label> <fragment> ; predicate call on stdin-free args
        lbl=$1; frag=$2; out=$3
        if grep -q "^FAIL" "$out" && grep -qF -- "$frag" "$out"; then
            echo "selftest ok   $lbl: refused, and said \"$frag\""
        else
            echo "selftest FAIL $lbl: expected a refusal saying \"$frag\", got: $(tr '\n' ' ' < "$out")"
            sfail=$((sfail + 1))
        fi
    }

    # 1. the needle is absent from a non-empty output
    ( fails=0; assert_contains "$d/present.txt" "the-damaged-name" "drill" ) > "$d/o1" 2>&1
    expect_refusal "contains-missing" "does not name" "$d/o1"

    # 2. the output file is empty — "measured nothing" must not read as "not found"
    ( fails=0; assert_contains "$d/empty.txt" "anything" "drill" ) > "$d/o2" 2>&1
    expect_refusal "contains-empty" "nothing was measured" "$d/o2"

    # 3. rc mismatch, with both values printed
    ( fails=0; assert_rc 1 0 "drill" ) > "$d/o3" 2>&1
    expect_refusal "rc-mismatch" "rc=1, required 0" "$d/o3"

    # 4. a missing input must name how to obtain it
    ( fails=0; require_input "$d/no-such-tree" "spike/cohort4/fetch-artifacts.sh" ) > "$d/o4" 2>&1
    expect_refusal "missing-input" "obtain it with: spike/cohort4/fetch-artifacts.sh" "$d/o4"

    # 5. digest mismatch
    ( fails=0; assert_digest "deadbeef" "f036686d" "drill" ) > "$d/o5" 2>&1
    expect_refusal "digest-mismatch" "does not match the committed pin" "$d/o5"

    # 6. the good case, so the guards are not simply always-red
    ( fails=0; assert_rc 0 0 "drill"; assert_digest "abc" "abc" "drill" ) > "$d/o6" 2>&1
    if grep -q "^FAIL" "$d/o6"; then
        echo "selftest FAIL good-case: a correct input was refused"; sfail=$((sfail + 1))
    else
        echo "selftest ok   good-case: correct input accepted by both predicates"
    fi

    rm -rf "$d" 2>/dev/null || /usr/bin/trash "$d" 2>/dev/null || true
    echo "== selftest failures: $sfail"
    [ "$sfail" -eq 0 ] || exit 1
    exit 0
fi

# --- the run ------------------------------------------------------------

# An unchecked mktemp leaves WORK empty and every path below becomes a
# root-level one — /c4, /gen.txt. Refuse rather than measure somewhere else.
WORK=$(mktemp -d "$HOME/outward-reach-XXXXXX") || WORK=""
if [ -z "$WORK" ] || [ ! -d "$WORK" ]; then
    echo "cannot run: mktemp -d under \$HOME failed, so there is nowhere to work" >&2
    exit 2
fi
trap 'rm -rf "$WORK" 2>/dev/null || /usr/bin/trash "$WORK" 2>/dev/null || true' EXIT

echo "== apparatus, recorded rather than trusted"
echo "   damage image:  $C4_IMAGE  $(docker image inspect -f '{{.Id}}' "$C4_IMAGE" 2>/dev/null | cut -c1-19)"
echo "   tools image:   $TOOLS_IMAGE  $(docker image inspect -f '{{.Id}}' "$TOOLS_IMAGE" 2>/dev/null | cut -c1-19)"
echo "   target binary: $(docker run --rm "$C4_IMAGE" sh -c 'himalaya --version | head -1; sha256sum "$(command -v himalaya)" | cut -c1-16' 2>/dev/null | tr '\n' ' ')"
docker run --rm "$TOOLS_IMAGE" cat /versions.txt 2>/dev/null | sed 's/^/   tool: /'

echo ""
echo "=============================================================="
echo "Producing the damage: the stock shape, in the untouched image."
echo "=============================================================="
mkdir -p "$WORK/c4"
docker run --rm -v "$WORK/c4":/tmp/cohort4 -v "$here/ops":/ops:ro "$C4_IMAGE" sh -c '
    set -u
    # The apparatus-absence claim is checked here rather than asserted in
    # prose, the way stock-reproduction.sh checks it.
    [ -e /etc/ld.so.preload ] && { echo "   FAIL: /etc/ld.so.preload exists"; exit 1; }
    echo "   apparatus absent: no /etc/ld.so.preload, LD_PRELOAD=${LD_PRELOAD:-<unset>}"
    /ops/setup.sh
    C=/tmp/cohort4/himalaya/config.toml
    strace -f -e trace=copy_file_range -e inject=copy_file_range:signal=KILL:when=1 \
        himalaya -c $C maildir messages copy "'"$MSGID"'" --maildir . --target Archive >/dev/null 2>&1
    echo "   killed copy rc=$? (137 = the injected signal landed)"
    himalaya -c $C maildir messages copy "'"$MSGID"'" --maildir . --target Archive >/dev/null 2>&1
    echo "   completed copy rc=$? (the healthy control, made by letting the same operation finish)"
' > "$WORK/gen.txt" 2>&1
gen_rc=$?
cat "$WORK/gen.txt"
assert_rc "$gen_rc" 0 "generation ran"

DAMAGED=""; HEALTHY=""
for f in "$WORK"/c4/himalaya/store/Archive/cur/*; do
    [ -e "$f" ] || continue
    b=$(wc -c < "$f" | tr -d ' ')
    echo "   $(basename "$f") = $b bytes"
    [ "$b" -eq 0 ] && DAMAGED=$(basename "$f")
    [ "$b" -gt 0 ] && HEALTHY=$(basename "$f")
done
[ -n "$DAMAGED" ] && ok "the damaged entry exists: $DAMAGED" || bad "no 0-byte entry was produced — the rest measures nothing"
[ -n "$HEALTHY" ] && ok "the healthy control exists: $HEALTHY" || bad "no healthy control was produced"

echo ""
echo "=============================================================="
echo "S1. Does an external syncer carry the empty message outward?"
echo "=============================================================="
echo "   isync, Maildir on both sides. mbsync --dry-run is not usable here:"
echo "   against a Maildir near store it aborts on"
echo "   maildir_find_new_msgs: Assertion 'DFlags & FAKEDUMBSTORE' failed."
echo "   So this is a real sync into a scratch far side."
docker run --rm -v "$WORK/c4":/store:ro -v "$here":/legs:ro "$TOOLS_IMAGE" \
    sh /legs/legs/sync-maildir.sh > "$WORK/s1.txt" 2>&1
s1_rc=$?
cat "$WORK/s1.txt"
assert_rc "$s1_rc" 0 "S1 ran"
assert_contains "$WORK/s1.txt" "near side: 2 messages" "S1 the syncer counted both entries as messages"
assert_contains "$WORK/s1.txt" "FAR-CONTROL-ARRIVED" "S1 positive control: the healthy message reached the far side"
assert_contains "$WORK/s1.txt" "FAR-EMPTY-ARRIVED" "S1 the empty entry reached the far side"
# mbsync names no individual file at any verbosity tried, so the combined
# run identifies the two arrivals by size — an inference. These two require
# the isolated syncs, where the far side's count is about one entry only.
assert_contains "$WORK/s1.txt" "ISOLATED-EMPTY-TRAVELLED" "S1 the empty entry travels when it is the only thing there"
assert_contains "$WORK/s1.txt" "ISOLATED-CONTROL-TRAVELLED" "S1 positive control travels under the same isolation"

echo ""
echo "=============================================================="
echo "S2. Does a real IMAP server accept it?"
echo "=============================================================="
echo "   Asked only because S1 answered yes. If the syncer had declined to"
echo "   carry the entry, no server would need to be stood up to know that."
docker run --rm -v "$WORK/c4":/store:ro -v "$here":/legs:ro "$TOOLS_IMAGE" \
    sh /legs/legs/sync-imap.sh > "$WORK/s2.txt" 2>&1
s2_rc=$?
cat "$WORK/s2.txt"
assert_rc "$s2_rc" 0 "S2 ran"
if grep -q "S2-NOT-MEASURED" "$WORK/s2.txt"; then
    # Not a soft outcome. A run that cannot answer the server question must
    # not be green, because the record's sentence about the server is
    # written from this transcript.
    bad "S2 NOT MEASURED: the server did not come up, so nothing may be written about what a server does"
else
    assert_contains "$WORK/s2.txt" "IMAP-CONTROL-ON-SERVER" "S2 positive control: the healthy message reached the server"
    assert_contains "$WORK/s2.txt" "IMAP-ISOLATED-EMPTY-ON-SERVER" "S2 the empty message alone reaches the server (isolated push, no identification by subject)"
    assert_contains "$WORK/s2.txt" "IMAP-SECOND-DEVICE-GOT-EMPTY" "S2 a second device pulling the account receives it"
fi

echo ""
echo "=============================================================="
echo "R. Does anything outside himalaya flag it?"
echo "=============================================================="
docker run --rm -v "$WORK/c4":/store:ro -v "$here":/legs:ro "$TOOLS_IMAGE" \
    sh /legs/legs/readers.sh > "$WORK/r.txt" 2>&1
r_rc=$?
cat "$WORK/r.txt"
assert_rc "$r_rc" 0 "R ran"
# The damaged entry's name is printed by the leg's own preamble, so finding
# it proves only that the leg described its inputs. These four markers are
# emitted from measured outcomes and nowhere else.
assert_contains "$WORK/r.txt" "NOTMUCH-INDEXED-CONTROL" "R positive control: notmuch indexed the healthy message"
assert_contains "$WORK/r.txt" "NOTMUCH-FLAGGED-DAMAGED" "R notmuch named the damaged entry in its own output"
assert_contains "$WORK/r.txt" "NOTMUCH-FLAGGED-PLANTED" "R control: notmuch also names a malformed non-empty file, so the refusal is not emptiness-specific"
assert_contains "$WORK/r.txt" "PYTHON-ENUMERATED-DAMAGED" "R the other reader still enumerates the damaged entry as a message"

echo ""
echo "=============================================================="
echo "T. Can the tool itself finish the cleanup?"
echo "=============================================================="
docker run --rm -v "$WORK/c4":/tmp/cohort4 -v "$here":/legs:ro "$C4_IMAGE" \
    sh /legs/legs/trash.sh > "$WORK/t.txt" 2>&1
t_rc=$?
cat "$WORK/t.txt"
assert_rc "$t_rc" 0 "T ran"
# "The script ran" is not "the deletions happened". Each of these is
# emitted only when the command's own rc and the folder counts say so.
assert_contains "$WORK/t.txt" "TRASH-MOVED-ZERO-BYTE" "T the first delete relocated the 0-byte entry into Trash"
assert_contains "$WORK/t.txt" "TRASH-SECOND-DELETE-REMOVED" "T the second delete emptied the Trash of it"
assert_contains "$WORK/t.txt" "TRASH-SCAN-CONTROL-FIRES" "T the surface scan's own expression matches when a matching name exists"

echo ""
echo "=============================================================="
echo "H. Is clap's help a faithful index of this binary?"
echo "=============================================================="
echo "   Narrowed on purpose. Modelling clap's derive expansion from a"
echo "   regex would agree with the help output while both missed a"
echo "   cfg-gated construction, and an extractor that finds nothing"
echo "   agrees with everything. What is checkable without rebuilding is"
echo "   whether the pinned source defines any command the help is told"
echo "   to omit, or an escape hatch that accepts unknown ones."
SRC=${HIMALAYA_SRC:-$here/../artifacts/himalaya-src}
PIN=$(awk '/himalaya-src.digest/ {print $3}' "$here/../freeze-build.txt" 2>/dev/null | head -1)
if require_input "$SRC" "spike/cohort4/fetch-artifacts.sh (artifacts/ is gitignored; a fresh checkout has no source tree)"; then
    # Recomputed over the tree with fetch-artifacts.sh's own expression, not
    # read from the sidecar file: a modified tree keeps its old sidecar, and
    # comparing a file to itself proves nothing about the bytes being read.
    have=$( (cd "$SRC" && find . -type f -not -path './.git/*' -print0 \
             | LC_ALL=C sort -z | xargs -0 -n 64 shasum -a 256 | shasum -a 256 | cut -d' ' -f1) 2>/dev/null )
    assert_digest "${have:-<none>}" "${PIN:-<none>}" "H the source tree hashes to the pinned digest (recomputed, not read from the sidecar)"
    n_hide=$(grep -rEc 'hide[[:space:]]*=|hide_long_help|external_subcommand' "$SRC/src" 2>/dev/null | awk -F: '{s+=$2} END {print s+0}')
    n_scan=$(find "$SRC/src" -name '*.rs' | wc -l | tr -d ' ')
    echo "   scanned $n_scan .rs files under the pinned src/"
    echo "   clap hiding or escape-hatch attributes found: $n_hide"
    if [ "$n_scan" -lt 50 ]; then
        bad "H the scan denominator is implausibly small ($n_scan files) — it is not seeing the tree"
    else
        ok "H scan denominator: $n_scan files"
    fi
    if [ "$n_hide" -eq 0 ]; then
        ok "H no hidden or external subcommand is declared in the pinned source"
    else
        bad "H $n_hide hiding or escape-hatch site(s) found — R1's enumeration is incomplete and the record must say so"
    fi
    echo "   positive control, same expression against a planted attribute:"
    tmpf=$WORK/planted.rs
    printf '#[command(hide = true)]\nstruct X;\n' > "$tmpf"
    pc=$(grep -Ec 'hide[[:space:]]*=|hide_long_help|external_subcommand' "$tmpf")
    [ "$pc" -ge 1 ] && ok "H the expression matches when a hidden command is present ($pc)" \
                    || bad "H the expression does not match a planted hidden command — it measures nothing"
fi

echo ""
echo "== failures: $fails"
[ "$fails" -eq 0 ] || exit 1
