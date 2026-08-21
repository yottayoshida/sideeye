#!/bin/sh
# Per-leg falsification of the borg-create checker: greens as controls,
# each red against an input violating exactly its leg. Normal executions
# and synthetic corruption only — no kill, no engine. Runs under the same
# frozen apparatus the define declares (installed here for the drills).
set -u
here=$(cd "$(dirname "$0")" && pwd)
OPS="$here/ops"
B=/tmp/cohort2/borg
FTLIB=$(find /usr/lib -name "libfaketime.so.1" | head -1)
[ -n "$FTLIB" ] || { echo "SETUP: libfaketime not in the image"; exit 2; }
echo "$FTLIB" > /etc/ld.so.preload
export FAKETIME="@2026-01-01 00:00:00 x0"
export PYTHONPATH="$B/pylib"
export BORG_BASE_DIR="$B/ambient"
FAILS=0
want() { if [ "$3" = "$2" ]; then echo "drill ok   $1 (rc=$3)"; else echo "drill FAIL $1 (rc=$3, wanted $2)"; FAILS=$((FAILS+1)); fi; }

echo "== borg-create checker drills — $(borg --version) — frozen apparatus active"

# green 1: the pre-state (old shape: base only, no lock)
"$OPS/setup.sh" > /dev/null 2>&1
SIDEEYE_STATE_DIR="$B/state" "$OPS/check.sh"; want "green-old-state" 0 $?

# green 2: the post-state (new shape: base + probe)
borg create --timestamp 2026-01-01T00:00:00 "$B/state/repo::probe" "$B/src" > /dev/null 2>&1
SIDEEYE_STATE_DIR="$B/state" "$OPS/check.sh"; want "green-new-state" 0 $?

# red V: a corrupted segment in an otherwise complete repo
"$OPS/setup.sh" > /dev/null 2>&1
seg=$(find "$B/state/repo/data" -type f | head -1)
printf 'JUNKJUNKJUNK' >> "$seg"
SIDEEYE_STATE_DIR="$B/state" "$OPS/check.sh"; want "red-leg-V" 1 $?

# red T: a third archive the contract does not allow
"$OPS/setup.sh" > /dev/null 2>&1
borg create --timestamp 2026-01-01T00:00:00 "$B/state/repo::probe" "$B/src" > /dev/null 2>&1
borg create --timestamp 2026-01-02T00:00:00 "$B/state/repo::third" "$B/src" > /dev/null 2>&1
SIDEEYE_STATE_DIR="$B/state" "$OPS/check.sh"; want "red-leg-T" 1 $?

# red C: a VALID repo whose base bytes differ (borg check passes,
# conservation fails — the leg V cannot cover)
"$OPS/setup.sh" > /dev/null 2>&1
rm -rf "$B/state" && mkdir -p "$B/state"
rm -rf "$B/ambient"
printf 'different bytes\n' > "$B/src/alpha"
touch -t 202601010000 "$B/src/alpha"
borg init --encryption=none "$B/state/repo" > /dev/null 2>&1
borg create --timestamp 2026-01-01T00:00:00 "$B/state/repo::base" "$B/src" > /dev/null 2>&1
SIDEEYE_STATE_DIR="$B/state" "$OPS/check.sh"; want "red-leg-C" 1 $?

# red N: the probe archive exists but carries the wrong bytes (a valid
# two-archive repo whose probe was made from unmodified content)
"$OPS/setup.sh" > /dev/null 2>&1
printf 'alpha file, fixed bytes\n' > "$B/src/alpha"
touch -t 202601010000 "$B/src/alpha"
borg create --timestamp 2026-01-01T00:00:00 "$B/state/repo::probe" "$B/src" > /dev/null 2>&1
SIDEEYE_STATE_DIR="$B/state" "$OPS/check.sh"; want "red-leg-N" 1 $?

# red R: a stale lock break-lock cannot remove (store unwritable, as
# nobody — to root every permission is a suggestion)
"$OPS/setup.sh" > /dev/null 2>&1
mkdir -p "$B/state/repo/lock.exclusive"
chmod -R a+rX "$B" && chmod 555 "$B/state/repo"
su nobody -s /bin/sh -c "FAKETIME='@2026-01-01 00:00:00 x0' PYTHONPATH='$B/pylib' BORG_BASE_DIR='$B/ambient' SIDEEYE_STATE_DIR='$B/state' '$OPS/check.sh'"; want "red-leg-R" 1 $?
chmod 755 "$B/state/repo"

echo "== drills failed: $FAILS"
[ "$FAILS" -eq 0 ] && exit 0 || exit 1
