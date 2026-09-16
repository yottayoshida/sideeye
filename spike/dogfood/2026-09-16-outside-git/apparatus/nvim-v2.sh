#!/bin/sh
# neovim, measured again after the first review of this record found that neovim 0.11 and later
# flush the whole shada file into the temporary before the rename (`packer.packer_flush` at
# `shada_write_exit:` in src/nvim/shada.c from v0.11.0; absent at v0.10.4). Two binaries:
#   nvim     Debian's 0.10.4 (the build the first explorations measured)
#   nvim012  the v0.12.5 release tarball (Dockerfile.nvim012)
# and a second checker, because the first one was shown rejecting only its register branch, never
# its history branch, did not ask nvim when main.shada was absent, and would pass a cut file that
# nvim reports as E576 (the first review). The first checker's explorations stay as they were
# (transcripts/explore/nvim-scratch.*).
#
# Parts, each printing its own section: 1 checker v2 falsified per predicate, per binary;
# 2 the strace order of a :wshada, per binary; 3 preflight, both builds and modes, 0.12.5;
# 4 explorations; 5 ulimit reproductions and a large-file limit scan, per binary; 6 what differs
# between two clean runs, located for every pair.
#   docker run --rm --privileged --network none -v <v1.4.0>:/se140:ro -v <main>:/semain:ro \
#     -v <this dir>:/hostap:ro -v <out>:/out sideeye-dogfood:2026-09-16-outside-nvim012 sh /hostap/nvim-v2.sh
set -u
R=/localrun; AP=$R/ap; AUX=$R/aux; OUT=/out/nvim-v2
mkdir -p "$AP" "$AUX" "$OUT" "$R/wk"
cp /hostap/screen-strace.py "$AP/"
export HOME=$AUX/home TMPDIR=$AUX/tmp XDG_STATE_HOME=$AUX/state XDG_DATA_HOME=$AUX/data XDG_CACHE_HOME=$AUX/cache
mkdir -p "$HOME" "$TMPDIR" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
/se140/sideeye version; /semain/bin/sideeye version; nvim --version | head -1; nvim012 --version | head -1

printf 'call histadd("cmd", "echo first")\ncall setreg("a", "first register")\nwshada!\nqa!\n' > $AUX/nvim-setup.vim
printf 'call histadd("cmd", "echo first")\nwshada!\nqa!\n' > $AUX/nvim-setup-history-only.vim
printf 'call setreg("a", "first register")\nwshada!\nqa!\n' > $AUX/nvim-setup-register-only.vim
printf 'call histadd("cmd", "echo second")\nwshada\nqa!\n' > $AUX/nvim-op.vim
for bin in nvim nvim012; do
  cat > "$AP/setup-$bin.sh" <<EOX
#!/bin/sh
set -eu
mkdir -p "\$SD"
$bin --headless -n -u NONE -i "\$SD/main.shada" -S $AUX/nvim-setup.vim > /dev/null 2>&1
EOX
  # Checker v2: nvim reads the file (through -i, 'shada' cleared before quitting so nothing is
  # written back) and reports register a and the command-line history; any E57x it prints is a
  # failure, and so is a missing register or a missing "echo first" history entry.
  cat > "$AP/check-$bin.sh" <<EOC
#!/bin/sh
f="\$SD/main.shada"
: > /tmp/nvim-check.txt
printf 'call writefile([getreg("a")] + split(execute("history cmd"), "\\\\n"), "/tmp/nvim-check.txt")\\nset shada=\\nqa!\\n' > /tmp/nvim-check.vim
$bin --headless -n -u NONE -i "\$f" -S /tmp/nvim-check.vim > /tmp/nvim-check.err 2>&1
what="\$( [ -f "\$f" ] && echo "\$(wc -c < "\$f") bytes" || echo "absent; files: \$(ls "\$SD" | tr '\\n' ' ')")"
if grep -q 'E57[0-9]' /tmp/nvim-check.err; then echo "nvim reports \$(grep -o 'E57[0-9][^.]*' /tmp/nvim-check.err | head -1 | cut -c1-90) (main.shada \$what)"; exit 1; fi
[ "\$(sed -n 1p /tmp/nvim-check.txt)" = "first register" ] || { echo "register a is lost (main.shada \$what)"; exit 1; }
sed -n '2,\$p' /tmp/nvim-check.txt | grep -q 'echo first' || { echo "the 'echo first' history entry is lost (main.shada \$what)"; exit 1; }
exit 0
EOC
done
chmod 755 "$AP"/*.sh

echo; echo "==================== 1. checker v2, falsified per predicate ===================="
for bin in nvim nvim012; do
  st() { SD=$R/probe/$bin-$1; export SD; rm -rf "$SD"; mkdir -p "$SD"; }
  ck() { "$AP/check-$bin.sh" > /tmp/ck.txt 2>&1; printf '  %-8s %-44s check rc=%s %s\n' "$bin" "$1" "$?" "$(head -1 /tmp/ck.txt | cut -c1-120)"; }
  st setup; "$AP/setup-$bin.sh"; ck "after setup (expect 0)"
  $bin --headless -n -u NONE -i "$SD/main.shada" -S $AUX/nvim-op.vim > /dev/null 2>&1; ck "after the operation (expect 0)"
  cp "$SD/main.shada" /tmp/b; "$AP/check-$bin.sh" > /dev/null 2>&1; cmp -s "$SD/main.shada" /tmp/b && echo "  $bin      the check left main.shada unchanged" || echo "  $bin      the check CHANGED main.shada"
  : > "$SD/main.shada"; ck "main.shada emptied (expect 1)"
  st absent; "$AP/setup-$bin.sh"; mv "$SD/main.shada" "$SD/main.shada.tmp.a"; ck "main.shada absent, complete tmp.a (expect 1)"
  st cut; "$AP/setup-$bin.sh"; n=$(( $(wc -c < "$SD/main.shada") - 20 )); head -c $n "$SD/main.shada" > /tmp/c && cp /tmp/c "$SD/main.shada"; ck "main.shada cut by 20 bytes (expect 1)"
  st noreg; $bin --headless -n -u NONE -i "$SD/main.shada" -S $AUX/nvim-setup-history-only.vim > /dev/null 2>&1; ck "history only, no register (expect 1)"
  st nohist; $bin --headless -n -u NONE -i "$SD/main.shada" -S $AUX/nvim-setup-register-only.vim > /dev/null 2>&1; ck "register only, no history (expect 1)"
done

echo; echo "==================== 2. the strace order of the operation ===================="
for bin in nvim nvim012; do
  SD=$R/st/strace-$bin; export SD; mkdir -p $SD; "$AP/setup-$bin.sh"
  (cd $SD && strace -f -y -qq -o $OUT/$bin.strace $bin --headless -n -u NONE -i $SD/main.shada -S $AUX/nvim-op.vim > /dev/null 2>&1)
  echo "-- $bin: every open for writing, write, fsync, unlink, rename and close on main.shada*"
  grep -n -E '(openat\(.*main\.shada.*O_WRONLY|write\([0-9]+<[^>]*main\.shada|fsync\([0-9]+<[^>]*main\.shada|unlinkat\(.*main\.shada|renameat2?\(.*main\.shada|close\([0-9]+<[^>]*main\.shada)' $OUT/$bin.strace | cut -c1-200
done

echo; echo "==================== 3. preflight, v0.12.5 ===================="
for b in 140 main; do
  case $b in 140) SE=/se140/sideeye; SHIM=/se140/libsideeye_shim.so ;; main) SE=/semain/bin/sideeye; SHIM=/semain/lib/libsideeye_shim.so ;; esac
  for mode in wrappers syscalls; do
    SD=$R/st/pf-$b-$mode; export SD; W=$R/wk/pf-$b-$mode; mkdir -p $SD $W
    (cd $SD && timeout 600 $SE preflight --state $SD --setup $AP/setup-nvim012.sh --operation "nvim012 --headless -n -u NONE -i $SD/main.shada -S $AUX/nvim-op.vim" \
      --shim $SHIM --oracle /usr/bin/strace --observe $mode --work $W > $OUT/nvim012.pf.$b.$mode.txt 2>&1)
    printf '  %-4s %-8s rc=%s  %s\n' $b $mode $? "$(grep -m1 -E '^(UNKNOWN|PREFLIGHT|SETUP)' $OUT/nvim012.pf.$b.$mode.txt | tr -s ' ' | cut -c1-100)"
  done
done

echo; echo "==================== 4. explorations ===================="
ex() {  # ex <bin> <define: plain|scratch> <build> <mode> <i>
  bin=$1; def=$2; b=$3; mode=$4; i=$5
  case $b in 140) SE=/se140/sideeye; SHIM=/se140/libsideeye_shim.so ;; main) SE=/semain/bin/sideeye; SHIM=/semain/lib/libsideeye_shim.so ;; esac
  tag=$bin.$def.$b.$mode.$i; SD=$R/st/$tag; export SD; W=$R/wk/$tag; mkdir -p $SD $W
  extra=""; [ $def = scratch ] && extra="--scratch main.shada"
  (cd $SD && timeout 1800 $SE explore --state $SD --setup $AP/setup-$bin.sh --operation "$bin --headless -n -u NONE -i $SD/main.shada -S $AUX/nvim-op.vim" \
    --check $AP/check-$bin.sh $extra --shim $SHIM --oracle /usr/bin/strace --observe $mode --work $W --json $OUT/$tag.json > $OUT/$tag.txt 2>&1)
  printf '  %-34s rc=%s  %s\n' $tag $? "$(grep -m1 -E '^(PASS|FAIL|UNKNOWN|SETUP ERROR)' $OUT/$tag.txt | tr -s ' ' | cut -c1-90)"
  grep -m2 -E '^ *(earliest|invariant)' $OUT/$tag.txt | tr -s ' ' | sed 's/^/      /' | cut -c1-160
  grep -v '^falsify:' $OUT/$tag.txt | grep -E '^(nvim reports|register a is lost|the .echo first. history)' | sort | uniq -c | sed 's/^/      checker: /' | cut -c1-170
}
for i in 1 2 3; do ex nvim012 plain 140 wrappers $i; done
for i in 1 2 3; do ex nvim012 scratch 140 wrappers $i; done
ex nvim012 scratch 140 syscalls 1
ex nvim012 scratch main wrappers 1
for i in 1 2 3; do ex nvim scratch 140 wrappers $i; done
ex nvim scratch 140 syscalls 1
ex nvim scratch main wrappers 1

echo; echo "==================== 5. without Sideeye: ulimit ===================="
{ i=1; while [ $i -le 400 ]; do printf 'call histadd("cmd", "echo history entry number %04d with some padding text")\n' $i; i=$((i+1)); done
  printf 'call setreg("a", "first register")\nwshada!\nqa!\n'; } > $AUX/large-setup.vim
printf 'call writefile([getreg("a"), string(len(split(execute("history cmd"), "\\n")) - 1)], "/tmp/read.txt")\nset shada=\nqa!\n' > $AUX/read.vim
for bin in nvim nvim012; do
  d=$R/ul/$bin-small; mkdir -p $d; $bin --headless -n -u NONE -i $d/main.shada -S $AUX/nvim-setup.vim > /dev/null 2>&1; before=$(wc -c < $d/main.shada)
  ( ulimit -f 0; $bin --headless -n -u NONE -i $d/main.shada -S $AUX/nvim-op.vim ) > /dev/null 2>&1; rc=$?
  echo "  $bin small file, ulimit -f 0: rc=$rc, main.shada $before -> $( [ -f $d/main.shada ] && wc -c < $d/main.shada || echo absent) bytes; files: $(ls $d | tr '\n' ' ')"
  base=$R/ul/$bin-base; mkdir -p $base; $bin --headless -n -u NONE -i $base/main.shada -S $AUX/large-setup.vim > /dev/null 2>&1; full=$(wc -c < $base/main.shada)
  echo "  $bin large file: $full bytes; limits from 512 bytes below the file size to 512 bytes above it, and a coarse sweep below"
  for bytes in 4096 8192 16384 $((full/512*512 - 1024)) $((full/512*512 - 512)) $((full/512*512)) $((full/512*512 + 512)); do
    d=$R/ul/$bin-$bytes; rm -rf $d; mkdir -p $d; cp $base/main.shada $d/
    ( ulimit -f $((bytes/512)); $bin --headless -n -u NONE -i $d/main.shada -S $AUX/nvim-op.vim ) > /dev/null 2>&1; rc=$?
    : > /tmp/read.txt; $bin --headless -n -u NONE -i $d/main.shada -S $AUX/read.vim > $d/read.out 2>&1
    printf '    limit %6d: rc=%-3s main.shada %6s bytes, files: %-32s next read: register "%s", %s history lines; %s\n' $bytes $rc \
      "$( [ -f $d/main.shada ] && wc -c < $d/main.shada || echo absent)" "$(ls $d | grep -v '\.out$' | tr '\n' ' ')" "$(sed -n 1p /tmp/read.txt)" "$(sed -n 2p /tmp/read.txt)" "$(grep -m1 -o 'E57[0-9][^"]*' $d/read.out | cut -c1-80)"
  done
done

echo; echo "==================== 6. what differs between two clean runs ===================="
for bin in nvim nvim012; do
  base=$R/det/$bin-base; mkdir -p $base; $bin --headless -n -u NONE -i $base/main.shada -S $AUX/nvim-setup.vim > /dev/null 2>&1
  for r in 1 2 3; do d=$R/det/$bin-r$r; mkdir -p $d; cp $base/main.shada $d/; $bin --headless -n -u NONE -i $d/main.shada -S $AUX/nvim-op.vim > /dev/null 2>&1; [ $r = 1 ] && sleep 1; done
  python3 - $R/det/$bin-r1/main.shada $R/det/$bin-r2/main.shada $R/det/$bin-r3/main.shada $bin <<'PY'
import sys, struct, time
paths, bin = sys.argv[1:4], sys.argv[4]
data = [open(p, 'rb').read() for p in paths]
now = int(time.time())
def explained(buf, d):
    ts = [i for i in range(len(buf) - 4) if buf[i] == 0xce and abs(struct.unpack('>I', buf[i+1:i+5])[0] - now) < 86400]
    k = buf.find(b"pid")
    return any(t < d <= t + 4 for t in ts) or (k >= 0 and k + 3 <= d <= k + 7)
for (i, j, label) in [(0, 1, "r1 vs r2, one second apart"), (1, 2, "r2 vs r3, back to back")]:
    a, b = data[i], data[j]
    diffs = [x for x in range(min(len(a), len(b))) if a[x] != b[x]]
    print(f"  {bin} {label}: sizes {len(a)}/{len(b)}, differing offsets {diffs}, every one inside a timestamp or the pid: {all(explained(a, d) for d in diffs) and len(a) == len(b)}")
PY
done
