#!/bin/sh
# Measurements the first review of this record asked for, each one a claim the pages made
# without a transcript or with the wrong one. No Sideeye. Image: Dockerfile.screen3.
#   1. lz4's thread count at the sizes the pages quote, and which thread writes (screen-strace.py).
#   2. ninja killed for real after `cp`'s truncating open — probe-ninja.sh's part 2 SIGKILLed only
#      the stand-in's own process group (ninja puts each command in its own), so ninja exited 1
#      after a failed edge rather than dying.
#   3. The rebuild leg of check-ninja-recovery.sh, falsified: a state where ninja does NOT rebuild
#      an empty out.txt, which the leg must reject.
#   4. Both branches of check-xz.sh, falsified: the explore runs falsified only the first.
# The two checkers are cut out of the explore scripts byte for byte, not retyped.
set -u
X=/localrun/review
mkdir -p $X
cp /hostap/screen-strace.py $X/
cut_heredoc() {  # cut_heredoc <script> <checker name> <out>
  awk -v start="cat > \"\$AP/$2\" <<'EOC'" 'index($0,start)==1{on=1;next} on&&$0=="EOC"{exit} on{print}' "$1" > "$3"
  chmod 755 "$3"; echo "  cut $2 from ${1##*/}: $(wc -l < "$3") lines"
}

echo "== 1. lz4 $(lz4 --version 2>&1 | head -1 | tr -s ' ')"
for n in 150000 250000; do
  for args in "-T2" "-T2 -B4"; do
    S=$X/lz4-$n-$(echo "$args" | tr -d ' -'); mkdir -p $S
    python3 -c "
import sys
with open('$S/f.bin','wb') as f:
    for i in range($n): f.write(b'MARKER-%07d-payload\n' % i)"
    strace -f -y -qq -o $S/cap lz4 -q $args --rm $S/f.bin
    echo "  $(( n * 23 )) bytes, lz4 $args:"
    python3 $X/screen-strace.py $S/cap $S | sed 's/^/  /'
  done
done

echo "== 2. ninja $(ninja --version), killed for real between cp's truncating open and its copy"
setup() {
  mkdir -p "$1"
  printf 'rule cp\n  command = cp $in $out\nbuild out.txt: cp in.txt\n' > "$1/build.ninja"
  printf 'MARKER first content\n' > "$1/in.txt"
  ninja -C "$1" > /dev/null
  touch -d 2026-01-01T00:00:00 "$1/out.txt"
  printf 'MARKER second content\n' > "$1/in.txt"
}
show() { printf '  out.txt %s bytes, in.txt %s bytes, .ninja_log lines %s\n' "$(wc -c < "$1/out.txt")" "$(wc -c < "$1/in.txt")" "$(wc -l < "$1/.ninja_log")"; }
S=$X/ninja-kill; setup $S
mkdir -p $X/killbin
cat > $X/killbin/cp <<'EOK'
#!/bin/sh
# Truncate the destination the way cp's open does, then SIGKILL every ninja, then this shell.
: > "$2"
pkill -KILL -x ninja
kill -KILL $$
EOK
chmod 755 $X/killbin/cp
( cd $S && PATH=$X/killbin:$PATH ninja > $X/ninja-kill.out 2>&1 ); rc=$?
echo "  the killed build: rc=$rc (137 = SIGKILL); its output:"; sed 's/^/  | /' $X/ninja-kill.out
show $S
ninja -C $S -d explain 2>&1 | sed 's/^/  | /'
show $S
cmp -s $S/out.txt $S/in.txt && echo "  RESULT 2: rebuilt, out.txt == in.txt" || echo "  RESULT 2: out.txt != in.txt after the next build"

echo "== 3. check-ninja-recovery.sh's rebuild leg, on a state ninja does not rebuild"
cut_heredoc /hostap/explore-ninja-recovery.sh check-ninja-recovery.sh $X/check-ninja-recovery.sh
S=$X/ninja-stale; setup $S
ninja -C $S > /dev/null            # build the second content, so the log records a recent mtime
: > $S/out.txt                     # the output emptied, mtime now
touch -d 2025-01-01T00:00:00 $S/in.txt   # the input older than both the output and the log's record
show $S
ninja -C $S -n -d explain 2>&1 | sed 's/^/  | ninja -n: /'
SD=$S $X/check-ninja-recovery.sh; echo "  checker rc=$? (must be 1)"

echo "== 4. check-xz.sh, every branch"
cut_heredoc /hostap/explore.sh check-xz.sh $X/check-xz.sh
mkdir -p /localrun/aux
python3 -c "
with open('/localrun/aux/xz.orig','wb') as f:
    for i in range(250000): f.write(b'MARKER-%07d-payload\n' % i)"
case_() {  # case_ <label> <expected rc>, state already in $SD
  SD=$SD $X/check-xz.sh > $X/xzc.out 2>&1; rc=$?
  printf '  %-58s rc=%s (expected %s) %s\n' "$1" "$rc" "$2" "$(head -1 $X/xzc.out)"
}
SD=$X/xz; mkdir -p $SD
cp /localrun/aux/xz.orig $SD/f.bin;                                   case_ "f.bin intact, no f.bin.xz" 0
xz -q -k -T2 --block-size=1MiB -c $SD/f.bin > $X/full.xz
half=$(( $(wc -c < $X/full.xz) / 2 )); echo "  the complete .xz is $(wc -c < $X/full.xz) bytes; a partial one is its first $half"
head -c $half $X/full.xz > $SD/f.bin.xz;                             case_ "f.bin intact, a partial f.bin.xz beside it" 0
head -c 1000 /localrun/aux/xz.orig > $SD/f.bin;                       case_ "f.bin torn (1000 bytes)" 1
rm -f $SD/f.bin; cp $X/full.xz $SD/f.bin.xz;                          case_ "f.bin gone, the complete f.bin.xz" 0
head -c $half $X/full.xz > $SD/f.bin.xz;                             case_ "f.bin gone, a partial f.bin.xz" 1
: > $SD/f.bin.xz;                                                      case_ "f.bin gone, an empty f.bin.xz" 1
head -c 1000 /localrun/aux/xz.orig | xz -q -c > $SD/f.bin.xz;         case_ "f.bin gone, an f.bin.xz of other content" 1
rm -f $SD/f.bin.xz;                                                    case_ "neither" 1
echo "  what a re-run of the define's command (without -q, to see the message) does beside a partial f.bin.xz:"
cp /localrun/aux/xz.orig $SD/f.bin; head -c $half $X/full.xz > $SD/f.bin.xz
xz -T2 --block-size=1MiB $SD/f.bin > $X/rerun.out 2>&1; rc=$?
sed 's/^/  | /' $X/rerun.out; echo "  xz rc=$rc; f.bin $( [ -f $SD/f.bin ] && echo present || echo absent), $(cmp -s $SD/f.bin /localrun/aux/xz.orig && echo identical to the original || echo NOT identical to the original); f.bin.xz $(wc -c < $SD/f.bin.xz) bytes"
