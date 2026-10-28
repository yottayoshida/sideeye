#!/bin/sh
# After a crash anywhere inside `grains.setval`, Salt itself still reads every grain the user had set:
# `grains.get` through the same masterless minion returns each of the seeded values.
set -u
d=${SIDEEYE_STATE_DIR:?}
fail() { echo "checker(salt-grains): $*"; exit 1; }
[ -f "$d/grains" ] || fail "the grains file is missing"
out=$(/opt/salt/salt/bin/python3.14 /opt/salt/salt/salt-call -c "$d" --local --out=json grains.item datacenter environment owner rack cost_center 2>&1) || fail "salt-call grains.item exited $?: $(echo "$out" | tail -c 200)"
for v in tokyo-2 production platform-team r12-u07 CC-4410; do
    printf '%s' "$out" | grep -q "\"$v\"" || fail "grain value $v is gone: $(echo "$out" | tr -d '\n' | cut -c1-200)"
done
exit 0
