#!/bin/sh
# T, inside the untouched cohort-4 image. external-recovery.txt measured
# that `message delete` relocates the empty entry into Trash and left one
# thing open in the same sentence: "whether emptying the trash removes it
# was not measured". That matters for a low-value assessment — how far the
# user can get with the tool alone — so it is measured here.
set -u

P=/tmp/cohort4/himalaya
C=$P/config-trash.toml
STORE=$P/store

echo "== the store as the damage left it"
for f in "$STORE"/Archive/cur/*; do
    [ -e "$f" ] || continue
    b=$(wc -c < "$f" | tr -d ' ')
    echo "   Archive/cur/$(basename "$f") = $b bytes"
    [ "$b" -eq 0 ] && DAMAGED=$(basename "$f")
done
DAMAGED=${DAMAGED:-}
[ -n "$DAMAGED" ] || { echo "   no 0-byte entry present; nothing to measure"; exit 0; }

# The refusal external-recovery.txt measured first is a property of an
# account with no trash mailbox, not of the damaged message: it refuses in
# the same words on healthy mail. So the account is given one here, which
# is what the tool's own error message asks for.
for d in cur new tmp; do mkdir -p "$STORE/Trash/$d"; done
sed 's/^\[accounts.probe\]/[accounts.probe]\nmailbox.alias.trash = "Trash"/' "$P/config.toml" > "$C"
echo ""
echo "== with a trash mailbox configured, as the tool's error asks"
id=$(echo "$DAMAGED" | cut -d: -f1)
himalaya -c "$C" message delete -m Archive "$id" > /tmp/del.out 2>&1
del1_rc=$?
echo "   message delete rc=$del1_rc — $(head -1 /tmp/del.out)"
tn=$(ls "$STORE/Trash/cur" 2>/dev/null | wc -l | tr -d ' ')
echo "   Archive/cur now: $(ls "$STORE/Archive/cur" 2>/dev/null | wc -l | tr -d ' ') entry(ies)"
echo "   Trash/cur now:   $tn entry(ies)"
tzero=no
for f in "$STORE"/Trash/cur/*; do
    [ -e "$f" ] || continue
    tb=$(wc -c < "$f" | tr -d ' ')
    echo "     in Trash: $(basename "$f") = $tb bytes"
    [ "$tb" -eq 0 ] && tzero=yes
done
# Emitted from the command's rc and the folder's own contents, never from
# the fact that this script reached this line.
if [ "$del1_rc" -eq 0 ] && [ "$tn" -eq 1 ] && [ "$tzero" = yes ]; then
    echo "   TRASH-MOVED-ZERO-BYTE"
else
    echo "   the first delete did not put exactly one 0-byte entry in Trash (rc=$del1_rc, count=$tn, zero=$tzero)"
fi

echo ""
echo "== is there a command that empties it?"
echo "   the shared mailbox API:"
himalaya mailbox --help 2>&1 | sed -n '/Commands:/,/Options:/p' | sed 's/^/     /'
echo "   the maildir-specific API:"
himalaya maildir --help 2>&1 | sed -n '/Commands:/,/Options:/p' | sed 's/^/     /'

echo "   scanning the blocks inspected above — and ONLY those — for a name"
echo "   that could remove it. This is not a claim about the whole surface:"
echo "   the IMAP-specific API does carry an expunge, which is an IMAP"
echo "   command and not a route for a maildir account, and it is named"
echo "   here so the scan is not read as wider than it is."
for blk in "" "mailbox" "maildir"; do
    h=$(himalaya $blk --help 2>&1 | sed -n '/Commands:/,/Options:/p' | \
        grep -icE 'purge|empty|expunge|vacuum|compact')
    echo "     ${blk:-<top level>}: names matching purge/empty/expunge/vacuum/compact = $h"
done
imaph=$(himalaya imap --help 2>&1 | sed -n '/Commands:/,/Options:/p' | \
        grep -icE 'purge|empty|expunge|vacuum|compact')
echo "     imap (named for contrast, not a maildir route): $imaph"
ctl=$(printf 'expunge  Remove deleted messages\n' | grep -icE 'purge|empty|expunge|vacuum|compact')
echo "   positive control, the same expression against a string that must match: $ctl"
[ "$ctl" -ge 1 ] && echo "   TRASH-SCAN-CONTROL-FIRES"

echo ""
echo "== the second delete: what happens to a message already in Trash?"
tid=$(ls "$STORE/Trash/cur" 2>/dev/null | head -1 | cut -d: -f1)
if [ -n "$tid" ]; then
    himalaya -c "$C" message delete -m Trash "$tid" > /tmp/del2.out 2>&1
    del2_rc=$?
    after=$(ls "$STORE/Trash/cur" 2>/dev/null | wc -l | tr -d ' ')
    echo "   message delete on the Trash copy rc=$del2_rc — $(head -1 /tmp/del2.out)"
    echo "   Trash/cur afterwards: $after entry(ies)"
    for f in "$STORE"/Trash/cur/*; do
        [ -e "$f" ] || continue
        echo "     still there: $(basename "$f") = $(wc -c < "$f" | tr -d ' ') bytes"
    done
    if [ "$del2_rc" -eq 0 ] && [ "$after" -eq 0 ]; then
        echo "   TRASH-SECOND-DELETE-REMOVED"
    else
        echo "   the second delete did not empty the folder (rc=$del2_rc, remaining=$after)"
    fi
fi

echo ""
echo "== reading"
echo "   Scoped to this account configuration and this build. What the tool"
echo "   can do is relocate the empty entry into a trash mailbox the user"
echo "   creates and names first. Whether anything in the surface then"
echo "   removes it is what the scan above answers, with its own positive"
echo "   control so that a count of zero means the expression works and"
echo "   found nothing, rather than that it matches nothing at all."
exit 0
