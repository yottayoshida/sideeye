#!/bin/sh
# Checker drills for the himalaya define: the operation run once and
# judged, every leg seen red once on its own, and the whole checker green
# on the states the operation can actually leave. The cohort rule is that
# an assertion nobody has watched fail is not yet an assertion.
#
# Each damage case builds a store, breaks exactly one thing, runs the
# committed check.sh against it through SIDEEYE_STATE_DIR, and requires
# the checker to fail WITH THE EXPECTED LEG NAMED. A case that goes red
# through some other leg is a failure of the drill, not a pass: it would
# mean the leg under test is dead and another one is carrying it.
#
# HOW THE SCRIPTS ARE SPAWNED. setup.sh and check.sh run through their own
# exec bit, never as `sh file`. That is CLAUDE.md's rule, bought when a 644
# declaration script proved green under `sh` and then died with Permission
# denied at the first sealed exploration. The first cut of this file broke
# it and copied setup.sh's config-writing inline as well, which left the
# define's own setup with no green run anywhere and would have kept these
# drills green against a stale copy of it. Both fixed here: the ambient
# comes from ops/setup.sh itself.
#
# Engine-free: no kill, no engine, no shim. The operation runs once,
# normally, so the checker can be judged against what it really leaves.
set -u
OPS=$(cd "$(dirname "$0")/ops" && pwd)
CHECK="$OPS/check.sh"
P=/tmp/cohort4/himalaya
W=/tmp/drills-himalaya
MSGID='1700000000.#0M0P1.probehost'
FAILS=0

msg_bytes() {
    cat <<'EOF'
Return-Path: <probe@example.invalid>
Date: Sat, 01 Mar 2026 09:00:00 +0000
From: Probe Author <probe@example.invalid>
To: Probe Target <target@example.invalid>
Subject: Existing message, fixed bytes
Message-ID: <existing0001@example.invalid>

This is the existing message. Its bytes are part of the freeze.
EOF
}

build() { # dir with-copy(yes/no)
    d=$1
    rm -rf "${d:?}"
    mkdir -p "$d/cur" "$d/new" "$d/tmp" "$d/Archive/cur" "$d/Archive/new" "$d/Archive/tmp"
    msg_bytes > "$d/cur/$MSGID:2,S"
    [ "$2" = yes ] && msg_bytes > "$d/Archive/cur/1767225600.#0M1P77.somehost:2,S"
    return 0
}

# run <name> <expect: green|leg-substring> <dir> [command-prefix...]
run() {
    name=$1; expect=$2; d=$3; shift 3
    out=$(SIDEEYE_STATE_DIR="$d" "$@" "$CHECK" 2>&1); rc=$?
    if [ "$expect" = green ]; then
        if [ "$rc" -eq 0 ]; then echo "drill ok   $name: checker green as required"
        else echo "drill FAIL $name: checker went red on a state it must accept: $out"; FAILS=$((FAILS+1)); fi
        return 0
    fi
    if [ "$rc" -eq 0 ]; then
        echo "drill FAIL $name: checker stayed GREEN on damage it must catch"
        FAILS=$((FAILS+1)); return 0
    fi
    case "$out" in
        *"$expect"*) echo "drill ok   $name: red through the expected leg: $out" ;;
        *) echo "drill FAIL $name: red, but through the WRONG leg (wanted '$expect'): $out"; FAILS=$((FAILS+1)) ;;
    esac
}

# ---- the operation itself, run once and judged ----------------------------
# The state the checker must accept above all others is the one the
# un-killed operation leaves: if the checker is red there, the engine
# answers baseline_violates_invariant and the target loses its slot. That
# state is produced here by the define's own setup and the toml's own argv,
# rather than assembled by hand as the first cut of this file did.
#
# No seccomp profile is applied to this run and it does not need one: the
# profile decides which kernel path fs::copy takes, not what the copy
# leaves on disk, and both probe transcripts show a correct copy either way
# (../probes/himalaya-bare.txt, where the unlifted copy succeeded through
# copy_file_range, and ../probes/himalaya.txt, where it fell back).
echo "== the operation itself: setup, the frozen argv, then the checker"
"$OPS/setup.sh" || { echo "drill FAIL live/setup: the define's setup failed"; exit 1; }
HOME="$P/home" XDG_CONFIG_HOME="$P/xdg" \
    himalaya -c "$P/config.toml" maildir messages copy "$MSGID" \
    --maildir . --target Archive > "$W.op.out" 2>&1
oprc=$?
echo "   operation rc=$oprc: $(head -1 "$W.op.out")"
copy=$(ls -A "$P/store/Archive/cur")
echo "   the copy it left: $copy ($(wc -c < "$P/store/Archive/cur/$copy" | tr -d ' ') bytes)"
[ "$oprc" -eq 0 ] || { echo "drill FAIL live/operation: the operation itself failed"; FAILS=$((FAILS+1)); }
run "live/operation-then-checker" green "$P/store"

echo ""
echo "== the other state the operation can leave (killed before it created anything)"
build "$W/green-absent" no;  run "green/copy-absent"  green "$W/green-absent"

echo ""
echo "== guard"
build "$W/g1" yes; rm -rf "$W/g1/Archive/tmp"
run "guard/missing-dir" "has lost its Archive/tmp directory" "$W/g1"
build "$W/g2" yes; : > "$W/g2/stray"
run "guard/stray-root-entry" "the store root holds entries" "$W/g2"
build "$W/g3" yes; : > "$W/g3/cur/another:2,S"
run "guard/extra-source-message" "the source folder holds entries" "$W/g3"
build "$W/g4" yes; : > "$W/g4/Archive/tmp/leftover"
run "guard/staged-leftover" "new/ or tmp/ is not empty" "$W/g4"
build "$W/g5" yes; msg_bytes > "$W/g5/Archive/cur/1767225600.#0M2P78.somehost:2,S"
run "guard/two-copies" "cannot produce more than one" "$W/g5"

# The listing-status guard is new in this round, so it is drilled against
# its own predicate rather than against the accident that suggested it.
# Without it an unreadable target folder counts as zero entries, leg D is
# skipped entirely, and whether the checker goes red at all depends on
# what the reader happens to do: a false pass waiting on someone else's
# behaviour.
#
# It has to run as a NON-ROOT user. The container runs as root, and root
# bypasses the permission bits, so the first version of this drill made
# the directory unreadable and watched the checker sail through it. The
# drill was measuring nothing. setpriv drops to nobody for this one case,
# and the positive control below shows the same user reading a healthy
# store green, so a red here is the guard and not the uid.
build "$W/g6" yes; chmod 0777 "$W/g6" "$W/g6/cur" "$W/g6/Archive"
run "guard/unreadable-control" green "$W/g6" setpriv --reuid=65534 --regid=65534 --clear-groups
chmod 000 "$W/g6/Archive/cur"
run "guard/unreadable-target-folder" "the target folder could not be listed" "$W/g6" setpriv --reuid=65534 --regid=65534 --clear-groups
chmod 755 "$W/g6/Archive/cur"

echo ""
echo "== leg D: the copy is all-or-nothing"
build "$W/d1" yes; : > "$W/d1/Archive/cur/1767225600.#0M1P77.somehost:2,S"
run "legD/zero-length-copy" "leg D: the copy is present but its bytes" "$W/d1"
build "$W/d2" yes; msg_bytes | head -c 120 > "$W/d2/Archive/cur/1767225600.#0M1P77.somehost:2,S"
run "legD/cut-mid-headers" "leg D: the copy is present but its bytes" "$W/d2"
build "$W/d3" yes; mv "$W/d3/Archive/cur/1767225600.#0M1P77.somehost:2,S" "$W/d3/Archive/cur/1767225600.#0M1P77.somehost"
run "legD/flags-lost" "leg D: the copy has lost the source's maildir flag suffix" "$W/d3"
build "$W/d4" yes; rm "$W/d4/Archive/cur/1767225600.#0M1P77.somehost:2,S"
ln -s /nowhere "$W/d4/Archive/cur/1767225600.#0M1P77.somehost:2,S"
run "legD/dangling-symlink" "leg D: the target folder holds an entry that is not a plain file" "$W/d4"

echo ""
echo "== leg E: the source is conserved"
build "$W/e1" yes; printf 'clobbered\n' > "$W/e1/cur/$MSGID:2,S"
run "legE/source-rewritten" "leg E: the source message's bytes changed" "$W/e1"

echo ""
echo "== leg C: the outside-root configuration is conserved"
build "$W/c1" yes
cp "$P/config.toml" "$W/config.saved"
printf 'tampered\n' >> "$P/config.toml"
run "legC/config-changed" "account configuration changed" "$W/c1"
rm -f "$P/config.toml"
run "legC/config-missing" "account configuration is gone" "$W/c1"
cp "$W/config.saved" "$P/config.toml"

echo ""
echo "== leg R: himalaya's own reader agrees"
# Leg R cannot be reached by damaging the store: every state that makes
# the reader disagree with the disk is caught by an earlier leg first (a
# second message trips the guard's entry count, a torn copy trips leg D's
# bytes). Its five fail sites are therefore exercised directly, with a
# reader put in front of the real one that answers wrongly on purpose:
# the same synthetic pinning this repository uses for a dyld phrase it
# cannot provoke. Every site the leg has, not only the two an accident
# happened to suggest.
build "$W/r0" yes
run "legR/preconditions-green" green "$W/r0"

mkdir -p "$W/fake"
fake_reader() { # case-statement body
    { echo '#!/bin/sh'; echo 'case "$*" in'; printf '%s\n' "$1"; echo 'esac'; } > "$W/fake/himalaya"
    chmod 755 "$W/fake/himalaya"
}
row='│ 1767225600.#0M1P77.somehost ┆ x │'

fake_reader '    *"envelope list"*) echo "backend exploded" >&2; exit 3 ;;
    *) exit 0 ;;'
build "$W/r1" yes
run "legR/list-fails" "leg R: envelope list failed (rc=3)" "$W/r1" env "PATH=$W/fake:$PATH"

fake_reader "    *\"envelope list\"*) printf '(empty listing)\n'; exit 0 ;;
    *) exit 0 ;;"
build "$W/r2" yes
run "legR/lists-nothing" "leg R: the target folder holds one message but the reader lists 0" "$W/r2" env "PATH=$W/fake:$PATH"

fake_reader "    *\"envelope list\"*) printf '$row\n'; exit 0 ;;
    *\"message read\"*) echo \"cannot read this message\" >&2; exit 1 ;;
    *) exit 0 ;;"
build "$W/r3" yes
run "legR/cannot-read" "leg R: the copy is on disk but the reader cannot read it back" "$W/r3" env "PATH=$W/fake:$PATH"

fake_reader "    *\"envelope list\"*) printf '$row\n'; exit 0 ;;
    *\"message read\"*) echo 'Subject: something else'; exit 0 ;;
    *) exit 0 ;;"
build "$W/r4" yes
run "legR/body-missing" "leg R: the reader returned the copy without the source's body text" "$W/r4" env "PATH=$W/fake:$PATH"

fake_reader "    *\"envelope list\"*) printf '$row\n'; exit 0 ;;
    *) exit 0 ;;"
build "$W/r5" no
run "legR/counts-a-ghost" "leg R: the target folder is empty but the reader lists 1" "$W/r5" env "PATH=$W/fake:$PATH"

echo "   (trial G in pre-define-trials.txt is the measurement that leg R"
echo "    cannot substitute for leg D: a zero-length copy lists as an"
echo "    ordinary envelope, 0 B and blank columns, rc 0.)"

echo ""
echo "== drills failed: $FAILS"
[ "$FAILS" -eq 0 ] || exit 1
exit 0
