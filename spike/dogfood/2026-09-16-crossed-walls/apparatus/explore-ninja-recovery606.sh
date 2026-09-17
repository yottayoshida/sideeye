#!/bin/sh
# #606 (ADR 0072), run 2026-09-17: ninja's first define — FAIL 3/3 on 2026-09-16 on the built-in
# invariant over out.txt, its checker passing — met again with the recovery ninja documents
# declared: re-run `ninja`. Not a release: the feat/606-recovery-phase branch, cross-built for
# aarch64-linux and mounted at /se606 (bin/ and lib/). The same define runs once without the
# recovery and twice with it, so the verdict can be read against itself.
#
# The recovery checker judges the state, not ninja's exit: in.txt still carries its MARKER,
# out.txt carries one too, and the two are byte-equal. Predicted in this comment before the
# first run: FAIL exit 1 with and without the recovery, the same violations and
# crash points; both controls hold (the junk probe has no MARKER; on the completed state ninja
# has nothing to fix); every exhibit's recovery `pass` — and that `pass` cannot fail, because
# the rebuilt state's timestamps are restore-time, in.txt is newer than the build log's record
# for out.txt, and ninja rebuilds whatever the crash left (the 2026-09-16 second define's reason).
#
# Runs as root in a --privileged container, as explore.sh did, so ninja's `cp` child is judged.
#   docker build -t sideeye-ninja606:2026-09-17 -f Dockerfile.recovery606 .
#   docker run --rm --privileged --network none -v <build prefix>:/se606:ro \
#     -v <this dir>:/hostap:ro -v <out>:/out sideeye-ninja606:2026-09-17 sh /hostap/explore-ninja-recovery606.sh
set -u
R=/localrun
AP=$R/ap
OUT=/out/explore-ninja-recovery606
mkdir -p "$AP" "$OUT" "$R/wk" "$R/st"
ninja --version
/se606/bin/sideeye version
# Which build: the branch is uncommitted while it is measured, so the binary's digest names it.
sha256sum /se606/bin/sideeye /se606/lib/libsideeye_shim.so

# setup-ninja.sh and check-ninja.sh, byte for byte as screen2.sh and explore.sh write them.
cat > "$AP/setup-ninja.sh" <<'EOX'
#!/bin/sh
set -eu
mkdir -p "$SD"
printf 'rule cp\n  command = cp $in $out\nbuild out.txt: cp in.txt\n' > "$SD/build.ninja"
printf 'MARKER first content\n' > "$SD/in.txt"
ninja -C "$SD" >/dev/null 2>&1
touch -d 2026-01-01T00:00:00 "$SD/out.txt"
printf 'MARKER second content\n' > "$SD/in.txt"
EOX
cat > "$AP/check-ninja.sh" <<'EOC'
#!/bin/sh
# The 2026-09-16 checker (spike/dogfood/2026-09-16-userview-3/apparatus/run-r4.sh): after a
# crash, ninja can still read its build directory, and the input is still there.
[ -f "$SD/build.ninja" ] || { echo "build.ninja is missing"; exit 1; }
ninja -C "$SD" -n >/tmp/e.txt 2>&1 || {
  echo "ninja cannot read the build directory: $(head -2 /tmp/e.txt | tr '\n' ' ' | cut -c1-140)"; exit 1; }
[ -f "$SD/in.txt" ] || { echo "in.txt is gone"; exit 1; }
grep -q MARKER "$SD/in.txt" || { echo "in.txt lost its MARKER"; exit 1; }
exit 0
EOC
cat > "$AP/check-ninja-recovered.sh" <<'EOC'
#!/bin/sh
# The recovery checker: what the recovery left, judged by content.
s=${SIDEEYE_STATE_DIR:?}
grep -q MARKER "$s/in.txt" 2>/dev/null || { echo "in.txt lost its MARKER"; exit 1; }
grep -q MARKER "$s/out.txt" 2>/dev/null || { echo "out.txt carries no MARKER ($(wc -c < "$s/out.txt" 2>/dev/null || echo no) bytes)"; exit 1; }
cmp -s "$s/out.txt" "$s/in.txt" || { echo "out.txt differs from in.txt"; exit 1; }
exit 0
EOC
chmod 755 "$AP"/*.sh

run() {  # run <tag> <with-recovery: 0|1>
  tag=$1
  SD="$R/st/$tag"; export SD
  W="$R/wk/$tag"; mkdir -p "$SD" "$W"
  if [ "$2" = 1 ]; then
    set -- --recovery "ninja -C $SD" --recovery-check "$AP/check-ninja-recovered.sh"
  else
    set --
  fi
  (cd "$SD" && /se606/bin/sideeye explore --state "$SD" --setup "$AP/setup-ninja.sh" --operation "ninja -C $SD" \
    --check "$AP/check-ninja.sh" --shim /se606/lib/libsideeye_shim.so --oracle /usr/bin/strace \
    --observe syscalls --work "$W" --json "$OUT/$tag.json" "$@" > "$OUT/$tag.txt" 2>&1)
  printf '%s rc=%s  ' "$tag" "$?"
  head -1 "$OUT/$tag.txt"
  grep -E '^(earliest|explored|checker|recovery)' "$OUT/$tag.txt" | sed 's/^/    /' | cut -c1-600
  python3 - "$OUT/$tag.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
e = d.get("earliest") or {}
c = d.get("checker_earliest") or {}
print("    json: verdict=%s violations=%s earliest=%s %s checker_earliest=%s %s" % (
    d.get("verdict"), d.get("violations"), e.get("crash_point"), e.get("recovery"),
    c.get("crash_point"), c.get("recovery")))
ev = d.get("evidence")
if ev:
    print("    bundle recovery: %s" % json.load(open(ev)).get("recovery"))
PY
}

run ninja.606.syscalls.none 0
run ninja.606.syscalls.recovery.1 1
run ninja.606.syscalls.recovery.2 1
