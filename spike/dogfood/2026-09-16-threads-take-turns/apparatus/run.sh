#!/bin/sh
# The probe run for beets (#539's own target): does a `pthread_join` fall between the two
# threads that open `library.db`? `joinlog.so` (LD_PRELOAD) logs pthread_create / join /
# detach and every open, write, fsync, close and unlink of a path holding "library.db",
# with the calling thread's id, one line per event on fd 2. Sideeye is not involved. Runs in
# the image `Dockerfile.probe` builds, with this directory at /hostap (holding joinlog.so,
# cross-built on the host with `zig cc -target aarch64-linux-gnu -shared -fPIC`) and an
# output directory at /hostout. Three imports from the same seed, one `ls`, and a control:
# plain Python 3.13's `Thread.join()`.
set -u
OUT=/hostout
python3 --version > "$OUT/environment.txt" 2>&1; beet version >> "$OUT/environment.txt" 2>&1
python3 /hostap/mkwav.py /tmp/src.wav
seed=/w/seed; mkdir -p "$seed/lib" "$seed/in1" "$seed/in2"
lame --quiet --tt Track1 --ta Artist1 --tl Album1 /tmp/src.wav "$seed/in1/t1.mp3"
lame --quiet --tt Track2 --ta Artist2 --tl Album2 /tmp/src.wav "$seed/in2/t2.mp3"
mkconf() { printf 'directory: %s/lib\nlibrary: %s/lib/library.db\nimport:\n  copy: yes\n  write: yes\n  quiet: yes\n  autotag: no\n' "$1" "$1" > "$1/config.yaml"; }
mkconf "$seed"
beet -c "$seed/config.yaml" import -q "$seed/in1" > /dev/null 2>&1; echo "seed import rc=$?"
for rep in 1 2 3; do
  SD=/w/st$rep; cp -a "$seed" "$SD"; mkconf "$SD"
  LD_PRELOAD=/hostap/joinlog.so beet -c "$SD/config.yaml" import -q "$SD/in2" > "$OUT/import.$rep.stdout" 2> "$OUT/import.$rep.stderr"
  echo "import rep $rep rc=$?  JL lines: $(grep -c '^JL ' "$OUT/import.$rep.stderr")"
  grep '^JL ' "$OUT/import.$rep.stderr" > "$OUT/import.$rep.jl"
done
SD=/w/ls; cp -a "$seed" "$SD"; mkconf "$SD"
LD_PRELOAD=/hostap/joinlog.so beet -c "$SD/config.yaml" ls > "$OUT/ls.stdout" 2> "$OUT/ls.stderr"
echo "ls rc=$?  JL lines: $(grep -c '^JL ' "$OUT/ls.stderr")"; grep '^JL ' "$OUT/ls.stderr" > "$OUT/ls.jl"
# 対照: 素の python3 が Thread を作って join する（3.13 の Thread.join が pthread_join か）
LD_PRELOAD=/hostap/joinlog.so python3 -c '
import threading
def w(): open("/w/ctl/library.db","w").write("x")
import os; os.makedirs("/w/ctl", exist_ok=True)
t=threading.Thread(target=w); t.start(); t.join(); open("/w/ctl/library.db","a").write("y")' 2> "$OUT/control.stderr"
echo "control rc=$?"; grep '^JL ' "$OUT/control.stderr" > "$OUT/control.jl"; cat "$OUT/control.jl"
