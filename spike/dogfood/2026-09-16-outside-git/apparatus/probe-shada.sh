#!/bin/sh
# Why two clean runs of neovim's operation leave different main.shada bytes: the same setup state
# copied twice, the operation run on each (one second apart, then twice in the same second), and
# the bytes compared. msgpack entries in a shada file carry a timestamp; the probe prints where the
# copies differ and whether each difference is inside a timestamp or the header's pid. No Sideeye.
set -u
export HOME=/tmp/h XDG_STATE_HOME=/tmp/s; mkdir -p $HOME $XDG_STATE_HOME /tmp/base
printf 'call histadd("cmd", "echo first")\ncall setreg("a", "first register")\nwshada!\nqa!\n' > /tmp/setup.vim
printf 'call histadd("cmd", "echo second")\nwshada\nqa!\n' > /tmp/op.vim
nvim --headless -n -u NONE -i /tmp/base/main.shada -S /tmp/setup.vim
run() { rm -rf "$1"; mkdir -p "$1"; cp /tmp/base/main.shada "$1/"; nvim --headless -n -u NONE -i "$1/main.shada" -S /tmp/op.vim; }
run /tmp/r1; sleep 1; run /tmp/r2; run /tmp/r3
echo "sizes: r1 $(wc -c < /tmp/r1/main.shada), r2 $(wc -c < /tmp/r2/main.shada), r3 $(wc -c < /tmp/r3/main.shada)"
echo "r1 vs r2 (one second apart): $(cmp -l /tmp/r1/main.shada /tmp/r2/main.shada | wc -l) differing bytes"
echo "r2 vs r3 (back to back):     $(cmp -l /tmp/r2/main.shada /tmp/r3/main.shada | wc -l) differing bytes"
python3 - /tmp/r1/main.shada /tmp/r2/main.shada <<'PY'
import sys, struct, time
a, b = open(sys.argv[1], 'rb').read(), open(sys.argv[2], 'rb').read()
diffs = [i for i in range(min(len(a), len(b))) if a[i] != b[i]]
print("differing offsets:", diffs[:16])
now = int(time.time())
# every 0xce (msgpack uint32) followed by a value within a day of now is a timestamp
ts = [i for i in range(len(a) - 4) if a[i] == 0xce and abs(struct.unpack('>I', a[i+1:i+5])[0] - now) < 86400]
print("uint32 values within a day of now, at offsets:", ts)
print("every differing offset inside one of them:", all(any(t < d <= t + 4 for t in ts) for d in diffs))
k = a.find(b"pid")
print("the header's \"pid\" key at offset", k, "- its value starts at", k + 3, ":", a[k+3:k+8].hex())
explained = lambda d: any(t < d <= t + 4 for t in ts) or (k + 3 <= d <= k + 7)
print("every differing offset inside a timestamp or the pid:", all(explained(d) for d in diffs))
PY
