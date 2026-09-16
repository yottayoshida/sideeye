#!/bin/sh
# Two follow-ups to nvim-v2.sh, both binaries, no Sideeye.
#  A. What differs between two clean runs, with timestamps recognised in both msgpack encodings.
#     nvim-v2.sh part 6 knew only uint32 (0xce); 0.12.5 writes the header's timestamp as a uint64
#     (0xcf) and part 6 printed False for the one pair that crossed a second.
#  B. The session after a kill in the window 0.12.5 still has: main.shada removed, the complete
#     temporary not yet renamed. The world is made by hand (the setup, then the operation's shada
#     moved to main.shada.tmp.a), then nvim is started and quit the ordinary way, twice.
set -u
export HOME=/tmp/h XDG_STATE_HOME=/tmp/s; mkdir -p $HOME $XDG_STATE_HOME
printf 'call histadd("cmd", "echo first")\ncall setreg("a", "first register")\nwshada!\nqa!\n' > /tmp/setup.vim
printf 'call histadd("cmd", "echo second")\nwshada\nqa!\n' > /tmp/op.vim
printf 'call writefile([getreg("a")] + split(execute("history cmd"), "\\n"), "/tmp/read.txt")\nqa!\n' > /tmp/read-and-write.vim
for bin in nvim nvim012; do
  echo "== A. $bin"
  base=/tmp/det-$bin; mkdir -p $base; $bin --headless -n -u NONE -i $base/main.shada -S /tmp/setup.vim > /dev/null 2>&1
  for r in 1 2 3; do d=/tmp/det-$bin-r$r; mkdir -p $d; cp $base/main.shada $d/; $bin --headless -n -u NONE -i $d/main.shada -S /tmp/op.vim > /dev/null 2>&1; [ $r = 1 ] && sleep 1; done
  python3 - /tmp/det-$bin-r1/main.shada /tmp/det-$bin-r2/main.shada /tmp/det-$bin-r3/main.shada <<'PY'
import sys, struct, time
data = [open(p, 'rb').read() for p in sys.argv[1:4]]
now = int(time.time())
def spans(buf):
    out = []
    for i in range(len(buf) - 4):
        if buf[i] == 0xce and abs(struct.unpack('>I', buf[i+1:i+5])[0] - now) < 86400: out.append((i + 1, i + 4, "uint32 timestamp"))
        if buf[i] == 0xcf and i + 9 <= len(buf) and abs(struct.unpack('>Q', buf[i+1:i+9])[0] - now) < 86400: out.append((i + 1, i + 8, "uint64 timestamp"))
    k = buf.find(b"pid")
    if k >= 0: out.append((k + 3, k + 7, "header pid"))
    return out
for i, j, label in [(0, 1, "r1 vs r2, one second apart"), (1, 2, "r2 vs r3, back to back")]:
    a, b = data[i], data[j]
    diffs = [x for x in range(min(len(a), len(b))) if a[x] != b[x]]
    s = spans(a)
    where = [next((n for lo, hi, n in s if lo <= d <= hi), "UNEXPLAINED") for d in diffs]
    print(f"  {label}: sizes {len(a)}/{len(b)}, differing offsets {diffs} -> {where}")
PY
  echo "== B. $bin: killed between the unlink and the rename, then two ordinary sessions"
  w=/tmp/win-$bin; mkdir -p $w /tmp/op-$bin
  $bin --headless -n -u NONE -i $w/main.shada -S /tmp/setup.vim > /dev/null 2>&1
  cp $w/main.shada /tmp/op-$bin/main.shada; $bin --headless -n -u NONE -i /tmp/op-$bin/main.shada -S /tmp/op.vim > /dev/null 2>&1
  rm -f $w/main.shada; cp /tmp/op-$bin/main.shada $w/main.shada.tmp.a
  echo "  the world: $(ls $w | tr '\n' ' ')(main.shada.tmp.a $(wc -c < $w/main.shada.tmp.a) bytes, the complete new file)"
  for s in 1 2; do
    : > /tmp/read.txt
    $bin --headless -n -u NONE -i $w/main.shada -S /tmp/read-and-write.vim > /tmp/sess.out 2>&1; rc=$?
    echo "  session $s: rc=$rc; it read register \"$(sed -n 1p /tmp/read.txt)\", history: $(sed -n '2,$p' /tmp/read.txt | grep -c 'echo') entries; afterwards: $(for f in $(ls $w); do printf '%s(%s) ' $f $(wc -c < $w/$f); done); says: $(grep -o 'E1[0-9][0-9][^"]*' /tmp/sess.out | head -1 | cut -c1-100)"
  done
done
