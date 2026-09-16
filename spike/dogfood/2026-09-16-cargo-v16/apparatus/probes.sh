#!/bin/sh
# The probes behind transcripts/probes.txt — what a diff review asked to see in a record rather
# than in prose (R1 P1-5/P1-6, R2 P1-4/P2-5/P2-6). No Sideeye involved. Runs in the same image as
# run.sh, with this directory at /hostap and the record's transcripts/ at /out:
#
#   docker run --rm --network none -v <this dir>:/hostap:ro -v <record>/transcripts:/out \
#       sideeye-dogfood:2026-09-16-cargo sh /hostap/probes.sh
#
#   1. which processes `cargo add` execs (the report says "2 other process(es) observed")
#   2. an empty Cargo.lock — the state the explored world leaves — under cargo's own reader
#   3. a torn Cargo.lock without any tool: only the lockfile crosses a file-size limit
#   4. what the commands after a torn lock do
set -u
OUT=/out
export CARGO_ROOT=/localrun/probe
sh /hostap/setup.sh > /dev/null 2>&1
S=$CARGO_ROOT/state; export CARGO_HOME=$CARGO_ROOT/home
{
echo "=== 1. which processes cargo add execs: strace -f -e trace=execve ==="
strace -f -e trace=execve -o /tmp/execve.log cargo add --offline --manifest-path "$S/Cargo.toml" --path "$CARGO_ROOT/depcrate" > /dev/null 2>&1; echo "cargo add rc=$?"
echo "execve lines: $(grep -c 'execve(' /tmp/execve.log)"; grep 'execve(' /tmp/execve.log | sed 's/^/  /' | cut -c1-160
echo
echo "=== 2. an empty Cargo.lock, the state the explored world leaves, under cargo's own reader ==="
cp "$S/Cargo.lock" /tmp/lock.complete; echo "complete lock: $(wc -c < /tmp/lock.complete) bytes"
: > "$S/Cargo.lock"; echo "emptied: $(wc -c < "$S/Cargo.lock") bytes"
cargo metadata --offline --format-version 1 --manifest-path "$S/Cargo.toml" > /dev/null 2>/tmp/meta.err; echo "cargo metadata rc=$? stderr_lines=$(wc -l < /tmp/meta.err)"; sed 's/^/  stderr: /' /tmp/meta.err
echo "after metadata: $(wc -c < "$S/Cargo.lock") bytes; identical to the complete lock: $(cmp -s "$S/Cargo.lock" /tmp/lock.complete && echo yes || echo no)"
echo
echo "=== 3. a torn Cargo.lock without any tool: 19 path dependencies, then cargo add under ulimit -f 2 (1024-byte cap) ==="
C=/localrun/torn; rm -rf "$C"; mkdir -p "$C/state/src" "$C/home"
printf '[package]\nname = "app"\nversion = "0.1.0"\nedition = "2021"\n\n[dependencies]\n' > "$C/state/Cargo.toml"
printf 'pub fn probe() -> u32 { 42 }\n' > "$C/state/src/lib.rs"
for i in $(seq 1 20); do
  mkdir -p "$C/dep$i/src"
  printf '[package]\nname = "dep%s"\nversion = "0.1.0"\nedition = "2021"\n' "$i" > "$C/dep$i/Cargo.toml"
  printf 'pub fn f() {}\n' > "$C/dep$i/src/lib.rs"
  [ "$i" -lt 20 ] && printf 'dep%s = { path = "../dep%s" }\n' "$i" "$i" >> "$C/state/Cargo.toml"
done
export CARGO_HOME="$C/home"
cargo generate-lockfile --offline --manifest-path "$C/state/Cargo.toml" > /dev/null 2>&1
echo "before: Cargo.lock $(wc -c < "$C/state/Cargo.lock") bytes, Cargo.toml $(wc -c < "$C/state/Cargo.toml") bytes"
sh -c "ulimit -f 2; cargo add --offline --manifest-path $C/state/Cargo.toml --path $C/dep20" > /tmp/add.out 2>&1; echo "cargo add rc=$?"; sed 's/^/  /' /tmp/add.out | tail -3
echo "after: Cargo.lock $(wc -c < "$C/state/Cargo.lock") bytes, Cargo.toml $(wc -c < "$C/state/Cargo.toml") bytes, dep20 in the manifest: $(grep -c dep20 "$C/state/Cargo.toml")"
echo "last line of the torn lock: $(tail -c 60 "$C/state/Cargo.lock" | tr '\n' '|')"
echo
echo "=== 4. what the commands after a torn lock do ==="
for cmd in "metadata --offline --format-version 1" "build --offline" "tree --offline"; do
  cargo $cmd --manifest-path "$C/state/Cargo.toml" > /dev/null 2>/tmp/cmd.err; echo "cargo $cmd: rc=$? — $(head -1 /tmp/cmd.err | cut -c1-90)"
done
echo "Cargo.lock still: $(wc -c < "$C/state/Cargo.lock") bytes"
} 2>&1 | tee "$OUT/probes.txt"
