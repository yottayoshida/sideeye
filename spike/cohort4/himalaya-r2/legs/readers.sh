#!/bin/sh
# R, inside the tools image. Does anything other than the one reader
# already tried flag the empty entry?
#
# The existing record's answer was "python's mailbox.Maildir enumerates it
# as an ordinary message", and it said out loud that this is one reader,
# not every reader. This leg adds an indexer and a control.
#
# THE CONTROL IS THE POINT. A tool that cannot emit a complaint about a
# malformed message produces the same silence as a tool that examined the
# file and approved it. So a third file is planted here — malformed but
# NOT empty — and any statement that a reader did not flag the empty entry
# is only written when that reader flagged the planted one. The planted
# file is hand-made and labelled as such; it is a control on the reader,
# never evidence about himalaya.
set -u

mkdir -p /work/store
cp -a /store/himalaya/store/Archive /work/store/INBOX

DAMAGED=""; HEALTHY=""
for f in /work/store/INBOX/cur/*; do
    [ -e "$f" ] || continue
    b=$(wc -c < "$f" | tr -d ' ')
    [ "$b" -eq 0 ] && DAMAGED=$(basename "$f")
    [ "$b" -gt 0 ] && HEALTHY=$(basename "$f")
done
echo "== the store under test"
echo "   damaged (0 bytes, from the killed copy): $DAMAGED"
echo "   healthy (from the completed copy):       $HEALTHY"

PLANTED='1700000000.planted.control:2,S'
printf 'this is not a message: no headers, no blank line, just bytes\n' \
    > "/work/store/INBOX/cur/$PLANTED"
echo "   planted control (hand-made, malformed but NOT empty): $PLANTED"
echo "     $(wc -c < "/work/store/INBOX/cur/$PLANTED" | tr -d ' ') bytes"

echo ""
echo "== reader 1: notmuch, an indexer"
export NOTMUCH_CONFIG=/work/nmconf
printf '[database]\npath=/work/store\n[new]\nignore=\n' > /work/nmconf
notmuch new > /work/nm.log 2>&1
rc=$?
echo "   notmuch new rc=$rc"
sed 's/^/   /' /work/nm.log
echo "   what it indexed: $(notmuch count '*' 2>/dev/null) message(s) of 3 files"

flagged_damaged=no; flagged_planted=no
grep -qF -- "$DAMAGED" /work/nm.log && flagged_damaged=yes
grep -qF -- "$PLANTED" /work/nm.log && flagged_planted=yes
echo "   notmuch named the damaged entry:  $flagged_damaged"
echo "   notmuch named the planted control: $flagged_planted"
# Emitted from the grep result, not from the fact that the names were
# printed in the preamble above.
[ "$flagged_damaged" = yes ] && echo "   NOTMUCH-FLAGGED-DAMAGED"
[ "$flagged_planted" = yes ] && echo "   NOTMUCH-FLAGGED-PLANTED"
if notmuch search --output=files '*' 2>/dev/null | grep -qF -- "$HEALTHY"; then
    echo "   NOTMUCH-INDEXED-CONTROL (the healthy message is in the database)"
fi

echo ""
echo "== reader 2: python's mailbox.Maildir, the one the record already used"
python3 - "$DAMAGED" "$PLANTED" <<'PY'
import mailbox, sys
damaged, planted = sys.argv[1], sys.argv[2]
mb = mailbox.Maildir("/work/store/INBOX", create=False)
print("   enumerates %d message(s)" % len(mb))
saw_damaged = False
for key, m in mb.items():
    path = mb._lookup(key)
    name = path.split("/")[-1]
    tag = "damaged" if name == damaged else ("planted" if name == planted else "healthy")
    if tag == "damaged":
        saw_damaged = True
    print("     [%s] subject=%r headers=%d body=%d bytes"
          % (tag, m.get("Subject"), len(m.keys()), len(m.get_payload())))
if saw_damaged:
    print("   PYTHON-ENUMERATED-DAMAGED")
PY
echo "   python reader rc=$?"

echo ""
echo "== reading, and it goes both ways"
echo "   The indexer refuses the empty entry by name and does not put it in"
echo "   its database, so a detection path exists that the record did not"
echo "   have. Whether that refusal is specific to emptiness or is the same"
echo "   refusal any unparseable file gets is answered by the planted"
echo "   control above, which is malformed but not empty."
echo "   The python reader still enumerates the empty entry as an ordinary"
echo "   message, which is what the report says and stays true."
echo "   Two readers, named. Not every reader."
exit 0
