#!/bin/sh
# Run `sideeye preflight --twice` for a B2 define while authoring it (#619):
# the released engine (fetch-engine.sh's staging for the generation), a fresh
# sideeye-ur-b2 container with the package installed at run time, the repo
# mounted read-only — and the launcher itself, launchers/bgroup.sh with
# BGROUP_PREFLIGHT_ONLY set, so the define is read here exactly as the sweep
# will read it (op.txt's one line, expect-status's digits, env.sh, the scratch
# HOME): a define that passes here is not refused there on a reading this
# script never made. Preflight only — exploring a candidate before the sweep
# would pre-empt the measurement; what this establishes is that the define is
# spelled, the setup seeds state, and two runs leave the same bytes (exit 0),
# or names what differs (exit 1), or what refused (exit 2). On exit 0 the clock
# records first_accepted_recording (once; the guard is b2-clock.sh's).
#
# Usage: b2-preflight.sh <package> [generation]      (generation defaults to g3)
set -u
t=${1:?package}; gen=${2:-g3}
here=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$here/../.." && pwd)
defs=$here/defines-b2/$t
[ -x "$defs/setup.sh" ] || { echo "b2-preflight: $defs/setup.sh missing or not executable" >&2; exit 2; }
engdir=$(sh "$here/fetch-engine.sh" "$gen" | cut -f1) || exit 2
[ -n "$engdir" ] || exit 2
mkdir -p "$ROOT/zig-out" || exit 2
out=$HOME/.cctmp/b2-author
mkdir -p "$out" || exit 2
log=$out/$t.preflight.txt

# packages.txt beside the define lists the Debian packages its environment needs
# beyond the target itself (a font to convert, the `paper` command psutils
# calls); the sweep image installs the same list, named per define.
extra=""
[ -f "$defs/packages.txt" ] && extra=$(grep -v '^#' "$defs/packages.txt" | tr '\n' ' ')
docker run --rm -v "$ROOT":/work:ro -v "$engdir/zig-out":/work/zig-out:ro \
    -e BGROUP_PREFLIGHT_ONLY=1 sideeye-ur-b2 sh -c '
  t="$1"; extra="$2"
  apt-get install -y --no-install-recommends "$t" $extra >/tmp/install.log 2>&1 || { echo "install failed"; tail -n 5 /tmp/install.log; exit 3; }
  /work/spike/unknown-rate/launchers/bgroup.sh "$t" /tmp/bgroup-art
  rc=$?
  cat /tmp/bgroup-art/preflight.txt 2>/dev/null
  exit $rc
' sh "$t" "$extra" > "$log" 2>&1
rc=$?
tail -n 25 "$log"
[ "$rc" = 0 ] && sh "$here/b2-clock.sh" "$t" first_accepted_recording >/dev/null
echo "b2-preflight: $t exit=$rc (log: $log)"
exit $rc
