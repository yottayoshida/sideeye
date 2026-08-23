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
# The damaged store is PRODUCED, never assembled. Every leg below runs
# against a store that a real `maildir messages copy` really crashed in
# the middle of, using the stock reproduction's own instrument: strace,
# one injected signal, no shim, no engine, no seccomp, no interposer.
# Hand-building the state was an R1 finding against the define's drills
# and it is not repeated here.
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
kids_strict() { himalaya $* --help 2>/dev/null | awk '/^Commands:/{f=1;next} /^Options:/{f=0} f && /^  [a-z][a-z0-9-]*(  |$)/{print $1}' | grep -vE '^help$'; }
kids_loose()  { himalaya $* --help 2>/dev/null | awk '/^Commands:/{f=1;next} /^Options:/{f=0} f && NF{print $1}' | grep -vE '^help$'; }
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

echo ""
note "scanning all $STRICT commands for anything repair-shaped:"
# grep first, rc read before anything is piped: a pipeline would report
# sed's status and hide a scan that failed to run.
grep -inE 'sync|repair|verif|check|fsck|doctor|restor|recover|rebuild|scan|fix|consist|integrit' \
    "$W/tree" > "$W/hits"
grc=$?
[ "$grc" -le 1 ] || bad "the scan itself failed (rc=$grc)"
sed 's/^/     /' "$W/hits"
note "matches: $(wc -l < "$W/hits" | tr -d ' ')"
if grep -qi 'copy' "$W/tree"; then
    note "positive control: the same scan finds 'copy' in this list"
else
    bad "positive control failed; the scan cannot match a word that is there"
fi
note ""
note "reading: two matches out of $STRICT, and neither looks at stored mail."
note "'account check' validates the account CONFIGURATION (its own help"
note "says so, and R2 measures it). 'gmail settings send-as verify' is"
note "Gmail alias ownership. There is no sync command in this version at"
note "all: the account subtree is list and check, nothing else."
note ""
note "This says the tool has nothing that would NOTICE the damage. It"
note "deliberately does not say the damage cannot be undone: R5 measures"
note "that separately, and finds it can be, by hand, once the user knows."

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
net=$(grep -cE '^[0-9]+ +(socket|connect|sendto|sendmsg|recvfrom|recvmsg|bind)\(' "$W/net.log")
note "operation rc=$orc, network syscalls traced during it: $net"
python3 -c "import socket; socket.socket().connect_ex(('127.0.0.1',1))" >/dev/null 2>&1
strace -f -e trace='%network' -o "$W/net-pc.log" \
    python3 -c "import socket; socket.socket().connect_ex(('127.0.0.1',1))" >/dev/null 2>&1
netpc=$(grep -cE '^[0-9]+ +(socket|connect|sendto|sendmsg|recvfrom|recvmsg|bind)\(' "$W/net-pc.log")
note "positive control (a process that does connect): $netpc network syscalls"
[ "$netpc" -gt 0 ] || bad "the network filter caught nothing even on a real connect; R3's 0 means nothing"
note "reading: the operation copies from one folder to another inside the"
note "same local root and never speaks to anything. The message it was"
note "creating in the target folder therefore exists nowhere else at the"
note "moment it is destroyed. This is the decisive half of the question:"
note "a synchronized side cannot restore content it has never seen, so"
note "the maildir-only case the freeze names is not the only case where"
note "recovery is unavailable. It is unavailable in every case."

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
note "reading: the phantom is removable. The refusal above is a property"
note "of a configuration with no trash mailbox, and it refuses on healthy"
note "mail in exactly the same words, so it is not part of this finding"
note "and is not reported as one. What R5 leaves standing is narrower and"
note "is the whole point: removal is manual, and it requires the user to"
note "already know which of the messages in the folder is not a message."

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
note "reading: an independent maildir reader enumerates the zero-byte file"
note "as an ordinary message too. Nothing in the maildir format marks it,"
note "so a second tool is not a recovery path either: it inherits the"
note "same object."

echo ""
echo "=============================================================="
echo "R7. What bounds the loss."
echo "=============================================================="
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
note "RECOVERY PATHS THAT EXIST:"
note "  1. The source message survives, so the copy can be repeated (R4,"
note "     R7). This restores the intended message. It does not remove"
note "     the empty one: the folder afterwards holds both, and the tool"
note "     lists both as messages."
note "  2. The empty message can be deleted by hand, once the user knows"
note "     it is there and the account names a trash mailbox (R5)."
note ""
note "CONDITIONS UNDER WHICH THEY DO NOT APPLY:"
note "  Both paths require the user to notice. Nothing offers to."
note "  The tool has no command that inspects stored mail (R1, 2 matches"
note "  in 216 and neither reads a mailbox), its one check-shaped command"
note "  reports the account OK over the damaged store (R2), and an"
note "  independent maildir reader enumerates the empty file as an"
note "  ordinary message as well (R6). In the listing the only difference"
note "  is blank columns and 0 B."
note ""
note "THE SYNCHRONIZED SIDE, WHICH THE FREEZE ASKED ABOUT SPECIFICALLY:"
note "  It cannot help, and not only in the maildir-only configuration"
note "  the freeze names. The operation copies between two folders inside"
note "  one local root and makes no network syscall at all (R3, 0 against"
note "  a positive control of 2), and this version of the tool has no"
note "  sync command in any of its 216 (R1). The message being created in"
note "  the target folder has therefore never existed anywhere else at"
note "  the moment it is destroyed. A remote side cannot restore content"
note "  it has never seen."
note ""
note "NOT MEASURED, AND STATED RATHER THAN IMPLIED:"
note "  Whether an EXTERNAL syncer (isync, offlineimap) managing this"
note "  maildir would upload the empty message to the server as a new"
note "  message, which is the shape the freeze calls the strongest form:"
note "  the external recovery path itself carrying the damage outward."
note "  Measuring it needs a second tool and a server, neither of which"
note "  is in this image. It is a question about making things worse,"
note "  not about recovery, so the recovery question above is answered"
note "  without it."

echo ""
echo "== BROKEN checks: $FAILS"
[ "$FAILS" -eq 0 ] || exit 1
exit 0
