#!/bin/sh
# S1, inside the tools image. The damaged store is mounted read-only at
# /store; everything here works on a copy, so nothing the syncer writes
# (.mbsyncstate, the ,U= infix it appends to near-side names) touches the
# measured artifact.
#
# The far side is a Maildir rather than an IMAP server on purpose: what is
# being asked first is whether the syncer classifies the empty entry as a
# message to carry at all. If it does not, no server is needed to know the
# answer. It does, so the IMAP half is asked separately.
set -u

mkdir -p /work/near /work/far
cp -a /store/himalaya/store/Archive /work/near/INBOX
for d in cur new tmp; do mkdir -p "/work/far/INBOX/$d"; done

DAMAGED=""; HEALTHY=""
echo "== the near side, before"
for f in /work/near/INBOX/cur/*; do
    [ -e "$f" ] || continue
    b=$(wc -c < "$f" | tr -d ' ')
    echo "   $(basename "$f") = $b bytes"
    [ "$b" -eq 0 ] && DAMAGED=$(basename "$f")
    [ "$b" -gt 0 ] && HEALTHY=$(basename "$f")
done

cat > /work/mb.rc <<EOF
MaildirStore near
Path /work/near/
Inbox /work/near/INBOX
SubFolders Verbatim

MaildirStore far
Path /work/far/
Inbox /work/far/INBOX
SubFolders Verbatim

Channel t
Far :far:
Near :near:
Patterns "INBOX"
Create Both
Sync All
SyncState *
EOF

echo ""
echo "== the sync, with maildir and sync debug on"
mbsync -c /work/mb.rc -Dm -Ds -V t > /work/sync.log 2>&1
rc=$?
echo "   mbsync rc=$rc (taken from the command, not through a pipe)"
grep -E "^(near|far) side:|^Channels:" /work/sync.log | sed 's/^/   /'

# The claim that matters is not "two things arrived" but "the syncer looked
# at THIS file". Its own debug output has to name it.
if [ -n "$DAMAGED" ] && grep -qF -- "$DAMAGED" /work/sync.log; then
    echo "   SYNCER-NAMED-DAMAGED $DAMAGED"
    echo "   the syncer's own output names the damaged entry:"
    grep -F -- "$DAMAGED" /work/sync.log | head -3 | sed 's/^/     /'
else
    echo "   the syncer's output never names $DAMAGED — nothing below is about that file"
fi

echo ""
echo "== the far side, after"
for f in /work/far/INBOX/cur/* /work/far/INBOX/new/*; do
    [ -e "$f" ] || continue
    b=$(wc -c < "$f" | tr -d ' ')
    echo "   $(basename "$f") = $b bytes"
    if [ "$b" -lt 100 ]; then
        echo "     its entire content:"
        sed 's/^/       /' "$f"
        echo "   FAR-EMPTY-ARRIVED"
    else
        subj=$(sed -n 's/^Subject: //p' "$f" | head -1)
        echo "     subject: ${subj:-<none>}"
        [ -n "$subj" ] && echo "   FAR-CONTROL-ARRIVED"
    fi
done

echo ""
echo "== the same question without an inference in it"
echo "   The run above proves two entries went out, and identifies which is"
echo "   which by size. mbsync's own debug output does not name individual"
echo "   files at any verbosity tried (-Dm -Ds), so that identification is"
echo "   an inference rather than the tool saying so. The isolation below"
echo "   removes the inference: each entry is synced ALONE from a clean"
echo "   near side into a clean far side, so the far side's count is about"
echo "   that entry and nothing else."
isolate() { # <label> <source-basename> <marker>
    lbl=$1; src=$2; marker=$3
    rm -rf /work/iso 2>/dev/null
    for d in cur new tmp; do mkdir -p "/work/iso/near/INBOX/$d" "/work/iso/far/INBOX/$d"; done
    cp -a "/store/himalaya/store/Archive/cur/$src" "/work/iso/near/INBOX/cur/$src"
    sed -e 's|/work/near/|/work/iso/near/|g' -e 's|/work/far/|/work/iso/far/|g' /work/mb.rc > /work/iso/mb.rc
    mbsync -c /work/iso/mb.rc -V t > "/work/iso/$lbl.log" 2>&1
    irc=$?
    n=0
    for g in /work/iso/far/INBOX/cur/* /work/iso/far/INBOX/new/*; do
        [ -e "$g" ] || continue
        n=$((n + 1)); sz=$(wc -c < "$g" | tr -d ' ')
    done
    echo "   $lbl: near held only $src ($(wc -c < "/store/himalaya/store/Archive/cur/$src" | tr -d ' ') bytes)"
    echo "     mbsync rc=$irc, far side afterwards: $n entry(ies)${sz:+, $sz bytes}"
    [ "$n" -eq 1 ] && echo "   $marker"
    unset sz
}
[ -n "$DAMAGED" ] && isolate "damaged-alone" "$DAMAGED" "ISOLATED-EMPTY-TRAVELLED"
[ -n "$HEALTHY" ] && isolate "healthy-alone" "$HEALTHY" "ISOLATED-CONTROL-TRAVELLED"

echo ""
echo "== reading, kept to what this measured"
echo "   isync $(mbsync --version 2>&1 | head -1 | tr -d '\n'), Maildir to Maildir, one channel,"
echo "   one configuration. The near side held two entries produced by real"
echo "   operations; the syncer loaded both as messages and pushed both."
echo "   What lands on the far side for the empty one is a message whose"
echo "   whole content is the syncer's own tracking header."
echo "   This says nothing about other syncers, other configurations, or"
echo "   what an IMAP server would accept — the IMAP half is its own leg."
exit 0
