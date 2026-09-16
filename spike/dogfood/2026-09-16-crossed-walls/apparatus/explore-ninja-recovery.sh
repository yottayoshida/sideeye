#!/bin/sh
# ninja's second define. The first (explore.sh) reached FAIL 3/3 on the built-in atomicity
# invariant over out.txt — `cp`'s truncating open with the write not yet done — while its
# checker passed. out.txt is a build output ninja owns, and probe-ninja.sh measured, without
# Sideeye, that the next `ninja` rebuilds an empty out.txt: the build log's recorded mtime is
# older than in.txt's. So this define declares out.txt scratch (ADR 0043: the built-in
# invariants leave it alone) and moves the claim into the checker: after a crash, re-running
# ninja — the documented recovery — ends with out.txt equal to in.txt.
# Released v1.4.0, --observe syscalls, three runs, --privileged; image Dockerfile.screen3.
set -u
R=/localrun
AP=$R/ap
OUT=/out/explore-ninja-recovery
mkdir -p "$AP" "$OUT" "$R/wk"
ONLY=" none " sh /hostap/screen2.sh > /dev/null 2>&1
/se140/sideeye version
cat > "$AP/check-ninja-recovery.sh" <<'EOC'
#!/bin/sh
[ -f "$SD/build.ninja" ] || { echo "build.ninja is missing"; exit 1; }
[ -f "$SD/in.txt" ] || { echo "in.txt is gone"; exit 1; }
grep -q MARKER "$SD/in.txt" || { echo "in.txt lost its MARKER"; exit 1; }
ninja -C "$SD" >/tmp/e.txt 2>&1 || {
  echo "re-running ninja failed: $(tail -2 /tmp/e.txt | tr '\n' ' ' | cut -c1-160)"; exit 1; }
cmp -s "$SD/out.txt" "$SD/in.txt" || {
  echo "after re-running ninja, out.txt ($(wc -c < "$SD/out.txt") bytes) differs from in.txt"; exit 1; }
exit 0
EOC
chmod 755 "$AP"/*.sh
for i in 1 2 3; do
  tag=ninja-recovery.140.syscalls.$i
  SD="$R/st/$tag"; export SD; W="$R/wk/$tag"; mkdir -p "$SD" "$W"
  (cd "$SD" && /se140/sideeye explore --state "$SD" --setup "$AP/setup-ninja.sh" --operation "ninja -C $SD" \
    --check "$AP/check-ninja-recovery.sh" --scratch out.txt --shim /se140/libsideeye_shim.so \
    --oracle /usr/bin/strace --observe syscalls --work "$W" --json "$OUT/$tag.json" > "$OUT/$tag.txt" 2>&1)
  printf '%s rc=%s  ' "$tag" "$?"
  grep -m1 -E '^(PASS|FAIL|UNKNOWN|SETUP ERROR)' "$OUT/$tag.txt"
  grep -E '^(earliest|path |atomicity|checker|scratch)' "$OUT/$tag.txt" | sed 's/^/    /' | cut -c1-220
done
