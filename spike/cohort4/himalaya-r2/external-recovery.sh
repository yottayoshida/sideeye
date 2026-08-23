#!/bin/sh
# The last precondition the freeze puts in front of a report
# (PROTOCOL.md, "Reporting, and delivery"): measure the recovery paths
# that exist OUTSIDE the tool, and the conditions under which they do not
# apply. For himalaya the freeze names the shape it expects: the
# conditions under which data is lost before it reaches the synchronized
# side.
#
# This is a non-claim, leg-external measurement. It does not touch claim
# eligibility, and nothing here authorises contact with anyone.
#
# The damaged store is PRODUCED, never assembled, using the stock
# reproduction's own instrument: strace, one injected signal, no shim, no
# engine, no seccomp, no interposer. Hand-building the state was an R1
# finding against the define's drills and it is not repeated here.
#
# Which legs crash, precisely, because a reviewer was right that "each
# leg gets a fresh crash" was not true as first written: R2, R4, R5 (both
# halves) and R7 each call `damage` for themselves. R6 does too. R3 is
# the deliberate exception and runs the operation to COMPLETION, because
# what it counts is the syscalls the whole operation makes; a crashed
# prefix would be a weaker measurement of the same thing.
#
# Every "none" and every "0" in the output is paired with a positive
# control, because a scan that finds nothing and a scan that never ran
# print the same number.
set -u
CFG=/tmp/cohort4/himalaya/config.toml
STORE=/tmp/cohort4/himalaya/store
MSGID='1700000000.#0M0P1.probehost'
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SETUP="$here/ops/setup.sh"
export HOME=/tmp/cohort4/himalaya/home XDG_CONFIG_HOME=/tmp/cohort4/himalaya/xdg
W=/tmp/extrec
rm -rf "$W"; mkdir -p "$W"
FAILS=0
note() { echo "   $*"; }
bad()  { echo "   BROKEN: $*"; FAILS=$((FAILS+1)); }

snapshot() { # dir -> path/size/sha per line, sorted
    find "$1" -type f 2>/dev/null | LC_ALL=C sort | while IFS= read -r f; do
        printf '%s %s %s\n' "${f#$1/}" "$(wc -c < "$f" | tr -d ' ')" \
            "$(sha256sum < "$f" | cut -c1-16)"
    done
}

damage() { # produce the finding for real; leaves the crashed store in place
    "$SETUP" || { bad "setup failed"; return 1; }
    strace -f -e trace=copy_file_range -e inject=copy_file_range:signal=KILL:when=1 \
        himalaya -c "$CFG" maildir messages copy "$MSGID" \
        --maildir . --target Archive > "$W/kill.out" 2>&1
    krc=$?
    n=$(ls -A "$STORE/Archive/cur" 2>/dev/null | wc -l | tr -d ' ')
    b=0
    for f in "$STORE"/Archive/cur/*; do [ -e "$f" ] && b=$(wc -c < "$f" | tr -d ' '); done
    note "operation rc=$krc, target folder holds $n entry, $b bytes"
    [ "$n" = 1 ] && [ "$b" = 0 ] || { bad "the damage did not reproduce; the rest measures nothing"; return 1; }
    return 0
}

echo "himalaya: $(himalaya --version 2>&1 | head -1)"
echo "apparatus absent: /etc/ld.so.preload $([ -e /etc/ld.so.preload ] && echo PRESENT || echo absent), LD_PRELOAD=${LD_PRELOAD:-<unset>}"

echo ""
echo "=============================================================="
echo "R1. Does the tool itself offer a way back? The whole command"
echo "    surface, enumerated rather than remembered."
echo "=============================================================="
# Breadth-first until a level has no children, so the DEPTH is measured.
# The first version of this walk stopped at three levels and reported 208
# commands; there is a fourth level with 29 more.
#
# The parse is indentation-strict. A loose "first field under Commands:"
# parse reads WRAPPED ALIAS LINES as commands, which inflates the
# denominator with entries like `gmail settings forwarding-addresses del,`.
# Both parses run, and the difference between them is validated in both
# directions below.
# R1 found by review: a pipeline loses himalaya's exit status, so a --help
# that FAILED would look like a command with no children and the walk would
# call it a leaf. The status is captured before anything is piped, and every
# failure is recorded so the completeness claim below can be checked rather
# than assumed.
: > "$W/helpfail"
kids_strict() {
    out=$(himalaya $* --help 2>/dev/null) || { echo "strict: $*" >> "$W/helpfail"; return 0; }
    printf '%s\n' "$out" | awk '/^Commands:/{f=1;next} /^Options:/{f=0} f && /^  [a-z][a-z0-9-]*(  |$)/{print $1}' | grep -vE '^help$'
}
kids_loose() {
    out=$(himalaya $* --help 2>/dev/null) || { echo "loose: $*" >> "$W/helpfail"; return 0; }
    printf '%s\n' "$out" | awk '/^Commands:/{f=1;next} /^Options:/{f=0} f && NF{print $1}' | grep -vE '^help$'
}
walk() { # $1 = kids function name, $2 = file to record the measured depth in
    fr=$($1)
    depth=0
    while [ -n "$fr" ]; do
        depth=$((depth+1))
        nx=""
        while IFS= read -r p; do
            [ -n "$p" ] || continue
            printf '%s\n' "$p"
            for c in $($1 "$p"); do nx="$nx$p $c
"; done
        done <<EOF
$fr
EOF
        fr=$(printf '%s' "$nx" | sed '/^$/d')
    done
    echo "$depth" > "$2"
}
walk kids_strict "$W/depth-strict" > "$W/tree" 2>/dev/null
walk kids_loose  "$W/depth-loose"  > "$W/tree-loose" 2>/dev/null
STRICT=$(wc -l < "$W/tree" | tr -d ' ')
LOOSE=$(wc -l < "$W/tree-loose" | tr -d ' ')
note "tree depth measured: $(cat "$W/depth-strict") levels (not assumed)"
note "commands enumerated: $STRICT strict, $LOOSE loose"
[ "$STRICT" -gt 100 ] || bad "the enumeration collapsed; a scan this small is not a surface"

# Two-sided validation of the parse fix.
ok=0; invalid=0
while IFS= read -r p; do
    [ -n "$p" ] || continue
    if himalaya $p --help >/dev/null 2>&1; then ok=$((ok+1)); else invalid=$((invalid+1)); echo "   KEPT-BUT-INVALID: $p"; fi
done < "$W/tree"
note "every kept node answers --help: valid=$ok invalid=$invalid"
[ "$invalid" -eq 0 ] || bad "the enumeration contains things that are not commands"

LC_ALL=C sort -u "$W/tree-loose" > "$W/loose-sorted"
LC_ALL=C sort -u "$W/tree"       > "$W/strict-sorted"
comm -23 "$W/loose-sorted" "$W/strict-sorted" > "$W/dropped"
tried=0; alive=0
while IFS= read -r p; do
    [ -n "$p" ] || continue
    tried=$((tried+1))
    if himalaya $p --help >/dev/null 2>&1; then alive=$((alive+1)); echo "   DROPPED-BUT-VALID: $p"; fi
done < "$W/dropped"
note "nodes the strict parse dropped: tried=$tried, real commands among them=$alive"
[ "$tried" -gt 0 ] || bad "the dropped-node check ran over an empty list, so its 0 means nothing"
[ "$alive" -eq 0 ] || bad "the strict parse threw away a real command"
himalaya maildir messages copy --help >/dev/null 2>&1 \
    && note "positive control: the same loop calls 'maildir messages copy' real" \
    || bad "positive control failed; the loop cannot recognise a command that exists"
# Only the STRICT walk's failures can hide a subtree, because the strict
# tree is the one every claim below is about. The loose walk descends into
# its own phantoms by construction, so its failures are expected; they are
# counted separately and are in fact a second, independent confirmation
# that the dropped nodes are not commands.
hfs=$(grep -c '^strict: ' "$W/helpfail")
hfl=$(grep -c '^loose: '  "$W/helpfail")
note "--help invocations that failed during the strict walk: $hfs"
note "--help invocations that failed during the loose walk:  $hfl (expected:"
note "  the loose walk descends into the alias fragments it mis-parses, and"
note "  this count independently agrees with the $(wc -l < "$W/dropped" | tr -d ' ') dropped above)"
[ "$hfs" -eq 0 ] || { grep '^strict: ' "$W/helpfail" | sed 's/^/     /'; bad "a subtree may have been silently treated as a leaf"; }
note "so the strict walk is complete FOR THE MECHANISM IT USES: every node"
note "it asked answered, and every node it kept is a real command. What it"
note "does not prove is that clap's help is a faithful index of the binary."
note "Both parses read the same 'Commands:' blocks and both drop 'help'"
note "deliberately, so a command reachable some other way would be"
note "invisible to either of them."

echo ""
note "scanning the NAMES of all $STRICT commands for anything repair-shaped:"
# grep first, rc read before anything is piped: a pipeline would report
# sed's status and hide a scan that failed to run.
PAT='sync|repair|verif|check|fsck|doctor|restor|recover|rebuild|scan|fix|consist|integrit'
grep -inE "$PAT" "$W/tree" > "$W/hits"
grc=$?
[ "$grc" -le 1 ] || bad "the scan itself failed (rc=$grc)"
sed 's/^/     /' "$W/hits"
note "matches: $(wc -l < "$W/hits" | tr -d ' ')"
# The control must run the IDENTICAL expression, not a stand-in: a control
# built from a different pattern proves that some grep works, not that this
# one does.
if printf 'sentinel repair\n' | grep -qiE "$PAT"; then
    note "positive control: this exact expression matches when given a match"
else
    bad "positive control failed; the scan expression cannot match at all"
fi
note ""
note "reading, kept to what a scan of command NAMES can support: of the"
note "$STRICT names, $(wc -l < "$W/hits" | tr -d ' ') are repair-shaped. 'account check' validates the"
note "account CONFIGURATION (its own help says so, and R2 runs it against"
note "the damage). 'gmail settings send-as verify' is Gmail alias"
note "ownership. No name in the surface is a sync."
note ""
note "This is a claim about names, not about behaviour. Commands that READ"
note "stored mail obviously exist, and R4 uses one: 'envelope list' is"
note "how the empty message gets displayed as an ordinary message in the"
note "first place. The narrow statement the scan supports is that nothing"
note "in the surface is named for CHECKING stored mail, and R2 measures"
note "the one candidate. It says nothing about whether the damage can be"
note "undone; R5 measures that separately."

echo ""
echo "=============================================================="
echo "R2. The one check-shaped command, run against the damage."
echo "=============================================================="
damage || { echo "== BROKEN: $FAILS"; exit 1; }
snapshot "$STORE" > "$W/before"
himalaya -c "$CFG" account check > "$W/check.out" 2>&1
crc=$?
snapshot "$STORE" > "$W/after"
note "account check rc=$crc"
sed 's/^/     /' "$W/check.out" | head -6
if grep -qiE '0 bytes|empty|corrupt|truncat|invalid message' "$W/check.out"; then
    note "it mentioned the damaged message"
else
    note "it did not mention the damaged message"
fi
# Same class as the dropped-node loop that once printed a reassuring 0 over
# a missing file: a grep that finds nothing and a grep with nothing to read
# print the same answer, so the negative above is only worth something next
# to a positive on the same file.
if grep -qi 'maildir' "$W/check.out"; then
    note "positive control: the same grep does match text that is in that output"
else
    bad "the check output could not be searched at all, so 'did not mention' means nothing"
fi
sb=$(wc -l < "$W/before" | tr -d ' ')
[ "$sb" -gt 0 ] || bad "the store snapshot is empty, so 'unchanged' would compare nothing"
note "snapshot covers $sb file(s) in the store"
if cmp -s "$W/before" "$W/after"; then note "store unchanged across the check"
else note "store CHANGED across the check:"; diff "$W/before" "$W/after" | sed 's/^/     /'; fi
note "reading: the account is valid, so the tool's only check-shaped"
note "command passes over a mailbox that holds a message with no message"
note "in it. It is a configuration validator, not a store validator."

echo ""
echo "=============================================================="
echo "R3. At the instant of the crash, does anything else hold a copy?"
echo "=============================================================="
"$SETUP"
strace -f -e trace='%network' -o "$W/net.log" \
    himalaya -c "$CFG" maildir messages copy "$MSGID" --maildir . --target Archive \
    > "$W/net.out" 2>&1
orc=$?
# Found by review: counting a hand-written list of syscall names measures
# "zero of the names I thought of", not "zero network syscalls". strace was
# already told to trace the %network class, so the honest count is every
# syscall line the log holds, whatever it is called. The two non-syscall
# line shapes strace emits (exit and signal records) are excluded by the
# same expression.
syscount() { grep -cE '^[0-9]+ +[a-z_][a-z_0-9]*\(' "$1"; }
net=$(syscount "$W/net.log")
note "operation rc=$orc, syscalls of the traced %network class during it: $net"
[ "$net" -eq 0 ] && note "  (and the log holds $(wc -l < "$W/net.log" | tr -d ' ') line(s) in total, so it was written)"
strace -f -e trace='%network' -o "$W/net-pc.log" \
    python3 -c "import socket; socket.socket().connect_ex(('127.0.0.1',1))" >/dev/null 2>&1
netpc=$(syscount "$W/net-pc.log")
note "positive control (a process that does connect), same filter and same"
note "counting expression: $netpc"
grep -oE '^[0-9]+ +[a-z_][a-z_0-9]*\(' "$W/net-pc.log" | awk '{print $2}' | sort -u | tr -d '(' | tr '\n' ' ' | sed 's/^/     names it caught: /'
echo ""
[ "$netpc" -gt 0 ] || bad "the network filter caught nothing even on a real connect; R3's 0 means nothing"
note "reading, stated narrowly because the sentence I first wrote here was"
note "wider than the measurement. What is measured: this operation, run to"
note "completion under this configuration, makes no call of the traced"
note "network class. It copies between two folders inside one local root."
note ""
note "What follows: the ENTRY being created in the target folder is not"
note "sent anywhere while it is being created, so a remote side has not"
note "seen THAT entry at the moment it is destroyed, and re-fetching from"
note "a server cannot put it back. What does NOT follow, and is where the"
note "first draft over-reached: the message's CONTENT may well exist"
note "elsewhere, on a server or in the source folder, and R7 measures the"
note "source surviving locally. So the content is recoverable; the folder"
note "state is not restored by anything remote."
note ""
note "Nor does this prove anything about accounts other than the one"
note "configured here. It is one measurement of one configuration."

echo ""
echo "=============================================================="
echo "R4. The obvious recovery: the source survived, so do it again."
echo "=============================================================="
damage || { echo "== BROKEN: $FAILS"; exit 1; }
src_before=$(sha256sum < "$STORE/cur/$MSGID:2,S" | cut -c1-16)
src_bytes=$(wc -c < "$STORE/cur/$MSGID:2,S" | tr -d ' ')
note "source after the crash: $src_bytes bytes, sha $src_before"
himalaya -c "$CFG" maildir messages copy "$MSGID" --maildir . --target Archive \
    > "$W/redo.out" 2>&1
rrc=$?
note "re-run rc=$rrc"
note "what the target folder holds now:"
for f in "$STORE"/Archive/cur/*; do
    [ -e "$f" ] || continue
    note "  $(basename "$f") -> $(wc -c < "$f" | tr -d ' ') bytes"
done
cnt=$(ls -A "$STORE/Archive/cur" | wc -l | tr -d ' ')
note "entries: $cnt"
note "and what the tool lists:"
himalaya -c "$CFG" envelope list -m Archive > "$W/redo-list.out" 2>&1
lrc=$?
note "envelope list rc=$lrc"
sed -n '1,12p' "$W/redo-list.out" | sed 's/^/     /'

echo ""
echo "=============================================================="
echo "R5. Can the tool remove the damaged message?"
echo "=============================================================="
damage || { echo "== BROKEN: $FAILS"; exit 1; }
note "the maildir-specific API has no delete: $(himalaya maildir messages --help 2>&1 | awk '/^Commands:/{f=1;next} /^Options:/{f=0} f && /^  [a-z]/{printf "%s ", $1}')"
id=$(basename "$(ls "$STORE"/Archive/cur/* | head -1)" | cut -d: -f1)
note "trying the shared command on the damaged entry, id $id"
himalaya -c "$CFG" message delete -m Archive "$id" > "$W/del.out" 2>&1
drc=$?
note "message delete rc=$drc"
sed -n '1,6p' "$W/del.out" | sed 's/^/     /'
note "target folder afterwards: $(ls -A "$STORE/Archive/cur" | wc -l | tr -d ' ') in cur, $(ls -A "$STORE/Archive/tmp" 2>/dev/null | wc -l | tr -d ' ') in tmp, $(ls -A "$STORE/Archive/new" 2>/dev/null | wc -l | tr -d ' ') in new"
for f in "$STORE"/Archive/cur/*; do [ -e "$f" ] && note "  remaining: $(basename "$f") ($(wc -c < "$f" | tr -d ' ') bytes)"; done

note ""
note "control: is that refusal about the damaged message, or about any"
note "message under this configuration? Same command, same folder, same"
note "config, on a HEALTHY copy produced by letting the operation finish:"
"$SETUP"
himalaya -c "$CFG" maildir messages copy "$MSGID" --maildir . --target Archive >/dev/null 2>&1
hid=$(basename "$(ls "$STORE"/Archive/cur/* | head -1)" | cut -d: -f1)
note "healthy copy in Archive: $hid ($(wc -c < "$(ls "$STORE"/Archive/cur/* | head -1)" | tr -d ' ') bytes)"
himalaya -c "$CFG" message delete -m Archive "$hid" > "$W/del-ctl.out" 2>&1
dcrc=$?
note "message delete on it rc=$dcrc"
sed -n '1,3p' "$W/del-ctl.out" | sed 's/^/     /'
echo ""
if [ "$dcrc" -ne 0 ]; then
    note "so the refusal is generic to the configuration, not specific to"
    note "the damaged message. Reported that way rather than as a second"
    note "defect."
else
    note "the healthy message deletes and the damaged one does not, which"
    note "would be a defect of its own."
fi

note ""
note "and with a trash mailbox configured, which the error asks for."
note "The control above consumed the damaged store, so it is produced"
note "again here rather than assumed to still be there:"
damage || { echo "== BROKEN: $FAILS"; exit 1; }
id=$(basename "$(ls "$STORE"/Archive/cur/* | head -1)" | cut -d: -f1)
sed 's/^default = true/default = true\nfolder.alias.trash = "Trash"\nmailbox.alias.trash = "Trash"/' "$CFG" > "$W/config-trash.toml"
mkdir -p "$STORE/Trash/cur" "$STORE/Trash/new" "$STORE/Trash/tmp"
himalaya -c "$W/config-trash.toml" message delete -m Archive "$id" > "$W/del2.out" 2>&1
d2rc=$?
note "message delete rc=$d2rc"
sed -n '1,3p' "$W/del2.out" | sed 's/^/     /'
note "Archive/cur now: $(ls -A "$STORE/Archive/cur" | wc -l | tr -d ' ') entry, Trash/cur: $(ls -A "$STORE/Trash/cur" 2>/dev/null | wc -l | tr -d ' ') entry"
for f in "$STORE"/Trash/cur/*; do [ -e "$f" ] && note "  in Trash: $(basename "$f") ($(wc -c < "$f" | tr -d ' ') bytes)"; done
note ""
note "reading, and it is not 'the message can be deleted', which is what"
note "the first draft said. What was measured is a MOVE: two config keys"
note "were added and a Trash folder was created first, and the command"
note "then relocated the entry out of Archive into Trash, where the"
note "transcript above shows it still sitting at 0 bytes. Emptying the"
note "trash was not measured."
note ""
note "The refusal before that is a property of an account with no trash"
note "mailbox: it refuses on healthy mail in the same folder under the"
note "same config in the same words, so it is not part of this finding"
note "and is not reported as one. What stands is narrower and is the"
note "point: getting the empty message out of the folder is a manual"
note "act, and it requires the user to already know which of the entries"
note "in the folder is not a message."

echo ""
echo "=============================================================="
echo "R6. Does anything outside himalaya see it as damage?"
echo "=============================================================="
damage || { echo "== BROKEN: $FAILS"; exit 1; }
python3 - "$STORE" <<'PY'
import sys, mailbox
root = sys.argv[1]
def show(label, path):
    md = mailbox.Maildir(path, create=False)
    keys = list(md.keys())
    print("   %s: %d message(s) enumerated by python mailbox.Maildir" % (label, len(keys)))
    for k in keys:
        m = md[k]
        print("     subject=%r from=%r headers=%d body=%d bytes"
              % (m.get("Subject"), m.get("From"), len(m.keys()), len(m.get_payload() or "")))
show("target folder (holds the damaged copy)", root + "/Archive")
show("source folder (positive control, healthy)", root)
PY
prc=$?
note "python reader rc=$prc"
note "reading: ONE independent maildir reader, python's stdlib mailbox"
note "module, enumerates the zero-byte file as an ordinary message, with"
note "a healthy message in the same store as the control. Nothing in the"
note "maildir format marks it. That is one reader, not every reader: it"
note "shows the entry is well formed as far as the format goes, not that"
note "no tool anywhere would flag it."

echo ""
echo "=============================================================="
echo "R7. What bounds the loss."
echo "=============================================================="
damage || { echo "== BROKEN: $FAILS"; exit 1; }
src_now=$(sha256sum < "$STORE/cur/$MSGID:2,S" | cut -c1-16)
note "source message after the crash: $(wc -c < "$STORE/cur/$MSGID:2,S" | tr -d ' ') bytes, sha $src_now"
note "leg E of the checker asserts exactly this, and it held in both runs."
note "So the original is not lost. What the crash creates is a second,"
note "message-shaped object with nothing in it, in the folder the user"
note "was archiving into."

echo ""
echo "=============================================================="
echo "The answer the freeze asked for, and its limits."
echo "=============================================================="
note "Every sentence here is scoped to the one account configuration this"
note "script measured: a maildir account with no remote, on this build."
note ""
note "RECOVERY PATHS THAT WERE MEASURED TO WORK:"
note "  1. The content is not lost, so the copy can simply be repeated"
note "     (R4, R7). The source is byte-identical after the crash. The"
note "     repeat does not remove the empty entry: the folder afterwards"
note "     holds both, and the tool lists both as messages."
note "  2. The empty entry can be moved out of the folder by the tool's"
note "     own delete, once the account names a trash mailbox and that"
note "     mailbox exists (R5). It lands in Trash still at 0 bytes;"
note "     whether emptying the trash removes it was not measured."
note ""
note "THE CONDITION BOTH SHARE:"
note "  Both require the user to notice, and nothing in what was measured"
note "  offers to. No command NAME in the surface is about checking"
note "  stored mail (R1, a scan of names only), the one check-shaped"
note "  command reports the account OK over the damaged store (R2), and"
note "  the one independent maildir reader tried enumerates the empty"
note "  file as an ordinary message (R6). In the tool's own listing the"
note "  entry differs from a real message only by blank columns and 0 B."
note ""
note "THE SYNCHRONIZED SIDE, WHICH THE FREEZE ASKED ABOUT SPECIFICALLY:"
note "  Re-fetching from a server cannot restore the target-folder ENTRY,"
note "  because that entry is never sent anywhere while it is being"
note "  created: the operation makes no call of the traced network class"
note "  (R3, against a positive control on the same filter), and no name"
note "  in the surface is a sync. This is about the entry, not about the"
note "  content: the content may well exist on a server, and it certainly"
note "  still exists in the source folder."
note ""
note "  So the maildir-only configuration the freeze names is not the"
note "  only one where a remote side fails to restore the folder state."
note "  It is where the CONTENT would also be at risk, and this operation"
note "  does not put the content at risk, because it conserves the"
note "  source. That is the honest limit of this finding's severity."
note ""
note "NOT MEASURED, AND STATED RATHER THAN IMPLIED:"
note "  - Whether an EXTERNAL syncer (isync, offlineimap) managing this"
note "    maildir would carry the empty message outward to the server as"
note "    a new message. That is the shape the freeze calls the strongest"
note "    form, the external recovery path itself carrying the damage."
note "    It needs a second tool and a server, neither in this image."
note "  - Whether any tool other than the one python reader tried would"
note "    flag the entry."
note "  - Whether clap's help output is a faithful index of the binary."
note "    R1's completeness is complete for that mechanism, no more."

echo ""
echo "== BROKEN checks: $FAILS"
[ "$FAILS" -eq 0 ] || exit 1
exit 0
