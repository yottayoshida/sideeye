#!/bin/sh
# Cohort-4 himalaya define (P1) checker. Property (proposals.md P1): crash
# anywhere inside `maildir messages copy`, and the store holds either the
# old message set, or the old set plus the COMPLETE copy of the message in
# the target folder, with himalaya's own reader agreeing about which.
#
# Legs, in this order: guard (the store has a shape this operation can
# produce), leg D (the copy is all-or-nothing: absent, or present with the
# source's exact bytes and its flag suffix), leg E (the source message is
# conserved), leg C (the outside-root configuration is unmutated), and last
# leg R (himalaya's own reader agrees with what leg D found).
#
# ORDERING, measured rather than inherited. papis's checker had to put its
# reader last because `papis list` WROTE — it minted and persisted a random
# papis_id into a document that had lost one, so a byte assertion after it
# would have judged the checker's own side effect. himalaya's reader was
# measured for the same hazard before this file was written, on healthy,
# zero-length, cut-mid-header and absent states, snapshotting every path,
# size and checksum in the store around each invocation: it mutated nothing
# in any of them (pre-define-trials.txt, trials A-E). The reader still runs
# last here, but as a convention rather than a constraint, and the record
# says which.
#
# NO DOCUMENTED RECOVERY IS APPLIED, and that is a measurement too. The
# cohort rule asks for the target's documented repair step before the
# assert. himalaya's command surface was enumerated (pre-define-trials.txt,
# trial F): mailbox, envelope, flag, message, attachment, the four
# backend-specific trees, configure, account, completion, manual,
# json-schema. There is no doctor, repair, check, verify or fsck, and the
# maildir subtree offers create, rename, delete, list, messages and flags.
# Nothing in it claims to repair a store, so there is nothing to run.
#
# NAME-AGNOSTIC ON PURPOSE. io-maildir mints the copy's filename from the
# clock, a process-local counter, the pid and the hostname
# (entry.rs:48-56), so it differs between worlds. The probe pinned those
# with libfaketime and a getpid interposer, which this define cannot reuse:
# the engine owns LD_PRELOAD for its shim, and /etc/ld.so.preload was
# measured to break strace, which the engine uses as its oracle. The engine
# needs no cross-run byte identity of its own — it refuses on threads and
# on a baseline that violates the invariant — so the checker asserts on the
# copy's CONTENT and flag suffix and never on its name. The one thing the
# name must satisfy is the maildir flag suffix, which carries the message's
# state and is part of what a copy has to preserve.
#
# The store himalaya reads is $SIDEEYE_STATE_DIR, so the account config is
# written per invocation with that path; its content is otherwise the
# frozen one. HOME and XDG live in the per-invocation temp dir so the
# checker cannot pollute the ambient it judges.
set -u
S=${SIDEEYE_STATE_DIR:?checker needs SIDEEYE_STATE_DIR}
P=/tmp/cohort4/himalaya
MSGID='1700000000.#0M0P1.probehost'
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/home" "$T/xdg"
cat > "$T/config.toml" <<EOF
[accounts.probe]
default = true
maildir.root = "$S"
EOF
export HOME="$T/home" XDG_CONFIG_HOME="$T/xdg"

fail() { echo "checker(himalaya-copy): $*"; exit 1; }

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

# ---- guard: the store has a shape this operation can produce --------------
# Enumerated rather than spot-checked: the accepted probe's guard is what
# catches a store that lost a directory, gained a stray entry, or turned a
# message into a symlink, any of which would walk past the legs below.
[ -d "$S" ] || fail "the store directory is missing"
for d in cur new tmp Archive Archive/cur Archive/new Archive/tmp; do
    [ -d "$S/$d" ] || fail "the store has lost its $d directory"
done
top=$(ls -A "$S" | sort | tr '\n' ' ')
[ "$top" = 'Archive cur new tmp ' ] \
    || fail "the store root holds entries this operation cannot produce (got: $top)"

src_entries=$(ls -A "$S/cur" | sort | tr '\n' ' ')
[ "$src_entries" = "$MSGID:2,S " ] \
    || fail "the source folder holds entries this operation cannot produce (got: $src_entries)"

empties=$(find "$S/new" "$S/tmp" "$S/Archive/new" "$S/Archive/tmp" -mindepth 1 | wc -l | tr -d ' ')
[ "$empties" = 0 ] \
    || fail "new/ or tmp/ is not empty: this operation stages nothing, so $empties entry/entries there is damage or a shape the define did not declare"

copies=$(ls -A "$S/Archive/cur" | wc -l | tr -d ' ')
case "$copies" in
    0) copy_present=no ;;
    1) copy_present=yes; copy_name=$(ls -A "$S/Archive/cur") ;;
    *) fail "the target folder holds $copies entries; one copy operation cannot produce more than one" ;;
esac

# ---- leg D: the copy is all-or-nothing ------------------------------------
if [ "$copy_present" = yes ]; then
    { [ -f "$S/Archive/cur/$copy_name" ] && [ ! -L "$S/Archive/cur/$copy_name" ]; } \
        || fail "leg D: the target folder holds an entry that is not a plain file ($copy_name)"
    case "$copy_name" in
        *:2,S) ;;
        *) fail "leg D: the copy has lost the source's maildir flag suffix (name: $copy_name)" ;;
    esac
    msg_bytes | cmp -s - "$S/Archive/cur/$copy_name" \
        || fail "leg D: the copy is present but its bytes are not the source's ($(wc -c < "$S/Archive/cur/$copy_name" | tr -d ' ') bytes on disk against $(msg_bytes | wc -c | tr -d ' ') in the source)"
fi

# ---- leg E: the source message is conserved -------------------------------
msg_bytes | cmp -s - "$S/cur/$MSGID:2,S" \
    || fail "leg E: the source message's bytes changed"

# ---- leg C: conservation of the outside-root configuration ----------------
printf '[accounts.probe]\ndefault = true\nmaildir.root = "%s"\n' "$P/store" | cmp -s - "$P/config.toml" \
    || fail "leg C: the outside-root account configuration changed"

# ---- leg R: himalaya's own reader agrees with what is on disk -------------
# The reader is the tool's own command, as rule 9 requires. Two assertions:
# the target folder lists exactly the number of messages leg D found, and,
# when one is there, the tool can read it back.
#
# What this leg does NOT do is stand in for leg D. The trials measured a
# zero-length message being listed as an ordinary envelope, 0 B and blank
# columns, rc 0 (pre-define-trials.txt, trial G): the reader alone cannot
# tell a torn copy from a whole one, which is exactly why the byte
# assertion runs first and this leg runs beside it rather than instead.
timeout 120 himalaya -c "$T/config.toml" envelope list -m Archive > "$T/list" 2> "$T/list.err"
rc=$?
if [ "$rc" -ne 0 ]; then
    tnote=""; case "$rc" in 124|137) tnote="; this step timed out" ;; esac
    fail "leg R: envelope list failed (rc=$rc$tnote): $(head -c 200 "$T/list.err")"
fi
listed=$(grep -c '│ [0-9][0-9]*\.' "$T/list")
if [ "$copy_present" = yes ]; then
    [ "$listed" = 1 ] || fail "leg R: the target folder holds one message but the reader lists $listed"
    timeout 120 himalaya -c "$T/config.toml" message read -m Archive "${copy_name%%:*}" > "$T/read" 2> "$T/read.err"
    rrc=$?
    [ "$rrc" -eq 0 ] \
        || fail "leg R: the copy is on disk but the reader cannot read it back (rc=$rrc): $(head -c 200 "$T/read.err")"
    grep -q 'This is the existing message' "$T/read" \
        || fail "leg R: the reader returned the copy without the source's body text"
else
    [ "$listed" = 0 ] || fail "leg R: the target folder is empty but the reader lists $listed message(s)"
fi

exit 0
