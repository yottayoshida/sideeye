#!/bin/sh
# Plan steps 4b-4c: each of the four targets under the engine mounted at /eng, in all three
# observation modes, with the strace oracle — the shape 2026-10-02's modes.sh ran vim and fish
# in — and `preflight` first. The question is narrow: does the run still stop at the call #684
# named (getxattr / listxattr / inotify_add_watch), and if not, where does it get to? A run
# that does not reach the oracle comparison answers neither, and summary.txt says which.
set -u
SE=/eng/bin/sideeye
SHIM=/eng/lib/libsideeye_shim.so
. /ap/env.sh
mkdir -p /out
{ echo "engine: $SE"; echo "sha256: $(sha256sum "$SE" | cut -d' ' -f1)"; echo "shim sha256: $(sha256sum "$SHIM" | cut -d' ' -f1)";
  echo "commit: ${ENGINE_COMMIT:-unknown}"; "$SE" version; } > /out/engine.txt
line() { python3 - "$1" <<'EOF' 2>/dev/null || echo "no-json - - -"
import json, sys
d = json.load(open(sys.argv[1]))
print(d.get("verdict"), d.get("unknown_reason") or d.get("setup_error_reason") or "-",
      "oracle=%s" % (d.get("oracle") or "-")[:60].replace(" ", "_"),
      "crash_points=%s" % d.get("crash_points"))
EOF
}
for t in vim fish dotdrop firewalld; do (
    d=/ap/defines/$t; o=/out/$t; mkdir -p "$o"
    [ -f "$d/env.sh" ] && . "$d/env.sh"
    seed() { sh "$d/seed.sh" > "$o/seed.log" 2>&1 || { echo "$t: seed failed: $(tail -1 "$o/seed.log")" | tee -a /out/summary.txt; exit 0; }; }
    for m in wrappers syscalls supervised; do
        seed
        "$SE" explore --config "$d/sideeye.toml" --shim "$SHIM" --oracle /usr/bin/strace --observe "$m" \
            --work "$o/work-$m" --json "$o/$m.json" > "$o/$m.txt" 2>&1
        rc=$?
        echo "$t: $m: exit $rc: $(line "$o/$m.json")" | tee -a /out/summary.txt
        sed -n '1,2p' "$o/$m.txt" | sed 's/^/      | /' | tee -a /out/summary.txt
    done
); done
