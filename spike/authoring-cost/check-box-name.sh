#!/bin/sh
# One spelling of the box name across every file that names it (#618).
#
# The onboarding clock records the failure this prevents: its audit hard-codes the box in a
# predicate, its launcher builds the command, and when the two drifted every legitimate call
# fell outside the allow-set while the audit's promise was still satisfied — green, and measuring
# nothing. This study's files name the box in three places (the prompt the subject must obey, the
# launcher's default, the box creator's default), so the same drift is available here.
#
# What this does NOT check: that the name is right. It checks that there is only one.
set -u

here="$(cd "$(dirname "$0")" && pwd)"
fails=0

# The name is READ from box.sh's default rather than written here. A constant in this file
# would be a fourth spelling — and the check whose job is "there is only one spelling" would be
# the thing that added one. `spike/check-box-name.sh` derives it the same way for the same
# reason.
NAME=$(sed -n 's/^BOX_NAME=${BOX_NAME:-\([a-z0-9-]*\)}.*/\1/p' "$here/box.sh" | head -1)
[ -n "$NAME" ] || { echo "FAIL: box.sh declares no BOX_NAME default to check against"; exit 1; }

for f in prompt.md box.sh run-authoring.sh; do
    path="$here/$f"
    [ -f "$path" ] || { echo "FAIL: $f is missing"; fails=$((fails + 1)); continue; }
    if ! grep -q "$NAME" "$path"; then
        echo "FAIL: $f does not name $NAME — a file that stopped naming the box is the drift"
        fails=$((fails + 1))
    fi
done

# Any other spelling of a box in these files is the drift itself.
others=$(grep -ho 'docker exec [a-z0-9-]*' "$here"/prompt.md "$here"/box.sh "$here"/run-authoring.sh 2>/dev/null |
    awk '{print $3}' | LC_ALL=C sort -u | grep -v "^$NAME$" | grep -v '^"' || true)
if [ -n "$others" ]; then
    echo "FAIL: another box name appears: $(echo "$others" | tr '\n' ' ')"
    fails=$((fails + 1))
fi

echo "scanned: 3 file(s) for the box name $NAME"
[ "$fails" = "0" ] || exit 1
echo "ok   one spelling of the box name across the prompt, the launcher and the box creator"
