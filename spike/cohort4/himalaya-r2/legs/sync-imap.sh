#!/bin/sh
# S2, inside the tools image. S1 established that the syncer decides to
# carry the empty entry. That decision is made on the near side and is the
# same decision whichever driver writes the far side — but whether a real
# IMAP server ACCEPTS the resulting APPEND is a different question, and
# only a server can answer it.
#
# The far side is read back over IMAP with an independent client, never by
# looking in dovecot's backing directory: what matters is what a second
# client of that mailbox would see, not what the server happens to store.
set -u

DOVECOT_OK=no
echo "== bringing up a real IMAP server"
id -u vmail >/dev/null 2>&1 || { groupadd -g 5000 vmail 2>/dev/null; useradd -u 5000 -g 5000 -d /srv/vmail -s /usr/sbin/nologin vmail 2>/dev/null; }
mkdir -p /srv/vmail/probe /run/dovecot
chown -R 5000:5000 /srv/vmail

cat > /work/dovecot.conf <<'EOF'
# dovecot 2.4 refuses any config whose first setting is not this one.
dovecot_config_version = 2.4.1
dovecot_storage_version = 2.4.1
protocols = imap
listen = 127.0.0.1
base_dir = /run/dovecot
log_path = /work/dovecot.log
ssl = no
auth_allow_cleartext = yes
auth_mechanisms = plain
mail_driver = maildir
mail_path = /srv/vmail/%{user}/Maildir
mail_uid = 5000
mail_gid = 5000
first_valid_uid = 5000
passdb static {
  password = probepass
}
userdb static {
  fields {
    uid = 5000
    gid = 5000
    home = /srv/vmail/%{user}
  }
}
service imap-login {
  inet_listener imap {
    port = 10143
  }
}
EOF

dovecot -c /work/dovecot.conf 2>/work/dovecot-start.err
start_rc=$?
echo "   dovecot start rc=$start_rc"
[ -s /work/dovecot-start.err ] && sed 's/^/   /' /work/dovecot-start.err
i=0
while [ $i -lt 20 ]; do
    if python3 -c 'import socket,sys; s=socket.socket(); s.settimeout(1); sys.exit(0 if s.connect_ex(("127.0.0.1",10143))==0 else 1)' 2>/dev/null; then
        DOVECOT_OK=yes; break
    fi
    i=$((i + 1)); sleep 1
done
echo "   IMAP reachable on 127.0.0.1:10143: $DOVECOT_OK"

if [ "$DOVECOT_OK" != yes ]; then
    echo ""
    echo "   S2-NOT-MEASURED"
    echo "   The server did not come up in this image, so the IMAP half is"
    echo "   NOT MEASURED. It is left that way on purpose: shrinking this leg"
    echo "   to the syncer's local decision would answer a different question"
    echo "   than the one the freeze asked, and calling that an answer is the"
    echo "   failure mode this project keeps refusing."
    [ -s /work/dovecot.log ] && tail -10 /work/dovecot.log | sed 's/^/     /'
    exit 0
fi

mkdir -p /work/inear
cp -a /store/himalaya/store/Archive /work/inear/INBOX
DAMAGED=""; HEALTHY=""
for f in /work/inear/INBOX/cur/*; do
    [ -e "$f" ] || continue
    b=$(wc -c < "$f" | tr -d ' ')
    [ "$b" -eq 0 ] && DAMAGED=$(basename "$f")
    [ "$b" -gt 0 ] && HEALTHY=$(basename "$f")
done
echo "   near side: $DAMAGED (0 bytes) and $HEALTHY"

cat > /work/mbi.rc <<'EOF'
IMAPAccount srv
Host 127.0.0.1
Port 10143
User probe
Pass probepass
TLSType None
AuthMechs LOGIN

IMAPStore far
Account srv

MaildirStore near
Path /work/inear/
Inbox /work/inear/INBOX
SubFolders Verbatim

Channel t
Far :far:
Near :near:
Patterns "INBOX"
Create Both
Sync Push
SyncState *
EOF

echo ""
echo "== pushing the folder to the server"
mbsync -c /work/mbi.rc -V t > /work/imap-sync.log 2>&1
rc=$?
echo "   mbsync rc=$rc (taken from the command)"
grep -E "^(near|far) side:|^Channels:|error|Error" /work/imap-sync.log | sed 's/^/   /' | head -8

echo ""
echo "== what a client asking the server sees, not what the disk holds"
python3 - <<'PY'
import imaplib
m = imaplib.IMAP4("127.0.0.1", 10143)
m.login("probe", "probepass")
typ, data = m.select("INBOX")
print("   SELECT INBOX -> %s %s" % (typ, data[0].decode()))
typ, nums = m.search(None, "ALL")
ids = nums[0].split()
print("   the server reports %d message(s) in INBOX" % len(ids))
for i in ids:
    typ, d = m.fetch(i, "(RFC822.SIZE BODY.PEEK[HEADER.FIELDS (SUBJECT)])")
    meta = d[0][0].decode(errors="replace")
    size = meta.split("RFC822.SIZE")[1].split()[0].strip("() ") if "RFC822.SIZE" in meta else "?"
    subj = b"".join(x[1] for x in d if isinstance(x, tuple)).decode(errors="replace").strip()
    print("     uid-seq %s  RFC822.SIZE=%s  subject=%r" % (i.decode(), size, subj))
    if "Existing message, fixed bytes" in subj:
        print("   IMAP-CONTROL-ON-SERVER")
m.logout()
PY
echo "   independent IMAP read rc=$?"

echo ""
echo "== the same question without an identification in it"
echo "   Above, which arrival is which rests on subject and size. The push"
echo "   below carries ONE entry — the 0-byte one — into a mailbox of its"
echo "   own, so the server's count for that mailbox is about that entry"
echo "   and nothing else. Then a clean second store pulls the account, the"
echo "   way another device would."
# The isolated mailbox is a SUBFOLDER, so the store still needs an Inbox of
# its own: pointing Inbox at the isolated maildir and then matching it with
# Patterns "ISO" makes mbsync match nothing and create nothing, which is how
# the first attempt produced a NONEXISTENT mailbox on the server.
for d in cur new tmp; do
    mkdir -p "/work/iso-near/INBOX/$d" "/work/iso-near/ISO/$d" \
             "/work/pull/INBOX/$d" "/work/pull/ISO/$d"
done
cp -a "/store/himalaya/store/Archive/cur/$DAMAGED" "/work/iso-near/ISO/cur/$DAMAGED"
cat > /work/mbi-iso.rc <<'EOF'
IMAPAccount srv
Host 127.0.0.1
Port 10143
User probe
Pass probepass
TLSType None
AuthMechs LOGIN

IMAPStore far
Account srv

MaildirStore isonear
Path /work/iso-near/
Inbox /work/iso-near/INBOX
SubFolders Verbatim

Channel iso
Far :far:
Near :isonear:
Patterns "ISO"
Create Both
Sync Push
SyncState *
EOF
mbsync -c /work/mbi-iso.rc -V iso > /work/imap-iso.log 2>&1
echo "   isolated push rc=$? — $(grep -E '^Channels:' /work/imap-iso.log | head -1)"

sed -e 's|Path /work/iso-near/|Path /work/pull/|' \
    -e 's|Inbox /work/iso-near/INBOX|Inbox /work/pull/INBOX|' \
    -e 's|Sync Push|Sync Pull|' /work/mbi-iso.rc > /work/mbi-pull.rc
mbsync -c /work/mbi-pull.rc -V iso > /work/imap-pull.log 2>&1
pull_rc=$?
echo "   second-device pull rc=$pull_rc — $(grep -E '^Channels:' /work/imap-pull.log | head -1)"

python3 - "$DAMAGED" <<'PY'
import imaplib, os, sys
damaged = sys.argv[1]
m = imaplib.IMAP4("127.0.0.1", 10143)
m.login("probe", "probepass")
typ, data = m.select("ISO")
n = int(data[0].decode())
print("   the server reports %d message(s) in the isolated mailbox" % n)
if n == 1:
    typ, d = m.fetch(b"1", "(RFC822.SIZE)")
    print("     its size on the server: %s" % d[0].decode(errors="replace"))
    print("   IMAP-ISOLATED-EMPTY-ON-SERVER")
m.logout()
got = []
for sub in ("cur", "new"):
    p = os.path.join("/work/pull/ISO", sub)
    got += [f for f in os.listdir(p)] if os.path.isdir(p) else []
print("   a clean second store pulled %d file(s) from that mailbox" % len(got))
for f in got:
    for sub in ("cur", "new"):
        fp = os.path.join("/work/pull/ISO", sub, f)
        if os.path.exists(fp):
            print("     %s = %d bytes" % (f, os.path.getsize(fp)))
if len(got) == 1:
    print("   IMAP-SECOND-DEVICE-GOT-EMPTY")
PY
echo "   isolated read + second-device pull rc=$pull_rc"

echo ""
echo "== reading"
echo "   dovecot $(dovecot --version 2>/dev/null | head -1), one account, plaintext on"
echo "   loopback. What is measured is what an IMAP client asking the server"
echo "   sees after the folder was pushed — the same question a second"
echo "   device would ask. Nothing here is about other servers or other"
echo "   syncers."
exit 0
