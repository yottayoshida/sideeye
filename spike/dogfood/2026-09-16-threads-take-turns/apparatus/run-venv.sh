#!/bin/sh
# The probe run for virtualenv: does a creation or a join fall between the two threads
# that write the environment (the root's mkdir and the site-packages entries)? The same
# probe as run.sh, matching every path under the environment (JL_MATCH), three runs.
set -u
OUT=/hostout
virtualenv --version > "$OUT/venv-environment.txt" 2>&1; python3 --version >> "$OUT/venv-environment.txt" 2>&1
for rep in 1 2 3; do
  SD=/w/venv$rep; mkdir -p "$SD"
  JL_MATCH="$SD/" LD_PRELOAD=/hostap/joinlog.so virtualenv -q --no-download "$SD/v" > "$OUT/venv.$rep.stdout" 2> "$OUT/venv.$rep.stderr"
  echo "virtualenv rep $rep rc=$?  JL lines: $(grep -c '^JL ' "$OUT/venv.$rep.stderr")"
  grep '^JL ' "$OUT/venv.$rep.stderr" > "$OUT/venv.$rep.jl"
done
