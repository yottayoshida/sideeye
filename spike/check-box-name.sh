#!/bin/sh
# The onboarding clock's container name has one spelling, and every file that
# has to agree does.
#
# The name is not a string in one place. `clock-audit.py`'s box predicate
# tokenizes a command and rejects a leading triple that is not exactly
# `docker exec <name>`; `prompt.md` instructs the driver to use that form; the
# launcher's allow-set scopes Bash to it; and CI's fixtures are written in it.
# Change it in one file and the audit disagrees with the launcher in silence —
# every legitimate box call lands off-allowlist, which still satisfies the
# audit's promise, so nothing goes red. That is why `box.sh` keeps the name a
# constant rather than a parameter, and why this exists instead.
#
# The paths are written out rather than globbed. A glob that matches nothing
# reports that every file agrees, which is the failure this check would be
# added to prevent; a named path that has moved is a failure here.
set -u

root=${1:-$(cd "$(dirname "$0")/.." && pwd)}
def="$root/spike/onboarding-clock/box.sh"
fails=0

# The one definition: box.sh's default. Everything below is compared to this
# rather than to a literal repeated here, so this script cannot be the file
# that drifts.
name=$(sed -n 's/^BOX_NAME=${BOX_NAME:-\(.*\)}$/\1/p' "$def")
if [ -z "$name" ]; then
    echo "FAIL  could not read the box name from $def" >&2
    echo "      expected a line of the form: BOX_NAME=\${BOX_NAME:-<name>}" >&2
    exit 1
fi
echo "box name, from box.sh: $name"

# Every file here must carry the name at least once. The count is printed, not
# just tested, because a check that only says "at least one" cannot show that a
# file it was supposed to cover went quiet for another reason.
for rel in \
    spike/onboarding-clock/clock-audit.py \
    spike/onboarding-clock/run-clock.sh \
    spike/onboarding-clock/prompt.md \
    spike/onboarding-clock/PROTOCOL.md \
    .github/workflows/ci.yml
do
    path="$root/$rel"
    if [ ! -f "$path" ]; then
        echo "FAIL  $rel does not exist — this check names its files, so a move is a failure here" >&2
        fails=$((fails + 1))
        continue
    fi
    # Raw rc, not a pipeline's: `grep -c` returns 1 on zero matches and the
    # count is what says which.
    n=$(grep -c -F "$name" "$path")
    rc=$?
    if [ "$rc" != 0 ] || [ "$n" = 0 ]; then
        echo "FAIL  $rel does not name $name (grep rc=$rc, count=$n)" >&2
        fails=$((fails + 1))
    else
        echo "ok    $rel  ($n)"
    fi
done

# The one line the whole coupling rests on. A file-level count would stay green
# if this predicate alone moved, because clock-audit.py names the box in two
# dozen other places (fixtures, comments, the selftest's allow spec).
pred="$root/spike/onboarding-clock/clock-audit.py"
if [ -f "$pred" ]; then
    if grep -q -F "if toks[:3] != [\"docker\", \"exec\", \"$name\"]:" "$pred"; then
        echo "ok    clock-audit.py's box predicate names $name"
    else
        echo "FAIL  clock-audit.py's box predicate does not name $name" >&2
        echo "      looked for: if toks[:3] != [\"docker\", \"exec\", \"$name\"]:" >&2
        fails=$((fails + 1))
    fi
fi

# The launcher's allow-set. Same reason: the scope string is what the CLI is
# given, and it is not the same line as anything above.
launcher="$root/spike/onboarding-clock/run-clock.sh"
if [ -f "$launcher" ]; then
    if grep -q -F "ALLOWED=\"Bash(docker exec $name *)" "$launcher"; then
        echo "ok    run-clock.sh's allow-set scopes Bash to $name"
    else
        echo "FAIL  run-clock.sh's allow-set does not scope Bash to $name" >&2
        fails=$((fails + 1))
    fi
fi

# CI's fixture. The per-file counts above are presence, not identity: this job
# also sets `BOX_NAME=onboarding-box-ci` for its throwaway box, and that string
# contains the production name, so a rename that left the CI fixture behind
# would still count. This looks at the fixture itself.
ci="$root/.github/workflows/ci.yml"
if [ -f "$ci" ]; then
    if grep -q -F "docker exec $name true" "$ci"; then
        echo "ok    ci.yml's audit fixture is written in $name"
    else
        echo "FAIL  ci.yml's audit fixture does not use $name" >&2
        echo "      looked for: docker exec $name true" >&2
        fails=$((fails + 1))
    fi
fi

if [ "$fails" != 0 ]; then
    echo "$fails check(s) failed" >&2
    exit 1
fi
echo "ok: every file that must name the box names $name"
