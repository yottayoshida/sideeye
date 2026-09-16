#!/bin/sh
# Without Sideeye: the world ninja's explorations flagged, made by hand. After the setup's
# build, in.txt changes, and the next build is killed after `cp` opened out.txt for truncation
# and before it wrote — out.txt is empty, its mtime is now, and .ninja_log still holds only the
# setup's entry. Question: does the next `ninja` rebuild out.txt?
#   Part 1 builds that state with `: >` (truncation, fresh mtime, no ninja involved).
#   Part 2 makes it the way a crash would: ninja runs the edge under a cp that is SIGKILLed
#   (with ninja itself) the moment it has opened out.txt, via a wrapper on PATH.
#   (It did not: the stand-in's `kill -KILL 0` reaches its own process group, ninja gives
#   each command a group of its own, and ninja exited 1 after a failed edge. probe-review.sh
#   part 2 kills ninja for real.)
set -u
show() { printf '  out.txt %s bytes, in.txt %s bytes; ' "$(wc -c < "$1/out.txt")" "$(wc -c < "$1/in.txt")"; tail -n +2 "$1/.ninja_log" | wc -l | sed 's/^ */.ninja_log entries: /'; }
setup() {
  mkdir -p "$1"
  printf 'rule cp\n  command = cp $in $out\nbuild out.txt: cp in.txt\n' > "$1/build.ninja"
  printf 'MARKER first content\n' > "$1/in.txt"
  ninja -C "$1" > /dev/null
  touch -d 2026-01-01T00:00:00 "$1/out.txt"
  printf 'MARKER second content\n' > "$1/in.txt"
}
ninja --version
echo "== part 1: out.txt truncated by hand"
S=/localrun/p1; setup $S
: > "$S/out.txt"
show $S
ninja -C $S -d explain 2>&1 | sed 's/^/  | /'
show $S
cmp -s $S/out.txt $S/in.txt && echo "  RESULT part 1: rebuilt, out.txt == in.txt" || echo "  RESULT part 1: out.txt != in.txt after the next build"

echo "== part 2: the build killed between cp's truncating open and its write"
S=/localrun/p2; setup $S
mkdir -p /localrun/killbin
cat > /localrun/killbin/cp <<'EOK'
#!/bin/sh
# open (truncate) the destination the way cp does, then kill the whole process group of the build
: > "$2"
kill -KILL 0
EOK
chmod 755 /localrun/killbin/cp
( cd $S && PATH=/localrun/killbin:$PATH setsid ninja > /localrun/p2.out 2>&1 ); echo "  killed build rc=$?"
show $S
ninja -C $S -d explain 2>&1 | sed 's/^/  | /'
show $S
cmp -s $S/out.txt $S/in.txt && echo "  RESULT part 2: rebuilt, out.txt == in.txt" || echo "  RESULT part 2: out.txt != in.txt after the next build"
