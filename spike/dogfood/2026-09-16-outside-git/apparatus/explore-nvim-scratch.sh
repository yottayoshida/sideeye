#!/bin/sh
# neovim's second define. The first (explore.sh) refused `baseline_violates_invariant` in every run:
# the uncrashed re-run leaves main.shada with other bytes, and probe-shada.sh measured that every
# differing byte is a msgpack timestamp or the header's pid. This define declares main.shada scratch
# (ADR 0043: the built-in invariants judge neither its bytes nor its presence) and the checker —
# the history entry and register the setup stored, read back by nvim — carries the claim.
# Released v1.4.0 wrappers x3 and syscalls x1, main 047592d wrappers x1; --privileged; image Dockerfile.
set -u
R=/localrun
AP=$R/ap
OUT=/out/explore-nvim-scratch
mkdir -p "$AP" "$OUT" "$R/wk"
ONLY=" none " sh /hostap/explore.sh > /dev/null 2>&1
export HOME=$R/aux/home TMPDIR=$R/aux/tmp XDG_STATE_HOME=$R/aux/state XDG_DATA_HOME=$R/aux/data XDG_CACHE_HOME=$R/aux/cache
mkdir -p "$HOME" "$TMPDIR" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
/se140/sideeye version; /semain/bin/sideeye version
run() {  # run <build> <mode> <i>
  b=$1; mode=$2; i=$3
  case $b in 140) SE=/se140/sideeye; SHIM=/se140/libsideeye_shim.so ;;
             main) SE=/semain/bin/sideeye; SHIM=/semain/lib/libsideeye_shim.so ;; esac
  tag=nvim-scratch.$b.$mode.$i
  SD="$R/st/$tag"; export SD; W="$R/wk/$tag"; mkdir -p "$SD" "$W"
  (cd "$SD" && timeout 1800 "$SE" explore --state "$SD" --setup "$AP/setup-nvim.sh" \
    --operation "nvim --headless -n -u NONE -i $SD/main.shada -S /localrun/aux/nvim-op.vim" \
    --check "$AP/check-nvim.sh" --scratch main.shada --shim "$SHIM" --oracle /usr/bin/strace \
    --observe "$mode" --work "$W" --json "$OUT/$tag.json" > "$OUT/$tag.txt" 2>&1)
  printf '%-32s rc=%s  ' "$tag" "$?"
  grep -m1 -E '^(PASS|FAIL|UNKNOWN|SETUP ERROR)' "$OUT/$tag.txt" | tr -s ' ' | cut -c1-120
  grep -m4 -E '^ *(earliest|path |observed|invariant)' "$OUT/$tag.txt" | tr -s ' ' | sed 's/^/    /' | cut -c1-200
}
for i in 1 2 3; do run 140 wrappers $i; done
run 140 syscalls 1
run main wrappers 1
