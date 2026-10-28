#!/bin/sh
# After a crash anywhere inside `systemd-sysusers --root=`, the image root's four databases are
# consistent by shadow-utils' own checkers (read-only, against the root, not the box's /etc), every
# account and group that was there before is still there, and the two halves of each database agree:
# a user in passwd has a shadow line and a group in group has a gshadow line.
set -u
d=${SIDEEYE_STATE_DIR:?}
fail() { echo "checker(sysusers): $*"; exit 1; }
for f in passwd shadow group gshadow; do [ -f "$d/etc/$f" ] || fail "etc/$f is missing"; done
o=$(pwck -r -q -R "$d" 2>&1); rc=$?
[ "$rc" -le 0 ] || fail "pwck -r exited $rc: $(echo "$o" | head -3 | tr '\n' ' ')"
o=$(grpck -r -R "$d" 2>&1); rc=$?
[ "$rc" -le 0 ] || fail "grpck -r exited $rc: $(echo "$o" | head -3 | tr '\n' ' ')"
for u in root daemon www-data postgres alice nobody; do
    grep -q "^$u:" "$d/etc/passwd" || fail "user $u is gone from passwd"
    grep -q "^$u:" "$d/etc/shadow" || fail "user $u is gone from shadow"
done
for g in root adm sudo postgres ssl-cert alice nogroup; do
    grep -q "^$g:" "$d/etc/group" || fail "group $g is gone from group"
    grep -q "^$g:" "$d/etc/gshadow" || fail "group $g is gone from gshadow"
done
exit 0
