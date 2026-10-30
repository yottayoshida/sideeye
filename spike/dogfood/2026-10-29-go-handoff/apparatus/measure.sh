#!/bin/sh
# Inside the box: one target, N runs in each of two arms, each run seeded first as 2026-10-25's
# lab-s1.sh seeded it. Arm 1 prints at most 64 bytes of any string (`-s 64`: the state's prefix of a
# path survives, a write's bytes mostly do not) so strace slows the target as little as it can; arm 2
# carries the bytes (`-s 1048576 -x`). Not `-e raw=` on the writes: it drops `-y`'s path from the fd.
#   docker run --rm --network none -v <2026-10-25 apparatus>:/ap:ro -v <this apparatus>:/hp:ro \
#     -v <out>:/out sideeye-gh1029 sh /hp/measure.sh <define | ctl-race | ctl-condvar> <N>
set -u
t=$1 n=$2
o=/out/$t; mkdir -p "$o/arm1" "$o/arm2"
case $t in
  ctl-*) state=/s/ctl cwd=/s scratch=- op="/opt/bin/$t /s/ctl"
         seed() { rm -rf /s/ctl && mkdir -p /s/ctl; } ;;
  *)     d=/ap/defines/$t
         eval "$(python3 - "$d/sideeye.toml" <<'PY'
import shlex, sys, tomllib
c = tomllib.load(open(sys.argv[1], "rb"))
op = c["define"]["operation"]
print("state=" + shlex.quote(c["world"]["state"]))
print("cwd=" + shlex.quote(c["define"].get("cwd", "/")))
print("scratch=" + shlex.quote(",".join(c["define"].get("scratch", [])) or "-"))
print("op=" + shlex.quote(op if isinstance(op, str) else " ".join(shlex.quote(a) for a in op)))
PY
)"
         seed() { (. /ap/env.sh; [ -f "$d/env.sh" ] && . "$d/env.sh"; sh "$d/seed.sh") > "$o/seed.log" 2>&1; } ;;
esac
printf 'state=%s\ncwd=%s\nscratch=%s\nop=%s\n' "$state" "$cwd" "$scratch" "$op" > "$o/define.txt"
raw="-s 64"
for arm in 1 2; do
  [ $arm = 1 ] && opts=$raw || opts="-s 1048576 -x"
  i=1
  while [ $i -le "$n" ]; do
    f=$(printf '%s/arm%s/run%02d' "$o" $arm $i)
    seed || { echo "$t arm$arm run$i: seed failed" >&2; tail -3 "$o/seed.log" >&2; exit 1; }
    find "$state" -mindepth 1 > "$f.initial"
    ( . /ap/env.sh 2>/dev/null; [ -n "${d:-}" ] && [ -f "$d/env.sh" ] && . "$d/env.sh"
      cd "$cwd" && strace -f -ttt -T -y $opts -o "$f.strace" sh -c "exec $op" ) > "$f.out" 2>&1
    echo "$t arm$arm run$i: exit $?" | tee -a "$o/exits.txt"
    i=$((i + 1))
  done
done
