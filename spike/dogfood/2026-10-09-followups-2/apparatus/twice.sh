#!/bin/sh
# The next step `baseline_violates_invariant` and `--twice` refusals name: `sideeye preflight --twice`,
# which says which paths two clean runs leave differently and, since #688 (v1.10.0), where in each
# file and what kind of bytes. Run as run.sh runs a define (the same env.sh, seed and toml), once in
# the default mode and, when that is refused before any comparison, once with --observe supervised.
#   docker run --rm --privileged --cgroupns=private --network none \
#       -v <apparatus>:/ap:ro -v <out>:/out sideeye-fu2-1009 sh /ap/twice.sh <target>...
set -u
SE=$(cat /install.path)
for t in "$@"; do
  (
    d=/ap/defines/$t; o=/out/$t; mkdir -p "$o"
    . /ap/env.sh
    [ -f "$d/env.sh" ] && . "$d/env.sh"
    for mode in default supervised; do
      sh "$d/seed.sh" > "$o/twice-seed.log" 2>&1 || { echo "== $t: seed failed"; exit 0; }
      if [ $mode = default ]; then
        "$SE" preflight --config "$d/sideeye.toml" --twice --oracle /usr/bin/strace --work "$o/work-twice-$mode" > "$o/twice-$mode.txt" 2>&1
      else
        "$SE" preflight --config "$d/sideeye.toml" --twice --oracle /usr/bin/strace --observe supervised --work "$o/work-twice-$mode" > "$o/twice-$mode.txt" 2>&1
      fi
      rc=$?
      head1=$(grep -m1 -E '^(PREFLIGHT|UNKNOWN|SETUP)' "$o/twice-$mode.txt" | tr -s ' ' | cut -c1-90)
      echo "== $t $mode rc=$rc: $head1"
      grep -E '^(repeatability|  |bytes|differ)' "$o/twice-$mode.txt" | grep -i -E 'differ|bytes|path|left|equal' | head -12 | cut -c1-200
      case "$head1" in *no_shim_marker*|*unsupported_syscall*|*child_process*) continue ;; *) break ;; esac
    done
  )
done
